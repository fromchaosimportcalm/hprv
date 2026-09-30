/*
 * mod-hprv-city — in capital cities, group bots go about their business
 * instead of following at 1.5 yards.
 *
 * While you are on foot in a capital, each bot you're master of drops
 * "follow" from its non-combat engine and takes one of two roles, rolled
 * each time it's taken over:
 *
 *   errands (ERRAND_SHARE)  walks between the city's auctioneers, bankers,
 *                           innkeepers and mailboxes, lingering at each
 *   milling (the rest)      strolls to a random spot near you every few
 *                           seconds, and follows if you get LEASH yards away
 *
 * Mount up, leave the zone or enter combat, and "follow" goes back.
 *
 * The strategy change is in memory only (PlayerbotAI::ChangeStrategy, not
 * the whisper path), so nothing is written to playerbots_db_store. The one
 * exception is Restore(): see SavedWithoutFollow().
 *
 * mod-playerbots itself is untouched, so its pin in scripts/pins.conf holds.
 */

#include "DBCStores.h"
#include "GameTime.h"
#include "Log.h"
#include "Group.h"
#include "Map.h"
#include "MotionMaster.h"
#include "MoveSpline.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "PlayerbotRepository.h"
#include "Playerbots.h"
#include "Random.h"
#include "ScriptMgr.h"

#include <cmath>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
// Zone IDs (not area IDs), checked 2026-09-30 against characters.zone/map.
std::unordered_set<uint32> const CITY_ZONES = {
    1637, 1638, 1497, 3487,  // Orgrimmar, Thunder Bluff, Undercity, Silvermoon City
    1519, 1537, 1657, 3557,  // Stormwind City, Ironforge, Darnassus, The Exodar
    3703, 4395,              // Shattrath City, Dalaran
};

constexpr uint32 TICK_MS = 1000;
constexpr float ERRAND_SHARE = 70.0f;  // percent of bots that run errands rather than mill

constexpr float LEASH = 60.0f;  // milling: further than this, the bot follows until it catches up
constexpr float WANDER_MIN = 4.0f;
constexpr float WANDER_MAX = 25.0f;
constexpr uint32 PAUSE_MIN_MS = 5000;
constexpr uint32 PAUSE_MAX_MS = 18000;

constexpr float CITY_SCAN = 800.0f;    // spawns this close to you are zone-checked, once per city
constexpr float ERRAND_REACH = 150.0f;  // next stop is picked from those this close to the bot
constexpr float JOG = 30.0f;            // further than this from the stop: run, don't walk
constexpr float ARRIVED = 3.0f;
constexpr uint8 MAX_STALLS = 6;  // re-issued moves without getting closer before giving up on a stop

// Where errand bots go. The spawn store has no usable zoneId (0 on every row
// here), so each city's list is built from positions the first time you enter.
enum class PoiKind : uint8 { Auctioneer, Banker, Innkeeper, Mailbox };

struct Poi
{
    PoiKind kind;
    float x, y, z, o;
    uint32 faction;  // creature faction template; 0 for mailboxes
};

std::unordered_map<uint32, std::vector<Poi>> poisByZone;

struct BotState
{
    bool errands = false;
    uint64 nextMs = 0;  // milling: next stroll; errands: when to leave the current stop
    int32 poi = -1;     // errands: stop being walked to or stood at
    int32 lastPoi = -1;
    bool enRoute = false;
    float tx = 0, ty = 0, tz = 0;
    float bestDist = 0;
    uint8 stalls = 0;
};

struct MasterState
{
    uint32 sinceTick = 0;
    std::unordered_map<ObjectGuid, BotState> bots;
};

// Unlocked: only real players reach it, and MapUpdate.Threads = 1 on this box.
std::unordered_map<ObjectGuid, MasterState> masters;

uint64 NowMs() { return static_cast<uint64>(GameTime::GetGameTimeMS().count()); }

uint64 After(uint32 minMs, uint32 maxMs) { return NowMs() + urand(minMs, maxMs); }

std::vector<Poi> const& CityPois(Player* master)
{
    uint32 const zone = master->GetZoneId();
    auto found = poisByZone.find(zone);
    if (found != poisByZone.end())
        return found->second;

    std::vector<Poi>& pois = poisByZone[zone];
    Map* map = master->GetMap();
    uint32 const mapId = master->GetMapId();

    // Distance first: GetZoneId() creates the terrain grid it's asked about.
    auto inCity = [&](float x, float y, float z)
    {
        return master->GetExactDist2d(x, y) <= CITY_SCAN && map->GetZoneId(PHASEMASK_NORMAL, x, y, z) == zone;
    };

    for (auto const& [spawnId, data] : sObjectMgr->GetAllCreatureData())
    {
        if (data.mapid != mapId)
            continue;
        CreatureTemplate const* tmpl = sObjectMgr->GetCreatureTemplate(data.id);
        if (!tmpl)
            continue;

        PoiKind kind;
        if (tmpl->npcflag & UNIT_NPC_FLAG_AUCTIONEER)
            kind = PoiKind::Auctioneer;
        else if (tmpl->npcflag & UNIT_NPC_FLAG_BANKER)
            kind = PoiKind::Banker;
        else if (tmpl->npcflag & UNIT_NPC_FLAG_INNKEEPER)
            kind = PoiKind::Innkeeper;
        else
            continue;

        if (inCity(data.posX, data.posY, data.posZ))
            pois.push_back({kind, data.posX, data.posY, data.posZ, data.orientation, tmpl->faction});
    }

    for (auto const& [spawnId, data] : sObjectMgr->GetAllGOData())
    {
        if (data.mapid != mapId)
            continue;
        GameObjectTemplate const* tmpl = sObjectMgr->GetGameObjectTemplate(data.id);
        if (tmpl && tmpl->type == GAMEOBJECT_TYPE_MAILBOX && inCity(data.posX, data.posY, data.posZ))
            pois.push_back({PoiKind::Mailbox, data.posX, data.posY, data.posZ, data.orientation, 0});
    }

    LOG_INFO("module", "mod-hprv-city: zone {} has {} errand stops", zone, pois.size());
    return pois;
}

bool Welcomes(Poi const& poi, Player* bot)
{
    if (!poi.faction)
        return true;

    FactionTemplateEntry const* npc = sFactionTemplateStore.LookupEntry(poi.faction);
    FactionTemplateEntry const* own = bot->GetFactionTemplateEntry();
    return !npc || !own || !npc->IsHostileTo(*own);
}

void LingerAt(PoiKind kind, BotState& s)
{
    switch (kind)
    {
        case PoiKind::Auctioneer: s.nextMs = After(15000, 45000); break;
        case PoiKind::Banker:     s.nextMs = After(10000, 30000); break;
        case PoiKind::Innkeeper:  s.nextMs = After(20000, 60000); break;
        case PoiKind::Mailbox:    s.nextMs = After(5000, 15000);  break;
    }
}

bool MasterWantsWander(Player* master)
{
    return master->IsAlive() && !master->IsMounted() && !master->IsInFlight() && !master->IsInCombat() &&
           CITY_ZONES.count(master->GetZoneId());
}

bool BotCanWander(Player* bot, Player* master, bool errands)
{
    if (!bot->IsInWorld() || !bot->IsAlive() || bot->IsInCombat() || bot->IsInFlight() ||
        bot->GetMap() != master->GetMap())
        return false;

    return errands ? bot->GetZoneId() == master->GetZoneId() : bot->IsWithinDistInMap(master, LEASH);
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

void MoveBot(Player* bot, float x, float y, float z, bool run)
{
    bot->GetMotionMaster()->MovePoint(0, x, y, z, run ? FORCED_MOVEMENT_RUN : FORCED_MOVEMENT_WALK, 0.0f, 0.0f,
                                      true, false);
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

        MoveBot(bot, x, y, z, false);
        return;
    }
}

void Mill(Player* bot, Player* master, BotState& s)
{
    if (!bot->movespline->Finalized())
        s.nextMs = After(PAUSE_MIN_MS, PAUSE_MAX_MS);  // still walking: pause counts from arrival
    else if (NowMs() >= s.nextMs)
    {
        Stroll(bot, master);
        s.nextMs = After(PAUSE_MIN_MS, PAUSE_MAX_MS);
    }
}

// A spot a few yards in front of an NPC (so bots queue up at the counter) or
// anywhere around a mailbox, raycast from the stop itself.
bool StandingSpot(Player* bot, Poi const& poi, float& x, float& y, float& z)
{
    Map* map = bot->GetMap();
    for (int attempt = 0; attempt < 5; ++attempt)
    {
        float const angle = poi.kind == PoiKind::Mailbox ? frand(0.0f, 2.0f * static_cast<float>(M_PI))
                                                         : poi.o + frand(-0.6f, 0.6f);
        float const dist = poi.kind == PoiKind::Mailbox ? frand(1.5f, 2.5f) : frand(2.5f, 4.5f);
        x = poi.x + dist * std::cos(angle);
        y = poi.y + dist * std::sin(angle);
        z = poi.z;

        if (map->CheckCollisionAndGetValidCoords(bot, poi.x, poi.y, poi.z, x, y, z))
            return true;
    }
    return false;
}

bool PickStop(Player* bot, BotState& s, std::vector<Poi> const& pois)
{
    std::vector<int32> options;
    for (int32 i = 0; i < static_cast<int32>(pois.size()); ++i)
        if (i != s.lastPoi && Welcomes(pois[i], bot) && bot->GetExactDist2d(pois[i].x, pois[i].y) <= ERRAND_REACH)
            options.push_back(i);

    // Wandered off the edge of the cluster: head for whatever is nearest.
    if (options.empty())
    {
        float best = 0;
        for (int32 i = 0; i < static_cast<int32>(pois.size()); ++i)
        {
            float const d = bot->GetExactDist2d(pois[i].x, pois[i].y);
            if (i != s.lastPoi && Welcomes(pois[i], bot) && (options.empty() || d < best))
            {
                options.assign(1, i);
                best = d;
            }
        }
    }

    if (options.empty())
        return false;

    int32 const pick = options[urand(0, options.size() - 1)];
    if (!StandingSpot(bot, pois[pick], s.tx, s.ty, s.tz))
        return false;

    s.poi = pick;
    s.enRoute = true;
    s.stalls = 0;
    s.bestDist = bot->GetExactDist2d(s.tx, s.ty);
    MoveBot(bot, s.tx, s.ty, s.tz, s.bestDist > JOG);
    return true;
}

void RunErrands(Player* bot, Player* master, BotState& s)
{
    std::vector<Poi> const& pois = CityPois(master);
    if (pois.empty())
    {
        Mill(bot, master, s);
        return;
    }

    if (!s.enRoute)
    {
        if (NowMs() >= s.nextMs && !PickStop(bot, s, pois))
            s.nextMs = After(2000, 5000);
        return;
    }

    Poi const& poi = pois[s.poi];
    float const dist = bot->GetExactDist2d(s.tx, s.ty);

    if (dist <= ARRIVED || bot->GetExactDist2d(poi.x, poi.y) <= ARRIVED + 2.0f)
    {
        if (!bot->movespline->Finalized())
            bot->StopMoving();
        bot->SetFacingTo(bot->GetAngle(poi.x, poi.y));
        s.enRoute = false;
        s.lastPoi = s.poi;
        LingerAt(poi.kind, s);
        return;
    }

    if (!bot->movespline->Finalized())
        return;

    // Stopped short: a long path gets cut at ~300 yd, or something bumped it.
    if (dist < s.bestDist - 1.0f)
    {
        s.bestDist = dist;
        s.stalls = 0;
    }
    else if (++s.stalls > MAX_STALLS)
    {
        s.enRoute = false;
        s.lastPoi = s.poi;  // unreachable from here; try somewhere else
        s.nextMs = After(1000, 3000);
        return;
    }

    MoveBot(bot, s.tx, s.ty, s.tz, dist > JOG);
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

            if (!wander)
                continue;  // not in `seen`, so restored below if it was ours

            ObjectGuid const guid = bot->GetGUID();
            auto it = state.bots.find(guid);
            // Roll the role up front so the eligibility check knows which leash applies.
            bool const errands = it != state.bots.end() ? it->second.errands : roll_chance_f(ERRAND_SHARE);

            if (!BotCanWander(bot, master, errands))
                continue;

            if (it == state.bots.end())
            {
                // Only take over bots that are actually following. One told to
                // `stay` or `guard` is left exactly where it was put.
                if (!botAI->HasStrategy("follow", BOT_STATE_NON_COMBAT))
                    continue;

                botAI->ChangeStrategy("-follow", BOT_STATE_NON_COMBAT);
                it = state.bots.emplace(guid, BotState{}).first;
                it->second.errands = errands;
                it->second.nextMs = After(500, 4000);
            }
            else if (botAI->HasStrategy("follow", BOT_STATE_NON_COMBAT))
                // Something reset its strategies (teleport, gear pass). Take it back.
                botAI->ChangeStrategy("-follow", BOT_STATE_NON_COMBAT);

            seen.insert(guid);

            if (it->second.errands)
                RunErrands(bot, master, it->second);
            else
                Mill(bot, master, it->second);
        }
    }

    for (auto it = state.bots.begin(); it != state.bots.end();)
    {
        if (seen.count(it->first))
        {
            ++it;
            continue;
        }

        if (Player* bot = ObjectAccessor::FindConnectedPlayer(it->first))
            Restore(bot);
        it = state.bots.erase(it);
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

        for (auto const& [guid, s] : it->second.bots)
            if (Player* bot = ObjectAccessor::FindConnectedPlayer(guid))
                Restore(bot);

        masters.erase(it);
    }
};

void AddHprvCityWanderScripts() { new HprvCityWanderPlayerScript(); }
