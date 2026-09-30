# mod-hprv-city

When you're on foot in a capital city, your group bots stop following you at
1.5 yards and go about their business instead. Each bot rolls a role when it's
taken over:

| Role | Share | What it does |
|---|---|---|
| **Errands** | ~70% | Walks between the city's auctioneers, bankers, innkeepers and mailboxes. It queues a few yards in front of the NPC, faces it and lingers (auction house 15–45 s, bank 10–30 s, inn 20–60 s, mailbox 5–15 s), then picks another stop within 150 yd. It runs to far stops and walks to near ones |
| **Milling** | the rest | Walks to a random spot 4–25 yd from you, pauses 5–18 s, repeats. If you get more than 60 yd away, it follows until it catches up |

Whenever you're mounted, in combat, dead, on a taxi or out of the city, every
bot follows as normal.

Capitals: Orgrimmar, Thunder Bluff, Undercity, Silvermoon, Stormwind,
Ironforge, Darnassus, the Exodar, Shattrath and Dalaran. The list is
`CITY_ZONES` in `src/HprvCityWander.cpp`, and the constants beside it set the
errand share, linger times and distances.

### Errand stops

The world DB's `zoneId` column is 0 for every spawn on this server. So the
first time you enter a city, the module takes the auctioneer, banker and
innkeeper spawns and mailboxes within 800 yd of you and keeps the ones whose
terrain is in that zone. It caches that list per zone until the next restart
and logs `mod-hprv-city: zone N has M errand stops`. Bots skip NPCs hostile to
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
