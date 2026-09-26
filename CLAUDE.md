# HPRV — Hellfire Peninsula Retirement Village

A 3.3.5a AzerothCore + mod-playerbots server. One human tanks. A standing
ten-man raid auto-logs-in with you; a wider pool of 40 characters is
summoned by name for 25-man nights; ~20 more bots wander the world as
ambient population. Target content is TBC endgame — Karazhan through Black
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
| Standing raid | 10 on your own account, **auto-login**: Bullwark + 9 bots, one of each class (ADR `0007`) |
| Wider pool | 31 more on type-2 accounts, summoned by name for 25-man |
| Ambient | 20 random bots, levels 1–70, Eastern Kingdoms / Kalimdor / Outland only (no Northrend, 2026-09-26) |
| Gear tier | **Tier 4, reset 2026-09-25** — everything above ilvl 125 stripped from the 25, `AutoGearScoreLimit = 125` (ADR `0006`) |
| Custom NPCs | Teleporter + free T4/T5/T6 and weapon vendors, Orgrimmar — `docs/custom-npcs.md` |
| Furthest kill | Black Temple: Naj'entus, Supremus (2026-08-13) |
| Furthest attempt | Illidari Council to 24%, lost to the 15-min berserk (2026-08-15) |

**The human tanks. That is the point of the project**, and it is the
constraint every other decision bends around. Non-goals: perfect boss
kills, a public server, authentic 2.4.3 talent trees (those stay WotLK —
the maintained playerbot ecosystem is 3.3.5-first, and BC *feel* is
recovered by tuning instead).

---

## The six rules that actually matter

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

The fix is **two whispers, and the first depends on the class**
(corrected 2026-09-26, read from `AiFactory.cpp` and the class
`*AiObjectContext.cpp` files):

| Class | `co` (combat) | then, every class |
|---|---|---|
| Warrior | `co -tank,-tank assist,+arms,+dps assist` | `nc -tank assist,+dps assist` |
| Paladin | `co -tank,-tank assist,+dps,+dps assist` | 〃 |
| Death Knight | `co -blood,-tank assist,+frost,+frost aoe,+dps assist` | 〃 |
| Druid (bear) | `co -bear,-tank assist,+cat,+dps assist` | 〃 |

Why the old single whisper, `co -tank,-tank assist,+dps,+dps assist`,
was wrong:

- **`IsTank()` checks every engine.** It is
  `ContainsStrategy(STRATEGY_TYPE_TANK)`, which loops over the combat,
  non-combat *and* dead engines. `tank assist` is itself TANK-typed
  (`TankAssistStrategy.h:20`), and `AiFactory` puts it in the
  **non-combat** engine for every tank spec. So after a `co`-only
  whisper, `IsTank()` stayed **true**. The taunt was gone on warriors and
  paladins, but `GetMainTankGuid()`, `ThreatValue` and the raid scripts
  still counted the bot as a tank.
- **The class tank strategy isn't always called `tank`.** A Death Knight's
  is `blood` and a druid's is `bear`. On them, `-tank` removed nothing, and
  `blood` carries `lose aggro → dark command` itself
  (`BloodDKStrategy.cpp:135`). **Crumm was never converted.** That is why
  he was the bot measured at 3,651 taunts.
- **Warriors have no `dps` strategy** (only `tank`, `arms`, `fury`), so
  the old whisper left a prot warrior with no rotation at all. Paladins
  do have one (Retribution), so on Ararin `+dps` did work.

The bot keeps its talents, gear and crit immunity, and off-tanks by
damage threat instead of by taunt. **Verify both rows, and check the
content, not just that the row is there.** Neither `co` nor `nc` may hold
`tank`, `blood`, `bear` or `tank assist`. `tank face`, `pull` and
`pull back` are not TANK-typed and are fine. Crumm verified this way,
2026-09-26.

**Any plate bot that arrives tank-specced needs this before it raids.**

> **Nobody is converted right now (found 2026-09-26).**
> `playerbots_db_store` is **empty**: 0 rows, `AUTO_INCREMENT` 692. The
> binlogs show no write to it at all from 26 Aug onward, so every
> override, including Ararin's and Crumm's, vanished between the
> 2026-08-14 count and then. The cause is unproven. The prime suspect is
> rule 2's `Randomize()` wipe during an `init=` pass. **Every
> tank-specced plate bot is running full tank strategies from spec**
> until it is re-whispered. Re-convert each one after its last gear pass
> (TODO item 2), then assert the row exists.

> **`Rechiw` is NOT converted, and this is live.** He has zero rows in
> `playerbots_db_store` and knows Rune Tap, Mark of Blood and Vampiric
> Blood, so `AiFactory` grants him the full tank set from spec every
> login. He is on account 83, so this is a **25-man-only** fault — he is
> not in the standing ten, and the only plate body that auto-logs-in
> (`Ararin`) was believed converted, but see the note above. The whisper needs him summoned, so
> it can only land on a 25-man night. He is a Death Knight, so he needs the
> `blood` form of the whisper from the table above. This file previously listed him as done: the
> 2026-08-13 check asked whether anyone *carries* `+tank`, and a bot
> with no rows answers "no" while running it from spec. **Absence of a
> `co` row is not evidence of conversion — it is evidence of the
> opposite.**

**The rule is symmetric, and which character you log in as decides it.**
Auto-login is all-or-nothing — the module runs a bare `SELECT name FROM
characters WHERE account = <yours>` with no exclusion — so `Bullwark`
arrives as a bot whenever he is not the one you picked, and he carries
no `co`, so he arrives a full tank.

- **Log in as a DPS or healer** — fine, no preparation. `Bullwark`
  main-tanks, still exactly one `IsTank()` body, `+threat` cap intact.
  This is now the supported bot-tank mode; `Netohje` is retired (ADR
  `0002`).
- **Log in as `Ararin` or any plate body** — rule 1 fires *at you*.
  Convert `Bullwark` first, with the warrior row from the table; it is harmless to
  leave in place, since `co` governs bot AI only.

Nothing advances the raid on its own on any character — every movement
primitive is relative to the master. You always lead.

> **One encounter suspends this rule, deliberately: the Illidari
> Council.** Its assist-tank roles gate on `IsTank()`, so a fully
> converted raid leaves Malande and Veras untanked — and the encounter
> script zeroes every taunt action for `IsTank()` bots in combat with
> Gathios, so the fault rule 1 exists to prevent cannot fire there.
> Restore two plate bodies at the Council's door, revert before Illidan.
> ADR `0004`, and `docs/encounters/black-temple.md`.

### 2. `co` writes a persistent, total override — and it is a trap

**And any gear pass erases it.** `PlayerbotFactory::Randomize()` calls
`PlayerbotRepository::Reset()`, which deletes **all** of that bot's
`playerbots_db_store` rows (`co`, `nc`, `dead`, values). That covers
every `init=` pass, and the auto-gear on login that fires on a level gap
greater than 3. A conversion does not survive a gear pass, so re-whisper
after every one.

Any `co` carrying `+`, `-` or `~` calls `PlayerbotRepository::Save()`,
which writes the bot's **entire current strategy list** to
`playerbots_db_store`, not the delta. On every later add, the module
rebuilds strategies from spec and then applies the saved list over the
top.

Two consequences:

- **A bot that has ever taken a `co` is frozen at the strategies it had
  when the whisper landed.** A spec change made any way other than
  `init=` leaves it running the *previous* spec's strategies, with no
  warning. An `init=` pass does not have this problem, because it wipes
  the rows first (`PlayerbotFactory.cpp:697`, unconditional). That also
  erases any conversion. `co !` before a pass is harmless but redundant.
- **Whatever raid you were standing in got baked in.** On 2026-08-14 all
  **21** bots carrying overrides had `+blacktemple` frozen into their
  saved lists, because that is where they were when the whisper landed.
  (Those rows are all gone now; see rule 1.)
  **This is now verified harmless** (2026-08-15).
  `PlayerbotAI::ApplyInstanceStrategies()` (`PlayerbotAI.cpp:1620`)
  removes *every* instance strategy from both engines and then adds back
  only the one matching the map you entered. A frozen `+blacktemple` is
  stripped on entering Karazhan and re-added on entering Black Temple,
  whatever the saved list says.

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

**Except for list settings — removing an entry needs a restart.**
`PlayerbotAIConfig::Initialize()` fills list options with `LoadList()`
(`PlayerbotAIConfig.cpp:23`), which only `push_back`s and is never
preceded by a `clear()`. A reload therefore *appends* the new list to the
old one: dropping `571` from `RandomBotMaps` and reloading left the
runtime list `0,1,530,571,0,1,530`, and a bot was teleported into Howling
Fjord minutes later (2026-09-26). Adding an entry reloads fine; removing
one does not. This applies to every `LoadList` option (`RandomBotMaps`,
`RandomBotQuestIds`, `RandomBotSpellIds`, …).
It also applies to lists the module builds for itself. After that reload,
every `.playerbots rndbot <cmd> <name>` ran **twice** per bot
(`[0/2]`, `[1/2]` in `Playerbots.log`), and after the restart it ran once
(`[0/1]`). So after any reload, a restart is the only way back to a clean
state.

That restart cost is real: world init is ~5m41s, of which **311 seconds
is the module parsing its own 102 KB `playerbots.conf`**. The systemd
units are `Type=simple`, so `systemctl start` returns instantly while
the server is still minutes from ready. Watch the journal, not the unit
state.

> **Re-measured 2026-09-26: `World Initialized In 0 Minutes 51 Seconds`**
> on a warm restart, not ~5m41s. The earlier figure may be a cold-cache
> start. Two data points only, so don't plan around either yet. Watch for
> `ready...` in the journal.

### 6. Raid-frame flags are role assignments, and they persist

`group_member.memberFlags` is read by the module, survives logout and
restart, and is invisible unless you go looking. `MEMBER_FLAG_MAINTANK`
(`2`) makes `GetMainTankGuid()` (`PlayerbotAI.cpp:2378`) return that
body **without ever checking `IsTank()`** — so a flag left on a rule-1
converted plate bot makes the raid's main tank a body with no tank
strategies, no taunt and no crit immunity, while your real tank holds
nothing. `MEMBER_FLAG_ASSISTANT` (`1`) orders every per-role index the
raid scripts use — assist tank 0/1, assist heal 0 — ahead of group join
order. `MEMBER_FLAG_MAINASSIST` (`4`) is read nowhere in the module.

Found live on 2026-08-15 with the main-tank flag on `Ararin`, which cost
a Black Temple night and misdirected every hunter Misdirection in the
raid to the wrong body. **This repo previously said "do not flag
anyone". That was wrong.** Audit before a serious night:

```sql
SELECT c.name, c.class, c.online, gm.memberFlags, gm.subgroup
  FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 ORDER BY gm.subgroup, gm.memberGuid;
```

Leader **or** assistant can set icons and the main-tank flag; only the
leader can promote assistants. A bot holding raid lead is normal —
`/w Bullwark give leader` hands it back. See ADR `0003`.

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
| `docs/encounters/` | Per-instance fight notes, one file per raid |
| `scripts/roster.conf` | The ten (auto-login), the 15 (summoned) and the bench, committed so they can be re-summoned |
| `scripts/pins.conf` | Core + module SHAs. The reproducibility artifact |
| `scripts/gear-pass.sh` | Force the spec roll, then gear |
| `scripts/gear-rounds.conf` | Item 2's gear passes as three `hprv-spec.sh --batch` rounds, capped per group |
| `scripts/roster-status.sh` | Level/class/gear from the DB, no login needed |
| `tuning/` | BC-feel SQL. See below |
| `custom/` | Custom NPC SQL (ID range 9100000–9100099) — `docs/custom-npcs.md`. `scripts/package-npcs.sh` packs it for other servers |
| `docs/raid-layout.md` | Party layout for the 10 and the 25, why it persists, audit and restore (`scripts/raid-layout.sql`) |
| `docs/tank-defence.md` | Enchants, gems and gear to crit-cap Bullwark and Ararin (`scripts/fix-tank-defence.sql`). Defence counting incl. enchants/gems: `scripts/defence.conf` |
| `docs/bullwark-gear.md` | Bullwark's hand-picked gear, snapshotted, with restore lines. He is never `init=`'d |
| `scripts/swap-standing-ten.sql` | The 2026-09-26 standing-ten swap. It's the pattern for any future swap (ADR `0007`) |
| `TODO.md` | The working list: items 1–7, with status |
| `scripts/strip-gear-above-ilvl.sql` | Delete equipped gear above an ilvl across the roster — ADR `0006` |
| `decisions/` | Standing rules only — history lives in `hprv-archive` |

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

**Start it in Karazhan, not Black Temple.** BT is already gated on gear
rather than on tuning: the Illidari Council's ~4.89M shared pool needs
~5,430 raid DPS to beat its 15-minute berserk, and at
`AutoGearScoreLimit = 141` (measured before the Tier 4 reset, ADR `0006`) the raid did ~4,130 — 30% short of the
*nerfed* value the restore would undo. Raise the tier first; no HP
restore lands in Black Temple until the Council dies inside its timer.
ADR `0005`.

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

## Known regressions

- **`roster-status.sh` reports `ACTUAL-SPEC` as `-`.** The pool migration
  deleted `playerbots_random_bots` rows for the migrated characters, and
  `specNo` — which that column reads — lives there. `PlayerbotFactory`
  rewrites it during `init=`, **but only when `EquipAndSpecPersistence`
  is off** — the same gate that blocks the respec itself. So it heals as
  each character goes through an `hprv-spec.sh` pass, which turns that
  flag off for the duration, and not otherwise.
- **Ararin still trips the "defence items in BAGS" warning.** True but no
  longer actionable — he is at 511 and the bagged pieces are worse than
  what he wears. The check has no notion of "already sufficient".
- **`roster.conf` does not match the live raid.** The 2026-08-15 group
  audit found `Netohje` (RNDBOT96) and `Gerina` (RNDBOT50) in the raid;
  neither is in `roster.conf`, and neither carries a `co` row — which by
  ADR `0002`'s rule is evidence of *non*-conversion. Both are warriors,
  so if either is prot-specced it is a live rule-1 fault. Check with a
  bare `co` whisper before the next serious night. `Rechiw` was **not**
  in that raid, so the known 25-man fault did not apply to it.

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
