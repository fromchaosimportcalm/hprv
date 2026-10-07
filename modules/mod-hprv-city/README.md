# mod-hprv-city

When you're on foot in a capital city, your group bots stop following you at
1.5 yards and go about their business instead.

**First, every bot goes shopping, once per city visit.** It runs to one of the
three nearest repair vendors, sells its junk and repairs. Then it rolls a role:

| Role | Share | What it does |
|---|---|---|
| **Errands** | ~70% | Runs between the city's auctioneers, bankers, innkeepers and mailboxes. It queues a few yards in front of the NPC, faces it and lingers (auction house 15–45 s, bank 10–30 s, inn 20–60 s, mailbox 5–15 s), then picks another stop within 150 yd |
| **Milling** | the rest | Runs to a random spot 4–25 yd from you, pauses 5–18 s, repeats. If you get more than 60 yd away, it follows until it catches up |

Whenever you're mounted, in combat, dead, on a taxi or out of the city, every
bot follows as normal.

Capitals: Orgrimmar, Thunder Bluff, Undercity, Silvermoon, Stormwind,
Ironforge, Darnassus, the Exodar, Shattrath and Dalaran. The list is
`CITY_ZONES` in `src/HprvCityWander.cpp`, and the constants beside it set the
errand share, linger times and distances.

### Shopping trip

- **What's sold:** every grey item, plus white weapons and armour. Nothing else:
  food, water, reagents, trade goods, ammo and quest items are kept. So are
  white tools (mining pick, skinning knife, blacksmith hammer, fishing pole),
  shirts and tabards. Only the backpack and bags are touched, never equipped
  gear, the bank or the keyring.
- **Repair:** at normal price with the reputation discount, like a player. An
  item the bot can't afford stays broken.
- **Quiet:** mod-playerbots' own `sell` action whispers you once per item. This
  doesn't. Each bot logs one line to the server log instead:
  `mod-hprv-city: Crumm at Urtharo: sold 4 items for 312c, repaired for 1840c`.
- **Once per visit:** mounting up inside the city doesn't reset it. Leaving the
  zone does.
- **Reagents, where needed.** After repairing, a bot that's below half its stock
  of a reagent one of its own spells uses runs on to one of the three nearest
  reagent vendors and buys back up to stock:

  | Reagent | Stock | For |
  |---|---|---|
  | Symbol of Kings | 100 | paladin greater blessings |
  | Sacred Candle | 40 | Prayer of Fortitude / Spirit / Shadow Protection |
  | Arcane Powder | 40 | Arcane Brilliance |
  | Wild Quillvine | 40 | Gift of the Wild |
  | Flintweed Seed | 10 | Rebirth |
  | Ankh | 10 | Reincarnation |

  Only top-rank spells count, so nobody buys old-rank reagents. A bot with
  enough skips this stop. The list is `REAGENTS` in the source. One log line
  per bot: `mod-hprv-city: Nathos at Horthus: bought 100 reagents for 15000c`.
- **Real vendors only.** Orgrimmar also has test-realm props with vendor and
  repair flags ("[DND] TAR Pedestal - Gems", a bare "Weapons Vendor"). A
  vendor must be selectable and have a subtitle ("Blade Merchant"), and its
  name must not start with `[DND]`.

### Errand stops

The world DB's `zoneId` column is 0 for every spawn on this server. So the
first time you enter a city, the module takes the auctioneer, banker and
innkeeper spawns and mailboxes within 800 yd of you and keeps the ones whose
terrain is in that zone. It caches that list per zone until the next restart
and logs `mod-hprv-city: zone N has M errand stops, K repair vendors, R reagent vendors`. Bots skip NPCs hostile to
their faction, which matters in Shattrath and Dalaran. A city with no stops
found sends every bot milling.

## How it works

Once a second the module checks your group. For each bot you're master of, it
removes `follow` from the bot's **non-combat** engine and drives the bot with
`MovePoint`. Milling spots are raycast from *your* position, and errand spots from
the stop itself, so nobody is sent behind a wall or onto a roof. A path that stops
short (they are cut at ~300 yd) is re-issued, and after six attempts that get no
closer the bot gives up on that stop. When the condition
ends, `follow` goes back.

- **Nothing is written to `playerbots_db_store`.** The module calls
  `PlayerbotAI::ChangeStrategy` directly, not the whisper handler that calls
  `PlayerbotRepository::Save()`.
- **Bots on `stay` or `guard` are left alone.** A bot is only taken over if it
  currently has `follow`.
- **Combat is unaffected.** Only the non-combat engine is touched, and a bot in
  combat is handed back straight away.

## The one trap: whispering `co`/`nc` in a city

A `co`/`nc` whisper to a wandering bot saves its **whole** strategy list
(CLAUDE.md rule 2), and at that moment the list has no `follow`. When the
module hands the bot back, it checks for this: if the saved `nc` row lacks
`+follow`, it re-saves the list with `follow` restored.

That check runs in memory, so a **restart while bots are wandering** skips it.
If a bot stands still after logging in, whisper it `nc +follow`.

## Build

Static module, discovered by CMake from `modules/*/src`. It includes
mod-playerbots headers but doesn't patch them, so the pin in
`scripts/pins.conf` still holds. See `docs/build.md` → *Local modules*.

## Also here: bots wear their own armour type

Not a city feature, but it lives in this module to avoid a CMake re-run.
At the pin, mod-playerbots lets a bot need-roll and equip armour below its
class's type, and takes a death knight for a cloth wearer
(`ItemUsageValue::QueryItemUsageForEquip`: a score comparison overwrites
`CanEquipArmor`'s verdict, and the armour-type guard falls through to
"equip"). On 2026-10-02 two paladins and a DK needed Treads of the Den
Mother (leather), and Crumm wore them.

`HprvArmorTypePlayerScript` hooks `Player::CanUseItem`, which every bot
check goes through, and refuses armour below the bot's own type from level
40: plate for warriors, paladins and DKs, mail for hunters and shamans,
leather for rogues and druids. The bot passes or greeds instead, and never
equips it. Real players, cloaks, shields, relics and jewellery are untouched.

## Also here: Ararin tanks Vashj's Striders, and only in phase 2

Also not a city feature, and in this file for the same reason as the armour
check (no CMake re-run). The module's Lady Vashj script gives Coilfang
Striders to assist tank 0, which has to be a bot that `IsTank()`. But nothing
in that script turns off taunts, so a tank bot in phases 1 and 3 takes Vashj
off you (CLAUDE.md rule 1).

`HprvVashjPlayerScript` checks once a second while you're in Serpentshrine and
Vashj is in combat within 200 yd of you. It switches `VASHJ_STRIDER_TANK`
(`Ararin`):

| When | Combat engine | Non-combat engine |
|---|---|---|
| Phase 1 and 3 | `-tank,-tank assist,+dps,+dps assist` | `-tank assist,+dps assist` |
| Phase 2 (≤70%, Magic Barrier up) | `+tank,+tank assist,-dps,-dps assist` | same |

The strategy names follow rule 1's per-class table, so a warrior, DK or
druid can be named instead. Each of the six strategies is recorded at the
pull, and put back exactly when the fight ends (kill, wipe, leaving, or
your logout). The server log gets one line per switch:
`mod-hprv-city: Vashj phase 2, Ararin tanks the Striders`.

In memory only, like the city wander: nothing is written to
`playerbots_db_store`. **The same trap applies:** a `co`/`nc` whisper to
Ararin mid-fight saves whatever he's holding at that moment.

**It also switches the loot method for the cores.** The Tainted Core is a
white item. Under Group Loot (threshold uncommon), a white item is
round-robin: only the player whose turn it is can loot it
(`LootMgr.cpp:1040`). Normal bot looting is off during Vashj, and the raid
leader is never in the core chain, so when it wasn't the core-looter bot's
turn, the core stayed on the corpse and the shield never dropped. That's
what stalled the first attempt on 2026-10-08: Gerina teleported and tried
to loot every core, and the passers stood waiting all phase. So while the
shield is up, the group is **Free-for-All**. It goes back to its own
method the moment the shield drops (or on a wipe, or your logout), before
Vashj's own loot exists. Log lines: `loot set to Free-for-All for the
cores` and `loot method restored`.
