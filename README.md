# HPRV — Hellfire Peninsula Retirement Village

A private 3.3.5a AzerothCore server running `mod-playerbots`, where one
human tanks TBC raids for a raid of bots.

- **1 human** prot warrior, main tank
- **A standing 10-man** on your own account that auto-logs-in with you
- **31 more** pool characters summoned by name for 25-man nights
- **20 more bots** living in the open world as ambient population
- Runs as an LXC on ClintonOps, 4 vCPU / 12 GB, Tank-backed storage
- Furthest kill: **Black Temple** — Naj'entus, Supremus

## Start here

| If you want to… | Read |
|---|---|
| Understand the project and its non-obvious rules | `CLAUDE.md` |
| Play tonight | `docs/raid-night.md` |
| Fight a specific boss | `docs/encounters/` |
| Set up the 40-character pool | `docs/pool.md` |
| Rebuild the server from nothing | `docs/build.md` |
| Create the container | `docs/host-create.md` |

**If you read only one thing, read the six rules in `CLAUDE.md`.** Five
of the six describe failures that are silent, persistent, and present as
something other than what they are.

## Quick reference

**These are server-side tools.** They read `playerbots.conf`, `hprv.env`
and a local MySQL socket, so they run on the box, not in your checkout.
Edit here, deploy, run there:

```bash
./scripts/deploy.sh                   # push this repo's scripts to /opt/hprv/scripts

H=root@192.168.4.124
ssh $H /opt/hprv/scripts/roster-status.sh          # level/class/gear/spec, from the DB
ssh $H /opt/hprv/scripts/hprv-spec.sh --list       # the 40-character pool
ssh $H /opt/hprv/scripts/hprv-spec.sh Ararin --show
ssh $H /opt/hprv/scripts/hprv-spec.sh Tanke "balance pve"
```

Running them from the checkout fails with
`cannot read /mnt/hprv/server/etc/modules/playerbots.conf` — that means
"you are on the wrong machine", not that anything is broken.

For a 10-man, just log in — the nine bots on your account come up with
you. For 25-man nights, summon the extra bodies by name;
`roster-status.sh` prints the paste line.

## Layout

```
CLAUDE.md              the brief — read first
docs/
  build.md             standing the server up, phases A-F
  pool.md              the 40-character pool: design, setup, spec switching
  host-create.md       host-side LXC creation
  raid-night.md        session runbook
  encounters/          per-instance fight notes, one file per raid
scripts/
  phase-*.sh           idempotent build/setup scripts
  deploy.sh            push scripts to /opt/hprv/scripts on the box
  pool.conf            the 40, with home specs and offspecs
  hprv-spec.sh         switch one character's spec and gear
  migrate-pool.sql     pool migration (review before running)
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
