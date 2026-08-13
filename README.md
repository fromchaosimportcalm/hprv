# HPRV — Hellfire Peninsula Retirement Village

A private 3.3.5a AzerothCore server running `mod-playerbots`, where one
human tanks TBC raids for a raid of bots.

- **1 human** prot warrior, main tank
- **24 bots**, a balanced 25-man comp
- **20 more bots** living in the open world as ambient population
- Runs as an LXC on ClintonOps, 4 vCPU / 12 GB, Tank-backed storage
- Furthest kill: **Black Temple** — Naj'entus, Supremus

## Start here

| If you want to… | Read |
|---|---|
| Understand the project and its non-obvious rules | `CLAUDE.md` |
| Play tonight | `docs/raid-night.md` |
| Rebuild the server from nothing | `docs/build.md` |
| Create the container | `docs/host-create.md` |

**If you read only one thing, read the five rules in `CLAUDE.md`.** Four
of the five describe failures that are silent, persistent, and present as
something other than what they are.

## Quick reference

```bash
scripts/roster-status.sh          # level/class/gear/spec for all 25, from the DB
scripts/gear-pass.sh              # force the spec roll, then gear
```

Summon the raid in game (two lines — 24 names exceeds a safe chat length;
`roster-status.sh` prints these ready to paste):

```
.playerbots bot add Ararin,Nathos,Krast,Tanke,Izri,Lomul,Dijito,Celerina,Ilyna,Anmine,Sehjece,Crumm
.playerbots bot add Rechiw,Ralda,Zaene,Muhnun,Fehmos,Dehme,Olidina,Irntifumm,Mutlie,Tengwe,Vestanza,Grohtarty
```

## Layout

```
CLAUDE.md              the brief — read first
docs/
  build.md             standing the server up, phases A-F
  host-create.md       host-side LXC creation
  raid-night.md        session runbook
scripts/
  phase-*.sh           idempotent build/setup scripts
  roster.conf          the 24 bots. Committed so they can be re-summoned
  roster-status.sh     DB-side status report
  gear-pass.sh         spec-then-gear passes
  pins.conf            core + module SHAs — the reproducibility artifact
decisions/             standing rules; history lives in the archive repo
tuning/                BC-feel SQL
```

## Provenance

This is a distillation. It replaces a repo of 36 commits and 14 ADRs that
recorded a long search — three raid compositions in two days, a main tank
that moved to a bot and back, and several config stances that were later
reversed. **That history is preserved in the archive repo**; nothing was
thrown away.

What survived is here, and it is deliberately much smaller. Where the two
disagree, this repo wins: several of the archive's most confident claims
(roster size, random-bot policy, gear tier, RAM) had drifted out of date
against the running server, which is what prompted the rewrite.

Every number in this repo was measured on the box on 2026-08-13. Where a
fact is unverified, it says so.
