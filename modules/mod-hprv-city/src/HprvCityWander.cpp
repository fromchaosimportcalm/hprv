/*
 * mod-hprv-city — in capital cities, group bots go about their business
 * instead of following at 1.5 yards.
 *
 * While you are on foot in a capital, each bot you're master of drops
 * "follow" from its non-combat engine. Its first job is a shopping trip: run
 * to a nearby repair vendor, sell grey items and white weapons/armour, and
 * repair. Once per visit. A bot low on raid-buff reagents then runs on to
 * a reagent vendor and tops them up. After that it takes one of two roles,
 * rolled each time it's taken over:
 *
 *   errands (ERRAND_SHARE)  runs between the city's auctioneers, bankers,
 *                           innkeepers and mailboxes, lingering at each
 *   milling (the rest)      jogs to a random spot near you every few
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

#include "Bag.h"
#include "DBCStores.h"
#include "GameTime.h"
#include "Group.h"
#include "ItemPackets.h"
#include "Log.h"
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
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "WorldSession.h"

#include <algorithm>
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
constexpr size_t VENDOR_CHOICE = 3;     // shopping: pick among this many nearest repair vendors
constexpr float ARRIVED = 3.0f;
constexpr uint8 MAX_STALLS = 6;  // re-issued moves without getting closer before giving up on a stop

// What a bot keeps in its bags. It only stocks what one of its own active spells
// uses, goes to a reagent vendor when below half, and buys back up to `stock`.
struct Reagent
{
    uint32 item;
    uint32 stock;
};

std::vector<Reagent> const REAGENTS = {
    {21177, 100},  // Symbol of Kings: paladin greater blessings
    {17029, 40},   // Sacred Candle: Prayer of Fortitude, Spirit, Shadow Protection
    {17020, 40},   // Arcane Powder: Arcane Brilliance
    {22148, 40},   // Wild Quillvine: Gift of the Wild
    {22147, 10},   // Flintweed Seed: Rebirth
    {17030, 10},   // Ankh: Reincarnation
};

enum class PoiKind : uint8 { Auctioneer, Banker, Innkeeper, Mailbox, Vendor };

struct Poi
{
    PoiKind kind;
    float x, y, z, o;
    uint32 entry;    // creature entry; 0 for mailboxes
    uint32 faction;  // creature faction template; 0 for mailboxes
};

// The spawn store has no usable zoneId (0 on every row here), so each city's
// lists are built from positions the first time you enter it.
struct City
{
    std::vector<Poi> stops;    // errand destinations
    std::vector<Poi> vendors;  // repair vendors, for the shopping trip
    std::vector<Poi> reagentVendors;
};

std::unordered_map<uint32, City> cities;

struct BotState
{
    bool errands = false;
    bool shopping = false;
    bool restock = false;  // after shopping: on its way to a reagent vendor
    uint64 nextMs = 0;  // milling: next stroll; otherwise when to leave the current stop
    int32 lastStop = -1;

    bool enRoute = false;
    Poi dest{};
    int32 destStop = -1;  // index into City::stops, or -1 for a vendor
    float tx = 0, ty = 0, tz = 0;
    float bestDist = 0;
    uint8 stalls = 0;
};

struct MasterState
{
    uint32 sinceTick = 0;
    std::unordered_map<ObjectGuid, BotState> bots;
    std::unordered_set<ObjectGuid> shopped;  // this city visit; cleared when you leave
};

// Unlocked: only real players reach it, and MapUpdate.Threads = 1 on this box.
std::unordered_map<ObjectGuid, MasterState> masters;

uint64 NowMs() { return static_cast<uint64>(GameTime::GetGameTimeMS().count()); }

uint64 After(uint32 minMs, uint32 maxMs) { return NowMs() + urand(minMs, maxMs); }

// Test-realm props ("[DND] TAR Pedestal - Gems", a bare "Weapons Vendor")
// carry vendor and repair flags too. Real merchants are selectable and have a
// subtitle.
bool IsRealVendor(CreatureTemplate const* tmpl)
{
    return !(tmpl->unit_flags & UNIT_FLAG_NOT_SELECTABLE) && !tmpl->SubName.empty() &&
           tmpl->Name.rfind("[DND]", 0) != 0;
}

City const& CityOf(Player* master)
{
    uint32 const zone = master->GetZoneId();
    auto found = cities.find(zone);
    if (found != cities.end())
        return found->second;

    City& city = cities[zone];
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
        if (!tmpl || (tmpl->unit_flags & UNIT_FLAG_NOT_SELECTABLE))
            continue;

        bool const repair = (tmpl->npcflag & UNIT_NPC_FLAG_REPAIR) && IsRealVendor(tmpl);
        bool const reagents = (tmpl->npcflag & UNIT_NPC_FLAG_VENDOR_REAGENT) && IsRealVendor(tmpl);
        PoiKind kind;
        if (tmpl->npcflag & UNIT_NPC_FLAG_AUCTIONEER)
            kind = PoiKind::Auctioneer;
        else if (tmpl->npcflag & UNIT_NPC_FLAG_BANKER)
            kind = PoiKind::Banker;
        else if (tmpl->npcflag & UNIT_NPC_FLAG_INNKEEPER)
            kind = PoiKind::Innkeeper;
        else if (repair || reagents)
            kind = PoiKind::Vendor;
        else
            continue;

        if (!inCity(data.posX, data.posY, data.posZ))
            continue;

        Poi const poi{kind, data.posX, data.posY, data.posZ, data.orientation, data.id, tmpl->faction};
        if (kind != PoiKind::Vendor)
            city.stops.push_back(poi);
        if (repair)
            city.vendors.push_back(poi);
        if (reagents)
            city.reagentVendors.push_back(poi);
    }

    for (auto const& [spawnId, data] : sObjectMgr->GetAllGOData())
    {
        if (data.mapid != mapId)
            continue;
        GameObjectTemplate const* tmpl = sObjectMgr->GetGameObjectTemplate(data.id);
        if (tmpl && tmpl->type == GAMEOBJECT_TYPE_MAILBOX && inCity(data.posX, data.posY, data.posZ))
            city.stops.push_back({PoiKind::Mailbox, data.posX, data.posY, data.posZ, data.orientation, 0, 0});
    }

    LOG_INFO("module", "mod-hprv-city: zone {} has {} errand stops, {} repair vendors, {} reagent vendors", zone,
             city.stops.size(), city.vendors.size(), city.reagentVendors.size());
    return city;
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
        case PoiKind::Vendor:     s.nextMs = After(4000, 10000);  break;
    }
}

bool MasterWantsWander(Player* master)
{
    return master->IsAlive() && !master->IsMounted() && !master->IsInFlight() && !master->IsInCombat() &&
           CITY_ZONES.count(master->GetZoneId());
}

// Errands and shopping range over the whole city; only milling is leashed to you.
bool BotCanWander(Player* bot, Player* master, bool cityWide)
{
    if (!bot->IsInWorld() || !bot->IsAlive() || bot->IsInCombat() || bot->IsInFlight() ||
        bot->GetMap() != master->GetMap())
        return false;

    return cityWide ? bot->GetZoneId() == master->GetZoneId() : bot->IsWithinDistInMap(master, LEASH);
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

// Grey anything, plus white weapons and armour. Never consumables, reagents,
// trade goods, ammo, quest items, or white tools (mining pick, skinning knife,
// fishing pole), shirts and tabards.
bool IsJunk(Item* item)
{
    ItemTemplate const* t = item->GetTemplate();
    if (!t->SellPrice || t->Bonding == BIND_QUEST_ITEM)
        return false;

    if (t->Quality == ITEM_QUALITY_POOR)
        return true;

    if (t->Quality != ITEM_QUALITY_NORMAL || t->TotemCategory)
        return false;

    if (t->Class == ITEM_CLASS_WEAPON)
        return t->SubClass != ITEM_SUBCLASS_WEAPON_MISC && t->SubClass != ITEM_SUBCLASS_WEAPON_FISHING_POLE;

    if (t->Class == ITEM_CLASS_ARMOR)
        return t->InventoryType != INVTYPE_BODY && t->InventoryType != INVTYPE_TABARD;

    return false;
}

// Backpack and bags only; equipped gear, the bank and the keyring are never touched.
std::vector<Item*> JunkInBags(Player* bot)
{
    std::vector<Item*> junk;
    for (uint8 slot = INVENTORY_SLOT_ITEM_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
        if (Item* item = bot->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
            if (IsJunk(item))
                junk.push_back(item);

    for (uint8 bagSlot = INVENTORY_SLOT_BAG_START; bagSlot < INVENTORY_SLOT_BAG_END; ++bagSlot)
        if (Bag* bag = bot->GetBagByPos(bagSlot))
            for (uint32 slot = 0; slot < bag->GetBagSize(); ++slot)
                if (Item* item = bag->GetItemByPos(slot))
                    if (IsJunk(item))
                        junk.push_back(item);

    return junk;
}

// The same packet path mod-playerbots' "sell" action uses, minus its
// per-item whisper to you.
void SellAndRepair(Player* bot, Poi const& vendor)
{
    Creature* npc = bot->FindNearestCreature(vendor.entry, 10.0f);
    if (!npc)
        return;

    uint32 const moneyBefore = bot->GetMoney();
    uint32 sold = 0;
    if (bot->GetNPCIfCanInteractWith(npc->GetGUID(), UNIT_NPC_FLAG_VENDOR))
    {
        for (Item* item : JunkInBags(bot))
        {
            WorldPacket p(CMSG_SELL_ITEM);
            p << npc->GetGUID() << item->GetGUID() << item->GetCount();
            WorldPackets::Item::SellItem packet(std::move(p));
            packet.Read();
            bot->GetSession()->HandleSellItemOpcode(packet);
            ++sold;
        }
    }
    uint32 const earned = bot->GetMoney() - moneyBefore;

    // Charged at the normal price; anything it can't afford stays broken.
    uint32 repaired = 0;
    if (bot->GetNPCIfCanInteractWith(npc->GetGUID(), UNIT_NPC_FLAG_REPAIR))
        repaired = bot->DurabilityRepairAll(true, bot->GetReputationPriceDiscount(npc), false);

    LOG_INFO("module", "mod-hprv-city: {} at {}: sold {} items for {}c, repaired for {}c", bot->GetName(),
             npc->GetName(), sold, earned, repaired);
}

// Always at run speed. Walking pace between short stops, then standing still,
// read as zombies shuffling about rather than people with somewhere to be.
// The reagents this bot's active spells use. Lower ranks are learnt but not
// Active, so a level-70 druid wants Wild Quillvine, not Wild Berries.
std::vector<Reagent> ReagentsUsed(Player* bot)
{
    std::unordered_set<uint32> used;
    for (auto const& [spellId, spell] : bot->GetSpellMap())
    {
        if (spell->State == PLAYERSPELL_REMOVED || !spell->Active || !spell->IsInSpec(bot->GetActiveSpec()))
            continue;
        if (SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId))
            for (uint8 i = 0; i < MAX_SPELL_REAGENTS; ++i)
                if (info->Reagent[i] > 0)
                    used.insert(info->Reagent[i]);
    }

    std::vector<Reagent> out;
    for (Reagent const& r : REAGENTS)
        if (used.count(r.item))
            out.push_back(r);
    return out;
}

bool LowOnReagents(Player* bot)
{
    for (Reagent const& r : ReagentsUsed(bot))
        if (bot->GetItemCount(r.item) < r.stock / 2)
            return true;
    return false;
}

bool SellsNeededReagent(Player* bot, uint32 vendorEntry)
{
    VendorItemData const* items = sObjectMgr->GetNpcVendorItemList(vendorEntry);
    if (!items)
        return false;

    for (Reagent const& r : ReagentsUsed(bot))
        if (bot->GetItemCount(r.item) < r.stock / 2)
            for (uint8 i = 0; i < items->GetItemCount(); ++i)
                if (VendorItem const* v = items->GetItem(i); v && v->item == r.item && !v->ExtendedCost)
                    return true;
    return false;
}

// Tops every reagent it uses back up to stock, a stack at a time, through the
// same call the vendor window's buy button reaches.
void BuyReagents(Player* bot, Poi const& vendor)
{
    Creature* npc = bot->FindNearestCreature(vendor.entry, 10.0f);
    if (!npc)
        return;
    VendorItemData const* items = npc->GetVendorItems();
    if (!items)
        return;

    // BuyItemFromVendorSlot reads the slot from this vendor's list unless a
    // gossip-opened vendor is recorded on the session.
    bot->GetSession()->SetCurrentVendor(0);

    uint32 const moneyBefore = bot->GetMoney();
    uint32 bought = 0;
    for (Reagent const& r : ReagentsUsed(bot))
    {
        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(r.item);
        if (!proto || !proto->BuyCount)
            continue;

        int32 slot = -1;
        for (uint8 i = 0; i < items->GetItemCount(); ++i)
            if (VendorItem const* v = items->GetItem(i); v && v->item == r.item && !v->ExtendedCost)
                slot = i;
        if (slot < 0)
            continue;  // this vendor doesn't sell it

        uint32 const lotsPerStack = std::max<uint32>(1, proto->GetMaxStackSize() / proto->BuyCount);
        uint32 have = bot->GetItemCount(r.item);
        while (have < r.stock)
        {
            uint32 const lots = std::min((r.stock - have + proto->BuyCount - 1) / proto->BuyCount, lotsPerStack);
            bot->BuyItemFromVendorSlot(npc->GetGUID(), slot, r.item, lots, NULL_BAG, NULL_SLOT);
            uint32 const now = bot->GetItemCount(r.item);
            if (now <= have)
                break;  // bags full, or out of money
            bought += now - have;
            have = now;
        }
    }

    LOG_INFO("module", "mod-hprv-city: {} at {}: bought {} reagents for {}c", bot->GetName(), npc->GetName(), bought,
             moneyBefore - bot->GetMoney());
}

void MoveBot(Player* bot, float x, float y, float z)
{
    bot->GetMotionMaster()->MovePoint(0, x, y, z, FORCED_MOVEMENT_RUN, 0.0f, 0.0f, true, false);
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

        MoveBot(bot, x, y, z);
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
// anywhere around a mailbox, raycast from the stop itself. Vendors get the
// closest spots, since selling needs interaction range.
bool StandingSpot(Player* bot, Poi const& poi, float& x, float& y, float& z)
{
    Map* map = bot->GetMap();
    for (int attempt = 0; attempt < 5; ++attempt)
    {
        float angle, dist;
        switch (poi.kind)
        {
            case PoiKind::Mailbox:
                angle = frand(0.0f, 2.0f * static_cast<float>(M_PI));
                dist = frand(1.5f, 2.5f);
                break;
            case PoiKind::Vendor:
                angle = poi.o + frand(-0.6f, 0.6f);
                dist = frand(1.5f, 3.0f);
                break;
            default:
                angle = poi.o + frand(-0.6f, 0.6f);
                dist = frand(2.5f, 4.5f);
                break;
        }
        x = poi.x + dist * std::cos(angle);
        y = poi.y + dist * std::sin(angle);
        z = poi.z;

        if (map->CheckCollisionAndGetValidCoords(bot, poi.x, poi.y, poi.z, x, y, z))
            return true;
    }
    return false;
}

bool StartTrip(Player* bot, BotState& s, Poi const& poi, int32 stopIndex)
{
    if (!StandingSpot(bot, poi, s.tx, s.ty, s.tz))
        return false;

    s.dest = poi;
    s.destStop = stopIndex;
    s.enRoute = true;
    s.stalls = 0;
    s.bestDist = bot->GetExactDist2d(s.tx, s.ty);
    MoveBot(bot, s.tx, s.ty, s.tz);
    return true;
}

enum class Trip : uint8 { Walking, Arrived, GaveUp };

Trip Advance(Player* bot, BotState& s)
{
    float const dist = bot->GetExactDist2d(s.tx, s.ty);

    if (dist <= ARRIVED || bot->GetExactDist2d(s.dest.x, s.dest.y) <= ARRIVED + 2.0f)
    {
        if (!bot->movespline->Finalized())
            bot->StopMoving();
        bot->SetFacingTo(bot->GetAngle(s.dest.x, s.dest.y));
        s.enRoute = false;
        return Trip::Arrived;
    }

    if (!bot->movespline->Finalized())
        return Trip::Walking;

    // Stopped short: a long path gets cut at ~300 yd, or something bumped it.
    if (dist < s.bestDist - 1.0f)
    {
        s.bestDist = dist;
        s.stalls = 0;
    }
    else if (++s.stalls > MAX_STALLS)
    {
        s.enRoute = false;
        return Trip::GaveUp;
    }

    MoveBot(bot, s.tx, s.ty, s.tz);
    return Trip::Walking;
}

bool GoToNearbyVendor(Player* bot, BotState& s, std::vector<Poi> const& vendors)
{
    std::vector<Poi> near;
    for (Poi const& v : vendors)
        if (Welcomes(v, bot))
            near.push_back(v);

    std::sort(near.begin(), near.end(), [bot](Poi const& a, Poi const& b)
              { return bot->GetExactDist2d(a.x, a.y) < bot->GetExactDist2d(b.x, b.y); });
    if (near.size() > VENDOR_CHOICE)
        near.resize(VENDOR_CHOICE);

    return !near.empty() && StartTrip(bot, s, near[urand(0, near.size() - 1)], -1);
}

// Returns true while the trip is still going.
bool Shop(Player* bot, Player* master, BotState& s)
{
    if (!s.enRoute)
        return GoToNearbyVendor(bot, s, CityOf(master).vendors);

    switch (Advance(bot, s))
    {
        case Trip::Walking:
            return true;
        case Trip::Arrived:
            SellAndRepair(bot, s.dest);
            LingerAt(PoiKind::Vendor, s);
            return false;
        case Trip::GaveUp:
            s.nextMs = After(1000, 3000);
            return false;
    }
    return false;
}

// The second leg of the shopping trip. Returns true while it's still going.
bool Restock(Player* bot, Player* master, BotState& s)
{
    if (!s.enRoute)
    {
        if (NowMs() < s.nextMs)
            return true;  // still at the repair vendor

        // The reagent flag also marks Inscription Supplies (Xantili in
        // Orgrimmar), who sells none of these. Only vendors that stock
        // something this bot is short of.
        std::vector<Poi> stocked;
        for (Poi const& v : CityOf(master).reagentVendors)
            if (SellsNeededReagent(bot, v.entry))
                stocked.push_back(v);
        return GoToNearbyVendor(bot, s, stocked);
    }

    switch (Advance(bot, s))
    {
        case Trip::Walking:
            return true;
        case Trip::Arrived:
            BuyReagents(bot, s.dest);
            LingerAt(PoiKind::Vendor, s);
            return false;
        case Trip::GaveUp:
            s.nextMs = After(1000, 3000);
            return false;
    }
    return false;
}

bool PickStop(Player* bot, BotState& s, std::vector<Poi> const& stops)
{
    std::vector<int32> options;
    for (int32 i = 0; i < static_cast<int32>(stops.size()); ++i)
        if (i != s.lastStop && Welcomes(stops[i], bot) &&
            bot->GetExactDist2d(stops[i].x, stops[i].y) <= ERRAND_REACH)
            options.push_back(i);

    // Wandered off the edge of the cluster: head for whatever is nearest.
    if (options.empty())
    {
        float best = 0;
        for (int32 i = 0; i < static_cast<int32>(stops.size()); ++i)
        {
            float const d = bot->GetExactDist2d(stops[i].x, stops[i].y);
            if (i != s.lastStop && Welcomes(stops[i], bot) && (options.empty() || d < best))
            {
                options.assign(1, i);
                best = d;
            }
        }
    }

    if (options.empty())
        return false;

    int32 const pick = options[urand(0, options.size() - 1)];
    return StartTrip(bot, s, stops[pick], pick);
}

void RunErrands(Player* bot, Player* master, BotState& s)
{
    std::vector<Poi> const& stops = CityOf(master).stops;
    if (stops.empty())
    {
        Mill(bot, master, s);
        return;
    }

    if (!s.enRoute)
    {
        if (NowMs() >= s.nextMs && !PickStop(bot, s, stops))
            s.nextMs = After(2000, 5000);
        return;
    }

    switch (Advance(bot, s))
    {
        case Trip::Walking:
            break;
        case Trip::Arrived:
            s.lastStop = s.destStop;
            LingerAt(s.dest.kind, s);
            break;
        case Trip::GaveUp:
            s.lastStop = s.destStop;  // unreachable from here; try somewhere else
            s.nextMs = After(1000, 3000);
            break;
    }
}

void Tick(Player* master, MasterState& state)
{
    bool const wander = MasterWantsWander(master);
    // Leaving the city ends the visit; mounting up inside it doesn't.
    if (!CITY_ZONES.count(master->GetZoneId()))
        state.shopped.clear();

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
            bool const shopping = it != state.bots.end() ? it->second.shopping : !state.shopped.count(guid);
            bool const restock = it != state.bots.end() && it->second.restock;

            if (!BotCanWander(bot, master, errands || shopping || restock))
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
                it->second.shopping = shopping;
                it->second.nextMs = After(500, 4000);
            }
            else if (botAI->HasStrategy("follow", BOT_STATE_NON_COMBAT))
                // Something reset its strategies (teleport, gear pass). Take it back.
                botAI->ChangeStrategy("-follow", BOT_STATE_NON_COMBAT);

            seen.insert(guid);
            BotState& s = it->second;

            if (s.shopping)
            {
                if (!Shop(bot, master, s))
                {
                    // Done, or no vendor reachable: either way, once per visit.
                    s.shopping = false;
                    s.restock = LowOnReagents(bot);
                    if (!s.restock)
                        state.shopped.insert(guid);
                }
            }
            else if (s.restock)
            {
                if (!Restock(bot, master, s))
                {
                    s.restock = false;
                    state.shopped.insert(guid);
                }
            }
            else if (s.errands)
                RunErrands(bot, master, s);
            else
                Mill(bot, master, s);
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
