# HPRV — Hellfire Peninsula Retirement Village

A 3.3.5a AzerothCore + mod-playerbots server. One human tanks; 24 bots
fill a 25-man raid; ~20 more bots wander the world as ambient
population. Target content is TBC endgame — Karazhan through Black
Temple — tuned back toward 2.4.3 difficulty.

This is the repo-root `CLAUDE.md`, auto-loaded when a session opens
here. It layers over the Homelab environment `CLAUDE.md` in a parent
directory.

Every number in this file was measured on the box, not remembered. Where
a fact is unverified it says so.

---

## What this is, right now

| | |
|---|---|
| Host | `hprv-lxc`, `192.168.4.124`, Proxmox on ClintonOps |
| Resources | 4 vCPU, 12 GB RAM, Tank-backed bulk storage |
| Core | `mod-playerbots/azerothcore-wotlk`, Playerbot branch, pinned |
| Module | `mod-playerbots/mod-playerbots`, pinned to the same merge |
| Raid | 1 human prot warrior (`Bullwark`) + 24 bots |
| Ambient | 20 random bots, levels 25–80, live in the open world |
| Gear tier | `AutoGearScoreLimit = 141` |
| Furthest kill | Black Temple: Naj'entus, Supremus (2026-08-13) |

**The human tanks. That is the point of the project**, and it is the
constraint every other decision bends around. Non-goals: perfect boss
kills, a public server, authentic 2.4.3 talent trees (those stay WotLK —
the maintained playerbot ecosystem is 3.3.5-first, and BC *feel* is
recovered by tuning instead).

---

## The five rules that actually matter

Everything else in this repo is procedure. These are the ones where
getting it wrong costs a raid night and presents as an unrelated fault.

### 1. A bot tank and a human tank cannot share a raid

Both tank strategies wire `LoseAggroTrigger` — `!AI_VALUE2(bool, "has
aggro", "current target")` — straight to a taunt: `taunt` at
`ACTION_INTERRUPT + 1` for warriors, `hand of reckoning` at
`ACTION_HIGH + 7` for paladins. A bot tank's `tank assist` strategy
points it at *the master's* target, so while you hold that target the
bot never "has aggro", the trigger is permanently satisfied, and it rips
the boss off you on cooldown, forever. **No threat setting reaches
this.**

Measured on Crumm, 2026-08-13: `dark command` pushed 3,651 times,
executed 49. Forty-nine rips off the main tank in one night.

The fix, whispered **once per bot, ever** (it persists):

```
/w <bot> co -tank,-tank assist,+dps,+dps assist
```

That clears `STRATEGY_TYPE_TANK` so `IsTank()` goes false. The bot keeps
its tank talents, tank gear and crit immunity, and off-tanks by damage
threat instead of by taunt — which is what you want from a plate body on
adds anyway.

**Any plate bot that arrives tank-specced needs this before it raids.**
Currently applied to `Ararin`, `Crumm`, `Rechiw`.

### 2. `co` writes a persistent, total override — and it is a trap

Any `co` carrying `+`, `-` or `~` calls `PlayerbotRepository::Save()`,
which writes the bot's **entire current strategy list** to
`playerbots_db_store`, not the delta. On every later add, the module
rebuilds strategies from spec and then applies the saved list over the
top.

Two consequences:

- **A bot that has ever taken a `co` is frozen at the strategies it had
  when the whisper landed.** Re-roll its spec through a gear pass and it
  logs in running the *previous* spec's strategies with no warning. Any
  pass that changes a spec must first clear the override with `co !`, or
  delete the bot's `playerbots_db_store` rows.
- **Whatever raid you were standing in got baked in.** All 20 bots
  currently carrying overrides have `+blacktemple` frozen into their
  saved lists, because that is where they were when the whisper landed.
  Raid strategies auto-apply on instance entry anyway, so this is
  believed harmless — but it is unverified, and it is the first thing to
  suspect if bots behave oddly in a *different* raid.

Verify what a bot actually carries with a bare `co` (no arguments), or:

```sql
SELECT c.name, s.value FROM acore_playerbots.playerbots_db_store s
  JOIN acore_characters.characters c ON c.guid = s.guid
 WHERE s.key = 'co';
```

### 3. Do not whisper `co -threat`

With **two or more** tanks, `ThreatValue::Calculate` expresses each
tank's threat as a percentage of the highest threat among *other* group
members that `IsTank()` accepts — so two tanks mute each other and
neither holds anything. That was a real fault, and the fix was
`co -threat` on both.

It no longer applies. With rule 1 in force there is exactly one body
`IsTank()` accepts — you — so `ThreatValue` finds a real tank to scale
the DPS bots against and the global `+threat` cap works as designed.
Whispering `co -threat` now would only uncap the DPS.

### 4. The client shows 10 characters. That caps everything.

`CharactersPerRealm` is validated `> 0 && <= 10` in `WorldConfig.cpp:231`
and the config comment says why: **`Default: 10 - (Client limitation)`**.
Set it higher and the server logs

```
Server Config (Name: CharactersPerRealm) failed validation check '> 0 && <= 10'.
Default value '10' will be used instead.
```

The cap is enforced only at character *creation*
(`CharacterHandler.cpp:420`), **not** at enum — so an account holding more
than 10 characters sends them all and the client answers
"Error retrieving character list". Learned the hard way at 41.

Three separate gates matter here, and they are routinely confused:

| Capability | Gated on |
|---|---|
| Gearable by `init=` | `IsAccountType(id, 2)` — a row in `playerbots_account_type` |
| Safe from ambient gear churn | **account type 1 vs 2**, not the account name. The ambient pool is built from `rndBotTypeAccounts` (type 1) only, and `IsRandomBot()` needs both the `rndbot%` name *and* membership in `currentBots` |
| Auto-login + group persistence | `BotAutologin` / `KeepAltsInGroup` — **your own account only**, so at most 9 bots |

**Characters on type-2 `rndbot` accounts are already gear-safe.** They are
gearable and the ambient system never touches them. Moving them to your
own account buys auto-login and group persistence — nothing more, and
only for 9 of them.

So the layout is: **10 on your account** (Bullwark + 9 that auto-login,
which is exactly a 10-man raid), and the rest of the pool on their type-2
accounts, summoned by name.

Full design: `docs/pool.md`.

### 5. Config edits need `.reload config` *then* `.playerbots bot reload`

In that order. `.playerbots bot reload` alone re-applies what `ConfigMgr`
cached at startup — it never touches disk, reports success, and changes
nothing. `.reload config` is what re-reads the file. The pair avoids a
~6-minute restart; either alone is a silent no-op.

That restart cost is real: world init is ~5m41s, of which **311 seconds
is the module parsing its own 102 KB `playerbots.conf`**. The systemd
units are `Type=simple`, so `systemctl start` returns instantly while
the server is still minutes from ready. Watch the journal, not the unit
state.

---

## Performance: measured, and fine

With the full 25-body raid in Black Temple **plus** 20 ambient randoms —
45 characters, 1 real player — on 2026-08-13:

```
Update time diff   mean 10ms   median 1ms   p95 26ms   p99 44ms   max 309ms
worldserver        100% of one core, RSS 5.0 GB of 12 GB
load average       1.87 across 4 vCPU
```

AzerothCore only logs `Update time diff` above ~100ms, so sparse lines
are the healthy state, not a missing metric. The world tick is
effectively single-threaded — one saturated core with three spare is the
expected shape, and adding vCPU will not lower the tick.

**Headroom exists but has not been probed.** 45 bodies is the largest
measurement taken. Do not assume 60+.

RAM note: the container runs at 12 GB. It was 6 GB during the build era
and had to be raised, because the `worldserver` **link** peaks at 7.4 GB
and gets OOM-killed at 6. Dropping `-j` does not help — the final link is
one `ld` process. At 12 GB standing this is no longer a special case.

---

## Guardrails

- **The 3.3.5a client is copyright Blizzard.** Do not download, torrent
  or fetch it. Clinton supplies it from his own copy. Work stops at
  server + realmlist.
- **Never expose auth/world ports to the internet.** LAN / WireGuard
  only. If this ever changes, HPRV has outgrown the Homelab environment
  and needs its own — see "Environment placement" below.
- **The build REQUIRES the playerbots core fork**, not upstream
  AzerothCore. Do not attempt to bolt the module onto stock AC.
- **Confirm before any `DROP` or destructive DB op** on a live world DB.
- **Client must be stock 3.3.5a.** MPQ archives layer, so a repack's
  custom patches (capitalised, lettered: `Patch-F.MPQ`, `Patch-H.MPQ`)
  override Blizzard's maps, models and DBCs. Extraction then yields data
  for a world the server has never heard of, and it fails silently at
  raid time rather than at import. Stock ships exactly seven lowercase
  archives in `Data/`; `phase-d-extract.sh` refuses to run if it finds
  others.

---

## Remotes

Dual-remote, per ClintonOps convention. Use the SSH host aliases from
`~/.ssh/config`, not the HTTP URLs (web UI only).

- `origin` → GitHub: `git@github.com-personal:fromchaosimportcalm/hprv.git`
- `gitea` → Gitea: `git@gitea:fromchaosimportcalm/hprv.git`
  (host alias `gitea` = 192.168.4.103:2222, web UI on :3002)

Push to both, every time:
`git push origin main && git push gitea main`

---

## Environment placement

**This lives under the Homelab environment. Do not move it to Personal,
and do not spin up a new environment for it.** Placement follows domain
of responsibility, not subject matter: HPRV is an LXC on the Tank pool,
behind UniFi/WireGuard, following the same systemd-unit and
dual-remote-git patterns as the Satisfactory and Minecraft servers. Its
rules are a subset of Homelab's plus the project-specifics in this file.

Do not edit the Homelab `CLAUDE.md` for this project. The only thing
that gets promoted upward is a genuinely reusable homelab convention —
test: "would this help a completely unrelated homelab project?"

The one trigger that would justify promotion: **going internet-facing.**
That brings auth hardening, DDoS exposure, player-data handling and
update-cadence discipline. A private LAN/WireGuard bot-raid box does not
clear that bar.

---

## Where things are

| Path | What |
|---|---|
| `docs/build.md` | Standing the server up from nothing |
| `docs/raid-night.md` | Session runbook — start here to actually play |
| `scripts/roster.conf` | The 24 bots, committed so they can be re-summoned |
| `scripts/pins.conf` | Core + module SHAs. The reproducibility artifact |
| `scripts/gear-pass.sh` | Force the spec roll, then gear |
| `scripts/roster-status.sh` | Level/class/gear from the DB, no login needed |
| `tuning/` | BC-feel SQL. See below |
| `decisions/` | Standing rules only — history lives in the archive repo |

On the box: `/mnt/hprv/server` (install), `/mnt/hprv/data` (extracted
client data), `/mnt/hprv/build/azerothcore` (source), `/etc/hprv/hprv.env`
(generated DB credentials).

---

## BC-feel tuning — the ongoing hobby

The one remaining direction with real room in it. Bot strategies were
tested against 2.4.3-restored tuning, so this is supported, not a hack.

**There is only one lever, and it is SQL.** Restore raid boss HP to
2.4.3 values — revert the global 30% HP nerf patch 3.0.2 applied to TBC
raid bosses — as idempotent, per-raid `UPDATE`s against
`acore_world.creature_template`, in version control.

**There is no bot damage or healing multiplier at this pin.** This was
long assumed to exist and planned around as "IP nerfs". It does not: the
entire 102 KB `playerbots.conf` matches `multiplier|nerf` on two lines,
one of which is `RandomChangeMultiplier` (unrelated — random-bot churn).
Verified 2026-08-13. If bot competence ever needs lowering, it is a
module patch or a gear-tier drop, not a config edit.

Each meaningful tuning decision → an ADR via the haven-log flow.

---

## Known-unfixable encounters

Structural properties of the encounters, not tuning problems:

- **Karazhan's Chess event.** mod-playerbots has no chess code at all,
  and the encounter is built around players charming pieces — uncharmed
  friendly pieces never move and cast at half the enemy rate, so "let
  the AI play it" loses by design. Open the Gamesman's exit door with
  `.gobject activate` and move on.
- **Magtheridon's cube phase.** Needs five players clicking Manticron
  Cubes on a timer. Attemptable but it commits five of your bodies to a
  mechanic bots handle poorly.

---

## Open questions

- **Whether to carry a small local patch series against the pinned
  module.** Several upstream fixes have been deferred on pinning
  grounds. Two would recover most of what rule 1 costs: teaching the
  Karazhan triggers to accept a human main tank, and making
  `LoseAggroTrigger` respect a human's aggro. Worth costing before the
  next relink, since that is a rebuild either way.
- **`Release` rebuild + `mod-multibot-bridge`.** The tree is
  `RelWithDebInfo`; `Release` reclaims ~2 GB and lowers the link ceiling.
  The maintained MultiBot client (`MultiBot-Chatless`) needs the
  server-side bridge module, i.e. a CMake re-run and a relink. Bundle
  both into one 12 GB window rather than paying twice.
- **Chatter shaping.** No built-in raid/non-raid gate exists — see
  `docs/raid-night.md`. Current behaviour is believed acceptable but has
  not been deliberately tuned.
- **Starting HP-restore percentage** for the first tuned raid night,
  then each adjustment after.
