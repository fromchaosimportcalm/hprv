# Encounter notes

One file per instance. These are the fights where mod-playerbots does
something specific enough — or fails specifically enough — that knowing
it in advance is the difference between a clean night and a wipe.

| Instance | File |
|---|---|
| Karazhan | `karazhan.md` |
| Zul'Aman | `zulaman.md` |
| Magtheridon's Lair | `magtheridon.md` |
| Black Temple | `black-temple.md` |

`docs/raid-night.md` remains the session runbook — starting up, flags,
summoning, the chat vocabulary, repairs, moving tiers. Come here once
you are standing in front of something.

## What belongs in these files, and what does not

**Durable, so it goes here:** what the module's script for an encounter
does, which roles it resolves and how, the setup that makes it work,
mechanics the bots cannot handle, and the order to do things in. These
change only when the pin moves.

**Volatile, so it goes in an ADR instead:** gear tiers, measured raid
DPS, boss HP totals, and anything else that a gear pass invalidates.
State the mechanic here and cite the ADR for the number. The archive
repo's numbers went stale in several places at once because they were
copied into every document that mentioned them; do not repeat that.

**A decision, so it goes in `decisions/`:** anything a future session
must not re-derive or accidentally reverse. These files describe how to
fight; ADRs record what was settled and why.

## The rule that spans all of them

Raid scripts gate their tank mechanics on `IsTank(bot)` and
`IsMainTank(bot)`, **evaluated inside each bot's own AI**. So *who tanks
decides whether the module's script for a fight runs at all*:

- **The human tanks** — every tank-gated trigger in the instance is dead
  code. The mechanics are yours to execute by hand. This is the accepted
  price of the project's central constraint, not a bug.
- **A bot tanks** (you play a DPS or healer, main-tank flag on
  `Bullwark`) — those triggers fire, and the scripts do their own tank
  positioning and marking.

Neither mode is better everywhere. Karazhan's scripted tank work is
worth having; Black Temple's Council needs assist tanks that rule 1 has
deliberately removed. Decide per instance.

And in both modes, `IsAssistTankOfIndex` requires `IsTank()`, which
rule 1's conversion whisper clears — so assist-tank mechanics stay
unfilled unless you deliberately restore a body. See ADR `0004`.
