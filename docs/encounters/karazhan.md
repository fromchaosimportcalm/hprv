# Karazhan

Map 532. `RaidKarazhanStrategy` ("karazhan") is applied automatically on
entry.

The 10-man that auto-logs-in with you is exactly a Karazhan raid, so
this is the instance that costs no setup at all.

---

## Who tanks decides how much of this instance is automated

Ten tank checks across `KaraTriggers.cpp` gate on `IsMainTank(bot)` or
`IsTank(bot)`, evaluated inside each **bot's** own AI. That makes the
mode you play a real choice here, not just a preference:

- **You tank on `Bullwark`** — every one of those triggers is dead code.
  Most are tank positioning and target marking, which a human tank does
  natively and enjoys doing.
- **You play a DPS or healer and let `Bullwark` bot-tank** — with the
  main-tank flag on him (rule 6) those triggers fire and the module does
  its own positioning and marking.

This corrects an earlier claim in `docs/raid-night.md` that they were
simply "dead code" — that is true only in the first mode. Karazhan is
the instance where handing the tanking to a bot buys the most, because
the scripted work here is ordinary tank work rather than the assist-tank
roles rule 1 has removed.

One exception either way: `KaraTriggers.cpp:148` also branches on
`IsAssistTankOfIndex(bot, 0)`, which requires `IsTank()` and therefore
finds nobody in a rule-1-converted raid.

**Two mechanics are yours by hand regardless of mode:**

- **Netherspite's beam rotation.** Yours to call.
- **Prince Malchezaar's Infernals.** `disperse` is your friend.

---

## The Chess event — skip it

mod-playerbots has **no chess code whatsoever**, and the encounter is
built around players charming pieces: uncharmed friendly pieces never
move and cast at half the enemy rate, so "let the AI play it" loses by
design, not by luck.

Open the Gamesman's exit door with `.gobject activate` and move on.
`.instance setbossstate` does not work here.
