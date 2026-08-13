# Decisions

This directory is for decisions made **from 2026-08-13 onward**. It is
empty on purpose.

## Where the history went

The predecessor repo carries 14 ADRs recording how this project arrived
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
| `0013` (+ amendment) | `co` persists via `playerbots_db_store`; the bot-tank/human-tank taunt corollary; there is no generic Misdirection |
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
