/*
 * mod-hprv-city — group bots mill around you in capital cities instead of
 * following at 1.5 yards.
 *
 * While you are on foot in a capital, each of your bots within LEASH yards
 * drops "follow" from its non-combat engine and strolls to a random spot
 * near you every few seconds. Mount up, leave the zone, enter combat or walk
 * off past the leash, and "follow" goes back.
 *
 * The strategy change is in memory only (PlayerbotAI::ChangeStrategy, not
 * the whisper path), so nothing is written to playerbots_db_store. The one
 * exception is Restore(): see SavedWithoutFollow().
 *
 * mod-playerbots itself is untouched, so its pin in scripts/pins.conf holds.
 */

#include "GameTime.h"
#include "Group.h"
#include "Map.h"
#include "MotionMaster.h"
#include "MoveSpline.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "PlayerbotRepository.h"
#include "Playerbots.h"
#include "Random.h"
#include "ScriptMgr.h"

#include <cmath>
#include <unordered_map>
#include <unordered_set>

namespace
{
// Zone IDs (not area IDs), checked 2026-09-30 against characters.zone/map.
std::unordered_set<uint32> const CITY_ZONES = {
    1637, 1638, 1497, 3487,  // Orgrimmar, Thunder Bluff, Undercity, Silvermoon City
    1519, 1537, 1657, 3557,  // Stormwind City, Ironforge, Darnassus, The Exodar
    3703, 4395,              // Shattrath City, Dalaran
};

constexpr uint32 TICK_MS = 1000;
constexpr float LEASH = 60.0f;  // further than this, the bot follows until it catches up
constexpr float WANDER_MIN = 4.0f;
constexpr float WANDER_MAX = 25.0f;
constexpr uint32 PAUSE_MIN_MS = 5000;
constexpr uint32 PAUSE_MAX_MS = 18000;

struct MasterState
{
    uint32 sinceTick = 0;
    std::unordered_map<ObjectGuid, uint64> wanderers;  // bot -> earliest next stroll (game ms)
};

// Unlocked: only real players reach it, and MapUpdate.Threads = 1 on this box.
std::unordered_map<ObjectGuid, MasterState> masters;

uint64 NowMs() { return static_cast<uint64>(GameTime::GetGameTimeMS().count()); }

uint64 NextStroll() { return NowMs() + urand(PAUSE_MIN_MS, PAUSE_MAX_MS); }

bool MasterWantsWander(Player* master)
{
    return master->IsAlive() && !master->IsMounted() && !master->IsInFlight() && !master->IsInCombat() &&
           CITY_ZONES.count(master->GetZoneId());
}

bool BotCanWander(Player* bot, Player* master)
{
    return bot->IsInWorld() && bot->IsAlive() && !bot->IsInCombat() && !bot->IsInFlight() &&
           bot->GetMap() == master->GetMap() && bot->IsWithinDistInMap(master, LEASH);
}

// A co/nc whisper while the bot is wandering makes PlayerbotRepository::Save()
// write the whole strategy list, which at that moment has no "follow" (CLAUDE.md
// rule 2). Left alone, the bot would log in next time and stand still.
bool SavedWithoutFollow(Player* bot)
{
    QueryResult result = PlayerbotsDatabase.Query(
        "SELECT value FROM playerbots_db_store WHERE guid = {} AND `key` = 'nc'", bot->GetGUID().GetCounter());
    if (!result)
        return false;

    for (std::string const& s : split((*result)[0].Get<std::string>(), ','))
        if (s == "+follow")
            return false;

    return true;
}

void Restore(Player* bot)
{
    PlayerbotAI* botAI = GET_PLAYERBOT_AI(bot);
    if (!botAI)
        return;

    botAI->ChangeStrategy("+follow", BOT_STATE_NON_COMBAT);

    if (SavedWithoutFollow(bot))
        PlayerbotRepository::instance().Save(botAI);
}

void Stroll(Player* bot, Player* master)
{
    Map* map = master->GetMap();
    for (int attempt = 0; attempt < 3; ++attempt)
    {
        float const angle = frand(0.0f, 2.0f * static_cast<float>(M_PI));
        float const dist = frand(WANDER_MIN, WANDER_MAX);
        float x = master->GetPositionX() + dist * std::cos(angle);
        float y = master->GetPositionY() + dist * std::sin(angle);
        float z = master->GetPositionZ();

        // Raycast from you, not from the bot: every spot is one you could walk
        // to in a straight line, so nobody ends up behind a wall or on a roof.
        if (!map->CheckCollisionAndGetValidCoords(bot, master->GetPositionX(), master->GetPositionY(),
                                                  master->GetPositionZ(), x, y, z))
            continue;
        if (map->IsInWater(bot->GetPhaseMask(), x, y, z, bot->GetCollisionHeight()))
            continue;

        bot->GetMotionMaster()->MovePoint(0, x, y, z, FORCED_MOVEMENT_WALK, 0.0f, 0.0f, true, false);
        return;
    }
}

void Tick(Player* master, MasterState& state)
{
    bool const wander = MasterWantsWander(master);
    std::unordered_set<ObjectGuid> seen;

    if (Group* group = master->GetGroup())
    {
        for (GroupReference* ref = group->GetFirstMember(); ref; ref = ref->next())
        {
            Player* bot = ref->GetSource();
            if (!bot || bot == master)
                continue;

            PlayerbotAI* botAI = GET_PLAYERBOT_AI(bot);
            if (!botAI || botAI->IsRealPlayer() || botAI->GetMaster() != master)
                continue;

            ObjectGuid const guid = bot->GetGUID();
            auto it = state.wanderers.find(guid);

            if (!wander || !BotCanWander(bot, master))
                continue;  // not in `seen`, so restored below if it was ours

            if (it == state.wanderers.end())
            {
                // Only take over bots that are actually following. One told to
                // `stay` or `guard` is left exactly where it was put.
                if (!botAI->HasStrategy("follow", BOT_STATE_NON_COMBAT))
                    continue;

                botAI->ChangeStrategy("-follow", BOT_STATE_NON_COMBAT);
                it = state.wanderers.emplace(guid, NowMs() + urand(500, 4000)).first;
            }
            else if (botAI->HasStrategy("follow", BOT_STATE_NON_COMBAT))
                // Something reset its strategies (teleport, gear pass). Take it back.
                botAI->ChangeStrategy("-follow", BOT_STATE_NON_COMBAT);

            seen.insert(guid);

            if (!bot->movespline->Finalized())
                it->second = NextStroll();  // still walking: pause counts from arrival
            else if (NowMs() >= it->second)
            {
                Stroll(bot, master);
                it->second = NextStroll();
            }
        }
    }

    for (auto it = state.wanderers.begin(); it != state.wanderers.end();)
    {
        if (seen.count(it->first))
        {
            ++it;
            continue;
        }

        if (Player* bot = ObjectAccessor::FindConnectedPlayer(it->first))
            Restore(bot);
        it = state.wanderers.erase(it);
    }
}
}  // namespace

class HprvCityWanderPlayerScript : public PlayerScript
{
public:
    HprvCityWanderPlayerScript()
        : PlayerScript("HprvCityWanderPlayerScript", {PLAYERHOOK_ON_UPDATE, PLAYERHOOK_ON_LOGOUT})
    {
    }

    void OnPlayerUpdate(Player* player, uint32 diff) override
    {
        PlayerbotAI* ai = GET_PLAYERBOT_AI(player);
        if (ai && !ai->IsRealPlayer())
            return;  // bots don't run this for themselves

        MasterState& state = masters[player->GetGUID()];
        state.sinceTick += diff;
        if (state.sinceTick < TICK_MS)
            return;
        state.sinceTick = 0;

        Tick(player, state);
    }

    void OnPlayerLogout(Player* player) override
    {
        auto it = masters.find(player->GetGUID());
        if (it == masters.end())
            return;

        for (auto const& [guid, next] : it->second.wanderers)
            if (Player* bot = ObjectAccessor::FindConnectedPlayer(guid))
                Restore(bot);

        masters.erase(it);
    }
};

void AddHprvCityWanderScripts() { new HprvCityWanderPlayerScript(); }
