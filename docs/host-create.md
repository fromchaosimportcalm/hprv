# HPRV — host-side container creation

Everything `scripts/phase-a-bootstrap.sh` deliberately refuses to do:
creating the LXC itself, Tank ZFS allocation, and sizing. These are
Proxmox host operations. The bootstrap script runs *inside* the
container that this document creates.

**Run these on the Proxmox host, by hand.** Nothing here is automated
from the repo session — container creation is Clinton's to run.

---

## 0. Where it goes

| Setting | Value | Why |
|---|---|---|
| Node | `home-server` (192.168.4.80) | Node 1 holds the ZFS `tank` pool. `games-lxc` (123) already lives here. |
| CTID | `124` | House convention: CTID == last IP octet. 123 is `games-lxc`; 124 is the next free game-adjacent slot. |
| Hostname | `hprv-lxc` | Matches the `*-lxc` naming used across the fleet. |
| IP | `192.168.4.124/24` | Static, gw `192.168.4.1`, DNS `192.168.4.1`, bridge `vmbr0`. |
| Rootfs | `local-lvm:10` | **Not 30 GB.** The thin pool is nearly full — see §2. |
| Bulk data | `/tank/games/hprv` → `/mnt/hprv` | Build tree, client data, MySQL datadir. |

HPRV gets its own container rather than sharing `games-lxc`. Satisfactory
and Minecraft there are Docker workloads; HPRV is a native build with its
own MySQL and a 20–40 minute compile. Different lifecycle, different
restart blast radius.

Sizing sanity check against the verified node (8 cores, 31 GB RAM, ~15 GB
already committed): 4 cores / 12 GB leaves headroom, but the node is not
empty — if the Phase C build starves, prefer dropping `-j` over raising
memory while the other containers are live.

> **Supersedes CLAUDE.md Phase A.** The "30 GB disk on Tank ZFS" line in
> the standing brief was written before the pool state was known. The
> real shape is a *small* `local-lvm` rootfs plus a Tank bind-mount for
> everything bulky. §2 has the numbers.

---

## 1. Why not `create-standard-lxc.sh`

The house helper (`clintonops-infra/helpers/create-standard-lxc.sh`) is
the normal path for a new LXC, but it diverges from the HPRV spec in
four ways that matter:

| House helper | HPRV needs | Verdict |
|---|---|---|
| Ubuntu 24.04 template | 22.04 (CLAUDE.md Phase A) | 22.04 is what the AC build deps are pinned against; the bootstrap script warns on anything else. |
| Installs Docker + `apps` user | Native build, `acore` user | Docker is dead weight here. |
| `--rootfs local-lvm:50` fixed | 10 GB + Tank bind-mount | 50 GB will not fit; the thin pool has ~11 GB free (§2). Client data (mmaps especially) is the disk hog and belongs on Tank. |
| `--features nesting=1` | Not required | Harmless but unnecessary. |

So: create HPRV with `pct create` directly, reusing the helper's
*conventions* (bridge, gateway, DNS, CTID==octet, `onboot`,
unprivileged, Tank mounts) without its Docker/24.04 payload.

If you'd rather not hand-roll, running the helper and then undoing the
Docker install also works — but the 24.04 template is the sticking
point, and that isn't parameterised.

---

## 2. Storage decision — RESOLVED

**Verified on home-server, 2026-08-03** (read-only, as `clinton`):

```
zpool  tank   29.1T total, 20.7T free, CAP 28%, HEALTH ONLINE
tank          mounted /tank, 14.9T avail
node          8 cores, 31 GB RAM (~15 GB already committed)
```

**Verified on home-server, 2026-08-04** (as root — `pvesm status`):

```
local       dir      12% used
local-lvm   lvmthin  92% used, ~11 GB free
```

**There is no ZFS-backed Proxmox storage entry.** Tank exists as a pool
and a mount path, but `pvesm` doesn't know about it. So the old option
(b) — rootfs on ZFS storage — is **off the table as written**, and not
worth planning around. Don't re-open it; adding a `pvesm` storage entry
for Tank is a fleet-level change, not an HPRV task.

That leaves option (a), the fleet pattern, with a hard constraint:

> **`local-lvm` has ~11 GB free.** HPRV's rootfs must be lean. Anything
> that grows without bound goes on the Tank bind-mount.

### The rootfs budget is genuinely tight — read before sizing

A 10 GB rootfs is not 10 GB of headroom. Steady-state estimate:

| Consumer | Size | Lands on |
|---|---|---|
| Ubuntu 22.04 base, post-`full-upgrade` | ~1.5 GB | rootfs |
| Phase A build deps (`libboost-all-dev`, `clang`, `mysql-server`, toolchain) | ~4–6 GB | rootfs |
| `acore_world` after import, + `characters`/`auth` | ~2–3 GB | **rootfs, unless moved** |
| AzerothCore source tree + module | **1.7 GB measured** (2026-08-07, after the real Phase B clone) | Tank (Phase B clone target) |
| Phase C build objects + static link | **9.3 GB measured** (2026-08-08) | Tank |
| Phase C install prefix (`make install`) | **1.5 GB measured** (2026-08-08) | Tank |
| Extracted client data (dbc + maps + vmaps + **mmaps**) | 15–25 GB | Tank |

Base + deps + databases lands at roughly **8–10 GB against a 10 GB
rootfs**, on a thin pool with ~11 GB actually free. That leaves no room
for apt cache during an upgrade, and no margin at all.

**Mitigation used by §3: bind-mount `/var/lib/mysql` onto Tank** (`mp1`).
That moves the one unbounded consumer off the rootfs and brings
steady-state rootfs use to ~5–6 GB, which fits with margin. It needs no
change to `phase-a-bootstrap.sh` — the mount is host-side and MySQL's
datadir path is unchanged, so the package postinst initialises straight
into it and AppArmor's `mysqld` profile still matches.

**Thin-pool caution.** `local-lvm` is at 92%. LVM-thin over-provisions:
if the pool actually fills, *every* container on it takes writeback
errors, not just HPRV. Creating a 10 GB volume is safe (thin — space is
consumed on write), but it means HPRV's growth is now shared risk with
the rest of the fleet. Keep the rootfs lean on purpose, not just to fit.

> Related, and deliberately **not** an HPRV task: `personal-lxc` (CT 103)
> is at 99% rootfs, ~26 GB of it Docker's image store. Moving Docker's
> data-root to Tank is a separate logged follow-up. Noted here only
> because it is the same thin pool — doing that move first would relieve
> this constraint considerably. HPRV does not depend on it, and is sized
> to work without it.

### Where on Tank — DECIDED: `/tank/games/hprv`

There is no `tank/games` *dataset* — `/tank/games` is a plain directory
under the `tank` dataset, and the two existing game servers disagree:

```
/tank/games/minecraft                   <- Minecraft data
/tank/apps/games-lxc/satisfactory       <- Satisfactory data
```

`/tank/games/hprv` wins: it follows the Minecraft precedent, sits beside
`games-lxc`/CT 123, and HPRV's bulk genuinely is game data. The
alternative (`/tank/apps/hprv-lxc`) is not wrong, just less apt here.
Settled — don't re-litigate at create time.

Layout under it:

```
/tank/games/hprv/build      <- AzerothCore source + build tree (~7-9 GB)
/tank/games/hprv/data       <- extracted client data (15–25 GB, mmaps included)
/tank/games/hprv/server     <- Phase C install prefix (CMAKE_INSTALL_PREFIX)
/tank/games/hprv/mysql      <- MySQL datadir (mp1)
```

`server/` is easy to forget — nothing before Phase C touches it, and
`make install` only fails once the 20–40 minute build has already
finished. Create it with the other two (§3).

mmaps are non-negotiable — bot pathing depends on them, and they are the
bulk of that 15–25 GB. Budget 50 GB and don't be precious; there's
14.9 TB free.

### Still to confirm at create time

```bash
pct list          # confirm CTID 124 is free — not yet run
```

---

## 3. Create the container

```bash
# On home-server (192.168.4.80), as root.

# 0. Confirm the CTID is free before anything else.
pct list | grep -w 124 || echo "124 is free"

# 1. 22.04 is NOT the fleet default — fetch it explicitly.
pveam update
pveam available | grep ubuntu-22.04
pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst

# 2. Tank-side directories: build tree, client data, install prefix,
#    MySQL datadir.
mkdir -p /tank/games/hprv/{build,data,server,mysql}

# 3. Create. Note rootfs 10 (NOT 30) — see §2.
pct create 124 local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst \
  --hostname hprv-lxc \
  --cores 4 \
  --memory 12288 \
  --swap 4096 \
  --storage local-lvm \
  --rootfs local-lvm:10 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.4.124/24,gw=192.168.4.1 \
  --nameserver 192.168.4.1 \
  --onboot 1 \
  --unprivileged 1 \
  --description "HPRV — AzerothCore + mod-playerbots. Created: $(date '+%Y-%m-%d')"

# 4. Mounts. mp0 = bulk (build tree + client data); mp1 = MySQL datadir.
pct set 124 -mp0 /tank/games/hprv,mp=/mnt/hprv
pct set 124 -mp1 /tank/games/hprv/mysql,mp=/var/lib/mysql

pct start 124
pct list
```

**`--rootfs local-lvm:10`, not 30.** The thin pool cannot support 30 GB
(§2). Everything that grows lives on Tank instead.

**Why `mp1` for `/var/lib/mysql`.** It keeps the databases — the one
unbounded rootfs consumer — off a nearly-full thin pool, with no change
to the bootstrap script. Mount it *before* first start, so the
`mysql-server` postinst in Phase A initialises the datadir directly onto
Tank. Adding it after MySQL is installed means stopping mysqld and
copying the datadir by hand; avoid that by doing it now.

**Unprivileged UID shift — do this or the container cannot write.**
CT 124 is unprivileged, so container UID *n* is host UID *100000+n*.
Freshly created Tank directories are owned by host root and will appear
as `nobody:nogroup` inside. Fix after the container is up and Phase A
has created the `acore` user:

```bash
# Container root (uid 0) owns the MySQL mount, so the postinst can
# chown it to the mysql user itself. Safe to run before first boot.
chown 100000:100000 /tank/games/hprv/mysql

# The build tree, client data and install prefix must all be writable
# by 'acore'. Resolve its UID and GID rather than assuming 1000 — and
# rather than assuming GID == UID, which is only true by coincidence.
ACORE_UID=$(pct exec 124 -- id -u acore)
ACORE_GID=$(pct exec 124 -- id -g acore)
chown -R $((100000 + ACORE_UID)):$((100000 + ACORE_GID)) \
  /tank/games/hprv/build /tank/games/hprv/data /tank/games/hprv/server
```

Verified 2026-08-07 on CT 124: `acore` is 1000/1000, so these become
`101000:101000` on the host and resolve back to `acore acore` inside.

`/tank/games/hprv` **itself stays host-root-owned** — it shows as
`nobody:nogroup` inside the container and that is correct. Only the four
subdirectories need shifting. That is also the trap: because the parent
is not writable by `acore`, a `server/` that was never created cannot be
created by `make install` either, and the build fails at the last step.

Note the **4 GB swap**, not the fleet's 512 MB. This is deliberate: the
Phase C link step is the RAM spike, and 6 GB with `-j4` is tight.
Cheaper to give it swap now than to discover it during a 30-minute
build. (The alternative, per CLAUDE.md Phase C, is dropping `-j`.)

`--features nesting=1` is intentionally omitted — nothing here is
containerised inside the container.

---

## 4. Verify before handing off to Phase A

```bash
pct exec 124 -- bash -c 'cat /etc/os-release | grep PRETTY_NAME'   # 22.04
pct exec 124 -- bash -c 'nproc; free -m; df -h / /mnt/hprv /var/lib/mysql'
pct exec 124 -- bash -c 'ping -c2 192.168.4.1 && ping -c2 1.1.1.1'
pct exec 124 -- bash -c 'systemd-detect-virt --container'          # -> lxc
```

`df -h` should show `/` at ~10 GB and both Tank mounts reporting Tank's
free space, not the rootfs's. If `/var/lib/mysql` shows the rootfs size,
`mp1` didn't take — fix it before running Phase A, not after.

That last check matters: `phase-a-bootstrap.sh` refuses to run unless it
can see it's inside a container, so it doesn't `apt full-upgrade` the
Proxmox host by accident.

Also confirm the mounts are actually writable by the right users — a
UID-shift mistake shows up as `nobody:nogroup` and silently fails later:

```bash
pct exec 124 -- bash -c 'ls -ld /mnt/hprv /mnt/hprv/{build,data,server} /var/lib/mysql'
for d in build data server; do
  pct exec 124 -- su -s /bin/bash acore -c \
    "touch /mnt/hprv/$d/.wtest && rm /mnt/hprv/$d/.wtest && echo $d-writable"
done
```

(The second only works after Phase A has created `acore`.)

---

## 5. Host-side follow-ups

**SSH alias** — add to `~/.ssh/config` on the workstation, matching the
existing LXC block:

```
Host hprv-lxc
    HostName 192.168.4.124
    User root
    IdentityFile ~/.ssh/id_ed25519_personal
    IdentitiesOnly yes
```

**Ansible inventory** — `clintonops-infra/ansible/inventory.ini` lists
`[lxcs]` but is already missing `games-lxc` (123), so HPRV joining it is
optional and a change to *that* repo, not this one. Worth noting the
`common` role provisions an `apps` user and `/mnt/apps`, which HPRV
doesn't use — if you do add `hprv-lxc` to the inventory, it should sit
outside the `lxcs` group or the role needs a conditional.

**Firewall / exposure** — nothing to open. Auth (3724) and world (8085)
stay on the LAN. Per the CLAUDE.md guardrail, no port forward, no
cloudflared route, no nginx-proxy host. If that ever changes, it's the
environment-promotion trigger, not a config tweak.

---

## 6. Handoff to Phase A

```bash
pct enter 124
# then, inside:
#   git clone <hprv repo> /root/hprv   (or scp the script over)
#   /root/hprv/scripts/phase-a-bootstrap.sh
```

Phase A ends with MySQL hardened, schemas created, the `acore` user in
place, and DB credentials at `/etc/hprv/hprv.env`. Phase B
(`scripts/phase-b-source.sh` — clone the fork, pin SHAs) picks up from
there as the `acore` user.

**Phase A ran 2026-08-05 and succeeded.** `mp1` took: the MySQL datadir
initialised onto Tank (`/tank/games/hprv/mysql`, host-owned
`100110:100118` = the container's `mysql` user). Nothing to redo.

**The §3 UID-shift chown was not run at create time.** Until 2026-08-07
`/tank/games/hprv/build` and `/data` were still `root:root` on the host,
appearing as `nobody:nogroup` inside, and `acore` could not write to
them. Phase B blocked on exactly this; its preflight refuses with the
chown instruction rather than half-cloning. **Run 2026-08-07 — see 6a.**

### 6a. Unblocking Phase B — RUN 2026-08-07

Recorded as run, not as pending. Re-runnable if the container is ever
rebuilt.

```bash
# 1. UID shift (host, as root). Without this 'acore' cannot write to
#    the Tank mount. Resolve UID *and* GID — do not assume they match.
ACORE_UID=$(pct exec 124 -- id -u acore)      # -> 1000
ACORE_GID=$(pct exec 124 -- id -g acore)      # -> 1000
chown -R $((100000 + ACORE_UID)):$((100000 + ACORE_GID)) \
  /tank/games/hprv/build /tank/games/hprv/data /tank/games/hprv/server

# 2. Key-based SSH into the container, so later phases don't need
#    `pct enter`. The workstation ~/.ssh/config has the 'hprv-lxc'
#    alias (§5), which authenticates with id_ed25519_personal — so
#    that specific pubkey is the one that has to land.
#    On the workstation:
#      scp ~/.ssh/id_ed25519_personal.pub home-server:/tmp/hprv-clinton.pub
#    Then on the host, as root:
pct exec 124 -- mkdir -p /root/.ssh
pct exec 124 -- chmod 700 /root/.ssh
pct push 124 /tmp/hprv-clinton.pub /root/.ssh/authorized_keys --perms 600
rm /tmp/hprv-clinton.pub
```

Install the one workstation pubkey rather than mirroring the host's own
`authorized_keys` — the host's trusted set is broader than the container
needs. Confirm with `ssh hprv-lxc hostname` from the workstation.

Then stage the scripts and run Phase B:

```bash
# From the workstation, once SSH works.
ssh hprv-lxc 'mkdir -p /opt/hprv/scripts'
scp scripts/{phase-a-bootstrap.sh,phase-b-source.sh,pins.conf} \
    hprv-lxc:/opt/hprv/scripts/
ssh hprv-lxc 'chmod 755 /opt/hprv/scripts/*.sh /opt/hprv /opt/hprv/scripts'

ssh hprv-lxc 'su -s /bin/bash acore -c /opt/hprv/scripts/phase-b-source.sh'
```

**`/opt/hprv`, not `/root/hprv`.** `/root` is mode 700, so `acore`
cannot traverse it — staging Phase B's script there produces a bare
"Permission denied" before any of the script's own guards can report
anything useful. Phase A (root) can live in `/root`; Phase B and
everything after it cannot.

**`su -s /bin/bash`, not `su - acore`.** `acore` is a service user and
may have a `nologin` shell.

`pins.conf` must travel with the script — `phase-b-source.sh` defaults
`HPRV_PINS` to `$SCRIPT_DIR/pins.conf` and dies without it. Those two
files are all Phase B needs; a full repo clone inside the container
would need a deploy key, which deliberately does not exist.

**Phase B/C must clone onto Tank, not into `/home/acore`.** The rootfs
has no room for an ~11 GB source + build tree (§2). Clone target:

```
/mnt/hprv/build/azerothcore        <- source + build/, per Phase C
```

Likewise Phase E's `DataDir` points at `/mnt/hprv/data`, not a rootfs
path. If a future step ever reports the rootfs filling, the answer is
almost always that something was written to `/home/acore` by mistake.

### 6b. Phase C build — COMPLETED 2026-08-08

Measured, not estimated. All of it cost a failed 40-minute build first.

**The container needs ~12 GB RAM to link, and 6 GB to run.** The final
`worldserver` link peaked at **7.4 GB RSS**, against a 6 GB container
with MySQL running — so it was OOM-killed at `[100%] Linking CXX
executable worldserver`, after everything else had built:

```
collect2: fatal error: ld terminated with signal 9 [Killed]
```

Signal 9 at the link is the OOM killer, not a compile error. **Lowering
`-j` does not help** — the final link is a single `ld` process, and
parallelism is already over by then.

```bash
# On the host, as root. Applies live; the build tree is undisturbed.
pct set 124 --memory 12288
# ... run the link ...
# NOTE: earlier revisions dropped this back to 6144 after the build.
# Do NOT. The container now runs at 12288 permanently — a 25-body raid
# plus 20 ambient bots sits at RSS 5.0 GB, and 6 GB has no margin.
```

Also stop MySQL for the link (`systemctl stop mysql`) — it is ~400 MB
that `ld` wants more than the databases do.

Object files survive an OOM kill, so a retry resumes straight to the
link. Retries cost minutes, not the full build.

**Do not build as root.** `phase-b-source.sh` has a `require_not_root`
guard; Phase C is still hand-run and has none, and it is easy to stay
root after `pct enter`. A root-run build leaves the tree root-owned and
`make install` writes root-owned binaries into a prefix the `acore`
daemons then own nothing in. Recoverable, but do it before continuing:

```bash
chown -R acore:acore /mnt/hprv/build /mnt/hprv/server
```

`chown` changes ctime, not mtime, so this does not invalidate the build.
Also check `/root/.ccache` — AzerothCore's cmake auto-enables ccache if
present, and a root-run build puts the cache on the 10 GB **rootfs**.

**Build type.** Nothing passed `-DCMAKE_BUILD_TYPE`, so this is
`RelWithDebInfo`. That is where both the 7.4 GB link peak and the
2.4 GB `worldserver` binary come from. A `Release` rebuild would reclaim
most of both and drop the link under the 6 GB ceiling permanently. Not
done — logged as a deliberate future choice, not an oversight.

**Verification that Phase C actually succeeded** (a core that builds
clean and has no bots is the failure mode worth catching):

```bash
ls -l /mnt/hprv/server/bin/          # authserver, worldserver, dbimport +
                                     # map_extractor, vmap4_extractor,
                                     # vmap4_assembler, mmaps_generator
ls -la /mnt/hprv/server/etc/modules/ # playerbots.conf.dist, ~102 KB
find /mnt/hprv/build/azerothcore/build -path '*mod-playerbots*' -name '*.o' | wc -l
                                     # 630 at this pin
```

The four extractor tools use underscores (`map_extractor`, not
`mapextractor`). They are what Phase D runs against the client.

---

## Rollback

If the container needs to be redone:

```bash
pct stop 124 && pct destroy 124
# /tank/games/hprv survives destroy — remove it deliberately if you
# want a truly clean slate:
# rm -rf /tank/games/hprv
```

The bootstrap script is idempotent, so re-running it against a rebuilt
container is fine — **with one trap introduced by the `mp1` datadir.**

`/etc/hprv/hprv.env` lives on the rootfs and dies with the container, so
a rebuild mints a *new* DB password. But `/tank/games/hprv/mysql` is on
Tank and survives, so `mysql-server` finds a populated datadir, skips
initialisation, and keeps the *old* `acore` password. The bootstrap's
final credential check then fails — correctly, but confusingly.

Pick one when rebuilding:

```bash
# (a) Keep the databases — reuse the old password.
#     Copy ACORE_DB_PASS out of the old env file first, then:
#     ACORE_DB_PASS='<old>' ./phase-a-bootstrap.sh
#
#     Or, if the old password is lost, rotate it against the surviving
#     datadir from inside the container:
#     HPRV_ROTATE_DB_PASS=1 ./phase-a-bootstrap.sh

# (b) Truly clean slate — drop the datadir with the container.
rm -rf /tank/games/hprv/mysql && mkdir -p /tank/games/hprv/mysql
chown 100000:100000 /tank/games/hprv/mysql
```

Option (b) also discards characters and any Phase I tuning applied to
`acore_world`, so prefer (a) once there's a raid worth keeping.
