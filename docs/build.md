# Standing the server up from nothing

Six phases. Everything except the host-side container creation and the
build itself is an idempotent script — re-running is safe and expected.

Total wall-clock is dominated by two steps: the `make` (20–40 min) and
mmaps extraction (hours). Plan around those two.

| Phase | What | How |
|---|---|---|
| — | Create the LXC | `docs/host-create.md`, by hand on the Proxmox host |
| A | OS prep, service user, MySQL | `scripts/phase-a-bootstrap.sh` (in container, root) |
| B | Clone core + module at the pins | `scripts/phase-b-source.sh` (as `acore`) |
| C | Build | by hand — see below |
| D | Databases + client data | `scripts/phase-d-dbimport.sh`, `scripts/phase-d-extract.sh` |
| E | Config | `scripts/phase-e-config.sh` |
| F | systemd + first light | `scripts/phase-f-systemd.sh` (root), then interactive |

---

## Before anything: the container

`docs/host-create.md` is the host-side runbook, run by hand on
`home-server` (192.168.4.80) as root. Target spec:

- Ubuntu 22.04 LTS (**not** the fleet default — fetch it explicitly)
- 4 vCPU, **12 GB RAM**, 4 GB swap (not the fleet's 512 MB)
- ~10 GB rootfs on `local-lvm`, plus Tank bind-mounts for all bulk

The rootfs is genuinely tight and the split is not optional: the source
tree is 1.7 GB, build output 9.3 GB, install prefix 1.5 GB. All of that
goes on Tank at `/tank/games/hprv`. There is no ZFS-backed `pvesm`
storage entry, and `local-lvm` has ~11 GB free.

**Resolve the `acore` UID *and* GID** for the mount ownership shift — do
not assume they match, and do not assume 1000. They match only by
coincidence.

---

## Phase A — OS, user, MySQL

```bash
/root/hprv/scripts/phase-a-bootstrap.sh     # in container, as root
```

Creates the `acore` service user (the daemons never run as root),
installs build deps, secures MySQL, and creates the DB user with a
**generated** password written to `/etc/hprv/hprv.env`.

It also creates all four schemas: `acore_auth`, `acore_characters`,
`acore_world`, `acore_playerbots`.

> **Never run AzerothCore's `data/sql/create/`.** Most guides tell you
> to — they assume no Phase A. `create_mysql.sql` resets the `acore`
> password to the project default and breaks every connection string.

---

## Phase B — Source at the pins

```bash
/root/hprv/scripts/phase-b-source.sh        # as acore; it refuses root
```

Clones the **playerbots core fork** (not upstream AzerothCore) and
`mod-playerbots` into `modules/`, both pinned to the SHAs in
`scripts/pins.conf` — that file is the reproducibility artifact and is
committed for exactly that reason.

Both pins come from the **same upstream merge**. Core and module advance
in lockstep through the `test-staging` branch, so taking both from one
merge avoids skew.

Clone target is `/mnt/hprv/build/azerothcore` on Tank, never
`/home/acore`.

> Upstream moved orgs: `liyunfan1223/*` now redirects to
> `mod-playerbots/*`. `pins.conf` uses the canonical org, because GitHub
> redirects break if the old name is ever re-created. Same project; the
> "not stock AC" rule is unchanged.

---

## Phase C — Build

By hand, **as `acore`, never root** — this phase has no
`require_not_root` guard, unlike Phase B.

```bash
cd /mnt/hprv/build/azerothcore
mkdir build && cd build
cmake ../ -DCMAKE_INSTALL_PREFIX=/mnt/hprv/server \
          -DTOOLS_BUILD=all -DSCRIPTS=static -DMODULES=static
make -j3
make install
```

Three things that will otherwise cost you the whole build:

- **`-j3`, not `-j$(nproc)`.** `nproc` is 4, and `SCRIPTS=static` /
  `MODULES=static` make the compile units large enough that 4 of them
  lean hard on swap.
- **`CMAKE_INSTALL_PREFIX` must exist and be `acore`-owned before
  `make install`.** `/mnt/hprv` is host-root-owned, so `make install`
  cannot create it — and that failure surfaces only *after* the entire
  build has finished. See `docs/host-create.md` §3.
- **The link peaks at 7.4 GB.** At 12 GB standing RAM this is fine. It
  was the reason the container was raised from 6 GB, where the
  `worldserver` link got OOM-killed. Lowering `-j` does not help — the
  final link is one `ld` process.

The tree is currently built `RelWithDebInfo`. A `Release` rebuild would
reclaim ~2 GB and lower the link ceiling; it is bundled with the
`mod-multibot-bridge` addition as one relink rather than paying twice.

---

## Phase D — Databases and client data

```bash
scripts/phase-d-dbimport.sh      # as acore
scripts/phase-d-extract.sh       # as acore
```

`dbimport` writes `dbimport.conf` from the installed `.dist` using the
Phase A credentials, then imports base + updates for
`auth`/`characters`/`world` — fully offline; the world base is ~126 MB
in-repo at this pin, not a downloaded release asset.

The module's own SQL needs no special handling: it sits under
`data/sql/{world,characters}/{base,updates}`, AzerothCore's module
convention, and `Updates.AllowedModules = "all"` picks it up.

> **`acore_playerbots` is NOT populated by `dbimport`.** Its mask stops
> at 4 (1=auth, 2=characters, 4=world) and `dbimport.conf` has no
> `PlayerbotsDatabaseInfo`. That connection string lives in
> `playerbots.conf`, and the **worldserver** applies the schema at
> startup, gated on `Playerbots.Updates.EnableDatabases` (default 1).
> The fourth schema therefore fills in at Phase F first-start, and
> should come to **30 tables**. That is the number a rebuild must match.

### Client data

Extracts dbc/maps/vmaps/mmaps from Clinton's own 3.3.5a client into
`/mnt/hprv/data`. Resumable per step (`maps`/`vmaps`/`mmaps`).

**mmaps are REQUIRED** — bot pathing depends on them, and a raid of bots
with no mmaps is useless. It is the hours-long step; run it in a
detach-safe shell.

**The client must be stock 3.3.5a.** MPQ archives layer, so a repack's
custom patches override Blizzard's maps, models and DBCs, and extraction
yields data for a world the server has never heard of — failing silently
at raid time rather than at import. Stock ships exactly seven lowercase
archives in `Data/`; the script refuses to run if it finds others
(capitalised, lettered ones like `Patch-F.MPQ` are the tell).

The same applies to the client you *play* on. Use a separate clean
install for HPRV.

---

## Phase E — Config

```bash
scripts/phase-e-config.sh
```

Points the three DB connection strings at local MySQL, sets `DataDir`,
and writes the realmlist row.

Two things that silently cost you a session if wrong:

- **`playerbots.conf`'s `PlayerbotsDatabaseInfo`.** The `.dist` ships
  password `acore`, not the generated one. Wrong here and the fourth
  schema never populates — silently.
- **`acore_auth.realmlist.flag` must be `0`.** The base row ships
  `flag = 2` (`REALM_FLAG_OFFLINE`), which shows the realm as offline in
  the client while still being connectable. Reads like an intermittent
  fault; is a config value. `gamebuild` must be `12340`.

### The population knobs

These are the settings that make HPRV what it is, rather than a default
playerbots install:

```
AiPlayerbot.RandomBotAutologin  = 1        # ambient world population ON
AiPlayerbot.MinRandomBots       = 20
AiPlayerbot.MaxRandomBots       = 20
AiPlayerbot.MaxAddedBots        = 40       # 24-bot raid fits with room
AiPlayerbot.AutoGearScoreLimit  = 125      # Tier 4 reset, ADR 0006
AiPlayerbot.CombatStrategies    = "+threat,+cc"
```

**20, not 500.** The `.dist` default is 500 random bots, which produced a
2.5-second idle world tick on 4 vCPU and almost certainly blocked client
login outright. 20 gives a populated world at a mean 10ms tick.

Zero the arena team counts (`RandomBotArenaTeam2v2Count`, `3v3Count`,
`5v5Count`) or the log fills with "No captains for random arena teams
available".

`+cc` on `CombatStrategies` is what gives priests Shackle Undead —
`AiFactory` gives them only `"dps assist"` and `"cure"` by default, so
without it there is no CC on Karazhan's undead trash. It is a harmless
no-op for classes with no CC.

---

## Phase F — First light

```bash
scripts/phase-f-systemd.sh       # root; installs and enables, does NOT start
```

First light must be interactive:

1. Run `authserver` + `worldserver` by hand once. **`Console.Enable` must
   be `1`** for this (the GM account is created at that console) and back
   to `0` before `systemctl start` — some builds read EOF on stdin as a
   shutdown request.
2. At the console: create the account, then
   `account set gmlevel <acct> 3 -1`.
3. Log in, verify world movement.
4. Set the client realmlist to `192.168.4.124`.

Expect world init around **5m41s**, of which 311 seconds is the module
parsing its own 102 KB `playerbots.conf`. The units are `Type=simple`,
so `systemctl start` returns instantly while the server is minutes from
ready. Connecting too early looks exactly like a dead realm.

Then go to `docs/raid-night.md`.

---

## Optional client-side

- **Realmlist** — required, `set realmlist 192.168.4.124`.
- **`MultiBot-Chatless`** — bot control UI. **Not addon-only any more:**
  the project split in 2026 and the maintained client requires the
  server-side `mod-multibot-bridge` module, i.e. a CMake re-run and a
  `worldserver` relink. Bundle it with the `Release` rebuild.
- **`Playerbot Manager`** — gear / raid-composition UI. This one *is*
  client-only and can be added at any time.
