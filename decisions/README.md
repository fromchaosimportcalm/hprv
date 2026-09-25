# Decisions

This directory is for decisions made **from 2026-08-13 onward**.

- `0001` — a standing ten on your own account, and a wider pool summoned
  by name. Records the 10-character client ceiling, the three gates that
  are routinely confused, and why SOAP cannot drive the bot commands.
- `0002` — which character you log in as is a raid decision. Records that
  rule 1 is symmetric (a DPS/healer swap is free, a plate swap is not),
  that `Bullwark` carries no `co` and so bot-tanks unconverted, that
  `Netohje` is retired as the bot-mode main tank, and that the raid does
  have `pull` after all.
- `0003` — raid-frame flags are role assignments. Records that
  `GetMainTankGuid()` honours `MEMBER_FLAG_MAINTANK` without checking
  `IsTank()`, that the assistant flag orders every per-role index, and
  the audit query. **Reverses "do not flag anyone".**
- `0004` — the Illidari Council needs three tank-strategy bodies. Records
  the encounter's role table, that `IsAssistTankOfIndex` gates on
  `IsTank()` so a rule-1-converted raid supplies no assist tanks, and that
  the encounter script disables the taunt behaviour rule 1 exists to
  prevent. A per-fight toggle, reverted before Illidan.
- `0005` — Black Temple is gated on gear, not tuning. Records the
  Council's 15-minute berserk, the ~4.89M shared pool, the measured
  30–32% DPS shortfall, and the rule that no HP restore lands here until
  the enrage is beaten.
- `0006` — reset the roster to Tier 4. Records the 354 pieces deleted
  above ilvl 125, the backups, that `AutoGearScoreLimit` gates only
  `autogear` and not drops, and that Bullwark's defence floor needs
  re-itemizing before he tanks.
- `0007` — one of each class in the standing ten, and a 25 on top of it.
  Records the new ten and 25, and that the swap found `playerbots_db_store`
  empty and the rule-1 whisper wrong (per-class `co` + `nc` now).
  Amended: Crumm goes frost, so the ten has one tank and no conversion.

## Where the history went

The predecessor repo, `hprv-archive`, carries 14 ADRs recording how this project arrived
at its current shape. They are preserved there and are worth reading if
you need to know *why* something is the way it is — several document
real module internals at this pin, with file-and-line citations that are
still accurate.

They are **not** carried forward here, because most of them argue with
each other. The sequence included:

- the main tank moving from the human to a bot, and back again
- three raid compositions in two days
- a `co -threat` prescription that was correct for a two-bot-tank raid
  and is actively wrong for this one
- a random-bot policy set to zero, then quietly reversed on the box
- a roster size closed at "nine, permanently", then run at 25

Reading them in order teaches the search. Reading them for guidance is a
good way to do the wrong thing confidently.

**The conclusions that survived are in `CLAUDE.md` as the five rules, and
in the comment blocks of `scripts/roster.conf`.** That is deliberate:
they now live next to the thing they govern instead of in a file you have
to know to go looking for.

## Findings still worth citing from the archive

If you need the receipts, these are the ADRs that hold them:

| Archive ADR | What it proves |
|---|---|
| `0013` (+ amendment) | `co` persists via `playerbots_db_store`; the bot-tank/human-tank taunt corollary. **Its "there is no generic Misdirection" finding is false at this pin** — `GenericHunterStrategy.cpp:68` wires `low tank threat` to `misdirection on main tank`. Corrected 2026-08-15; see ADR `0003` |
| `0014` | Why the human tanks, and what the nine dead Karazhan triggers actually cost |
| `0007` | A respec never re-gears — `init=` rolls spec *then* gears |
| `0008` | The tank defence floor is met by hand-picking items, not by tier |
| `0005` | Why the roster comes from the AddClass pool (and why that forecloses persistence) |
| `0001` | Why core and module are pinned to a single upstream merge |

## Writing new ones

Same haven-log flow as before, numbered from `0001` in this repo. Log a
decision when it is a **standing rule** — something a future session must
not re-derive or accidentally reverse.

Do not log the search that led to it. That is what made the last set
unusable. If a decision reverses an earlier one, say so in the file and
correct `CLAUDE.md` in the same commit, so the brief never disagrees with
the record.

**And check the box before writing.** The single biggest failure of the
archive was documents that stayed confident while the server moved
underneath them.
