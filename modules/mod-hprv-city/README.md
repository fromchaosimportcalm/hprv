# mod-hprv-city

When you're on foot in a capital city, your group bots stop following you at
1.5 yards and stroll around you instead.

| You are... | Your bots... |
|---|---|
| On foot in a capital, out of combat | Walk to a random spot 4–25 yd from you, pause 5–18 s, repeat |
| Mounted, in combat, dead, on a taxi, or out of the city | Follow, as normal |
| More than 60 yd away from a bot | That bot follows until it catches up, then goes back to wandering |

Capitals: Orgrimmar, Thunder Bluff, Undercity, Silvermoon, Stormwind,
Ironforge, Darnassus, the Exodar, Shattrath and Dalaran. The list is
`CITY_ZONES` in `src/HprvCityWander.cpp`.

## How it works

Once a second the module checks your group. For each bot you're master of, it
removes `follow` from the bot's **non-combat** engine and drives the bot with
`MovePoint`. Each destination is raycast from *your* position, so a bot only
ever walks somewhere you could walk in a straight line. When the condition
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
