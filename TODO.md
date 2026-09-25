# HPRV — to-do list

Worked one at a time, in the order below. The order is not the order
they were asked in: 3 is a quick config fix that changes the world 1 and
6 depend on, and gear (2) has to come after the roster (1) is settled.
Professions (5) go after gear, because a gear pass may reset them.

Measured on the box 2026-09-26 unless marked otherwise.

> **Start here next session: item 2 (gear).** Items 3 and 1 are done.
> First step: check whether `hprv-spec.sh` can pass a gearscore cap
> (`init=168` for the ten, `init=183` for the 15). `gear-pass.sh`'s slot
> passes are disabled. Then draft the passes for review, with
> Bullwark's defence (`docs/bullwark-gear.md`) and the Crumm and Ararin
> re-conversions as the closing steps. Nothing on the box is mid-change:
> the server is up, and the ten auto-login as normal.

| # | Item | Kind | State |
|---|---|---|---|
| 3 | Level cap past 70 | do | **Done and verified 2026-09-26** |
| 1 | Roster: 10 + 15 by class, rest on the bench | do | **Done 2026-09-26** (Crumm's damage deferred) |
| 2 | Gear each group at its own tier | do | **Urgent.** The standing ten are half naked |
| 4 | Riding maxed at 70 | do | **Already done.** Two cosmetic fixes |
| 5 | Professions for the ten | plan | **Bullwark done 2026-09-26.** The other nine are still a plan |
| 6 | Make Orgrimmar feel busier | plan | Ranked options below |
| 7 | Level-80 holiday content | plan | **Brewfest is live now** |

---

## 3. Levelling past 70 — confirmed off for players, not for bots

**Players and the pool: off.** `worldserver.conf` has `MaxPlayerLevel = 70`
(`Expansion = 2`, so Northrend content is still loaded, but nobody earns
XP past 70). Every pool character is 70 or 1.

**Ambient bots: still levelling to 80, and living in Northrend.**
`playerbots.conf` has `RandomBotMaxLevel = 80` and
`RandomBotMaps = 0,1,530,571`. The factory sets bot level directly and
ignores `MaxPlayerLevel`. Of the 20 online ambient bots, **9 are above 70**
and 11 are on map 571 (Northrend), four of them at 79–80 in Storm Peaks.
They add nothing to a TBC world. Half of them are Alliance, and the rest
are on a continent you never visit.

There are also **47 offline characters at 71–80** on accounts with no
`playerbots_account_type` row. These need identifying before anything
touches them. They are probably leftovers from before the pool migration.

**What the source says** (read at the pin, 2026-09-26):
- `RandomBotMaxLevel` is **already clamped** to `MaxPlayerLevel`
  (`PlayerbotAIConfig.cpp:392`), so the 80 in config was effectively 70.
  The 80s reached 80 **before** the cap and have stayed there, because
  `DowngradeMaxLevelBot = 0` makes `Randomize()` keep their level.
- Turning `DowngradeMaxLevelBot` on is **not** the fix. It sends every
  ambient bot at or above the max, including legitimate 70s, back to
  level 1.
- `RandomBotMaps` is checked at teleport time, but **removing a map
  needs a restart**. A reload *appends* list settings instead of
  replacing them (`LoadList` has no `clear()`), which is now in CLAUDE.md
  rule 5. Found when Valuaan and Byninma were teleported *into* Howling
  Fjord after the reload.
- The 47 offline 71–80 characters are on **type-0** accounts, which are
  spare `rndbot` accounts that neither the ambient system nor the pool
  uses. They're dormant, so leave them alone. The ambient 20 live on just
  two type-1 accounts, RNDBOT0 and RNDBOT1.

**Done:**
- [x] `playerbots.conf`: `RandomBotMaxLevel = 70` and
      `RandomBotMaps = 0,1,530`. Backup at
      `playerbots.conf.20260925-162155.bak`. `docs/build.md` and
      `CLAUDE.md` are updated to match
- [x] 47 untyped characters identified as dormant type-0 accounts. No action

**Yours, in game** (there's no console: `Console.Enable`, RA and SOAP are all off):
- [ ] `.reload config`, then `.playerbots bot reload` (rule 5)
- [ ] Re-roll the 9 bots above 70. Each gets a random level from 1 to 70,
      new gear, and a teleport:
      ```
      .playerbots rndbot init Umran
      .playerbots rndbot init Aralan
      .playerbots rndbot init Valuaan
      .playerbots rndbot init Nathick
      .playerbots rndbot init Nuwelli
      .playerbots rndbot init Blantor
      .playerbots rndbot init Kalidana
      .playerbots rndbot init Dellysia
      .playerbots rndbot init Besholem
      ```
- [ ] Move the two level-70s out of Northrend without re-levelling them:
      ```
      .playerbots rndbot teleport Tebie
      .playerbots rndbot teleport Byninma
      ```
- [x] Commands run 2026-09-26. **Levels verified:** no type-1 bot above
      70. 7 of the 9 re-rolls and Tebie landed outside Northrend
- [x] Worldserver restarted 2026-09-26 and ready in 51 s. The maps list
      is now really `0,1,530`
- [x] Valuaan and Byninma teleported, and both landed in Shattrath
      (`Playerbots.log`). No bot has been teleported to map 571 since the
      restart
- [x] DB confirmed 2026-09-26 16:46: Byninma in Shattrath, Valuaan in Terokkar. **0** type-1 characters on map 571 or above 70

---

## 1. Roster: one of each class in the ten, then the 25

### The ten now

Warrior, Paladin ×2 (Ararin, Nathos), Druid ×2 (Tanke, Restofarian), Shaman,
Priest, Mage, Hunter, Rogue. That is **no Warlock and no Death Knight**. It
also has 4 healers and only 4 DPS, which is more healing than Karazhan
needs.

### Proposed ten: 2 tanks / 3 heals / 5 DPS, one per class

| Class | Character | Spec | Role | Change |
|---|---|---|---|---|
| Warrior | **Bullwark** | prot | main tank (human) | stays |
| Death Knight | Crumm | blood, converted | off-tank | **in** (RNDBOT98) |
| Paladin | Nathos | holy | tank healer | stays |
| Shaman | Krast | resto | heal | stays |
| Druid | Restofarian | resto | heal | stays (decision B) |
| Priest | Dijito | shadow | ranged | stays |
| Mage | Izri | frostfire | ranged | stays |
| Warlock | Celerina | destro | ranged | **in** (RNDBOT97) |
| Hunter | Ilyna | BM | ranged | stays |
| Rogue | Anmine | combat | melee | stays |

**Out:** Ararin (to the 25) and Tanke (to the 25).

Why the DK off-tanks rather than the paladin: one-of-each forces the
paladin to be either the tank or the tank healer. Holy is the one you
can't replace. The raid's only single-target tank healer matters more
when a human is taking the hits. Crumm is also **already genuinely
converted** (rule 1). Ararin stays useful as the 25's third plate body.

### Proposed 25: the ten + 15 → 3 tanks / 7 heals / 15 DPS

| Role | The 15 added |
|---|---|
| Plate (converted) | Ararin |
| Heal (+4) | Tanke (resto druid), Dehme (disc), Olidina (holy priest), Irntifumm (resto shaman) |
| Melee (+4) | Muhnun (rogue), Zaene (ret), Gerina (arms), Fimur (enh shaman, still level 1) |
| Ranged (+6) | Sehjece (ele), Fehmos (hunter), Lomul (mage), Vestanza (mage), Grohtarty (lock), Tengwe (balance) |

This gives 4 shamans, which means totems in 4 of the 5 parties. Only Fimur
is new to the 25.

**Dropped from today's `roster.conf`:** Rechiw (the unconverted DK, a
live rule-1 fault), Ralda (a third DK, and not in the pool), and Mutlie
(an 8th healer). The Tier 4 reset already emptied the lockouts, so now
is the cheapest time to change names (the roster.conf lockout note).

### The bench: everyone else (decision C)

**No 40.** TBC has no 40-man content, and a retuned AQ40 isn't worth
the work. The plan covers the 10 and the 25 only.

The other 16 pool characters are the bench: Rechiw, Daedana, Caugotsa,
Mutlie, Delatasia, Maroman, Cirtiglaz, Netohje, Grahlukk, Lonhwa, Eriona,
Alais, Bemarlarin, Drusun, Gelanlan and Tyrnan. They are spares for
illness-style swaps in the 25 and nothing else. They get no gear or
profession work until one is actually needed. Then it's a single
`init=183` pass, the same as the 15. Six of them are still level 1, and
they'll level themselves the first time they're summoned.

### Decisions (resolved 2026-09-26)

- [x] **A.** The DK off-tanks, and the paladin stays holy
- [x] **B.** Restofarian stays in the ten. Tanke goes to the 25.
      You answered "Resto", and both are resto druids, so I read that
      as Restofarian. Say so if you meant Tanke
- [x] **C.** No 40. The ten and the 25 only, and the rest are the bench

### Found while preparing the swap (2026-09-26)

- **`playerbots_db_store` is empty. Nobody is converted**, including
  Ararin and Crumm. No binlog write since 26 Aug; the rows were lost
  sometime between 14 and 26 Aug. `CLAUDE.md` rules 1 and 2 are corrected.
- **Every `init=` pass wipes a bot's `co` rows**
  (`PlayerbotFactory::Randomize()` → `PlayerbotRepository::Reset()`,
  unconditional). Conversions must be redone after every gear pass,
  which makes them the last step of item 2 for each plate body.
- Lockouts: Bullwark, Ararin and Tanke share Karazhan instance 1 and
  Gruul instance 2. Crumm and Celerina bind when they zone in.

### Steps once decided

- [x] `scripts/swap-standing-ten.sql` is written. Its guards abort on
      error, so nothing is half-applied. It was **dry-run against the
      live DB with ROLLBACK**: every check passed, and it caught and fixed
      a `USE` bug (ERROR 1046)
- [x] Run 2026-09-26: server stopped, dump taken
      (`/opt/hprv/backups/pre-swap-ten-20260925-164058.sql.gz`, 20 MB,
      complete), script committed with every check passing, server back up
      in 23 s. Account 101 is now Bullwark, Nathos, Ilyna, Anmine, Dijito,
      Crumm, Krast, Izri, Celerina and Restofarian. Ararin is on 93 and
      Tanke on 99
- [x] In game: invites done. **Crumm converted and verified** with the
      corrected DK pair, `co -blood,+frost,+frost aoe` + `nc -tank assist,+dps assist`.
      Neither row holds a TANK-typed strategy. The original `co -tank,…`
      line would have removed nothing from a DK (see CLAUDE.md rule 1)
- [ ] **Deferred ("we can deal with it"):** Crumm runs `frost` on blood
      talents, so his damage is below a real frost DK's. Revisit during
      item 2: keep blood talents with the frost rotation, or re-spec
- [x] Account 101 swap: out before in, never above 10. Done by the script
- [x] `roster.conf` rebuilt: slots 01–09 `GROUP=ten`, 10–24 `GROUP=25`,
      plus `BENCH`. `roster-status.sh` leaves the ten out of the summon
      line. `pool.conf` and `docs/pool.md` are updated. Deployed to
      `/opt/hprv/scripts` and run clean on the box
- [x] The conversion whisper is corrected everywhere (per-class `co` +
      `nc`). `hprv-spec.sh` prints the right pair for the class. ADR 0002
      is amended
- [x] `gear-pass.sh` slot passes (`tank`, `offtank`, `a`, `b`, `c`) now
      **refuse**, because their slot numbers predate the new `roster.conf`.
      Item 2 replaces them
- [x] ADR `0007`, "one of each class in the standing ten", is written and indexed
- [ ] Rechiw (bench, DK), Netohje and Gerina: no conversion now. Gerina
      is arms and in the 25, so she needs none. Rechiw needs the DK pair
      if he's ever summoned

---

## 2. Gear: the ten Karazhan-ready, the 15 Gruul-ready

**This is more urgent than it looks.** The Tier 4 strip deleted gear and
put nothing back:

| Character | Equipped slots (of 17) | avg ilvl |
|---|---|---|
| Krast, Izri, Tanke | **2** | 115–125 |
| Dijito | 8 | 119 |
| Nathos | 9 | 120 |
| Bullwark, Ilyna | 11 | 118 / 79 |
| Ararin, Anmine, Restofarian | 13–17 | 119–122 |

**Opinion: yes, and the mechanism already exists.** `init=<gearscore>`
caps a single bot's gear, so each group gets its own tier with no
change to the global `AutoGearScoreLimit`. A cap is a score, where
score = ilvl × 1.4641 for an epic (`gear-pass.sh`).

| Group | Meaning | Target ilvl | `init=` |
|---|---|---|---|
| Ten | best pre-raid: heroics, badges, crafted, rep | ~115 | `init=168` |
| +15 | Karazhan cleared, ready for Gruul | 125 | `init=183` |
| Bench | untouched until summoned, then as the 15 | 125 | `init=183` |

The idea is that the ten gear up in Karazhan on 10-man nights, while
the 15 are already Gruul-ready and waiting for them.

- [x] **Decision D.** There is no third tier. The bench is geared like the 15, and only when used
- **State on 2026-09-26** (`roster-status.sh`): 15 of the 24 bots have 2–5
  items equipped. Only Restofarian, Anmine, Ilyna, Ararin (14) and Gerina
  are near full. **Tanke is balance, not resto** (SPEC MISMATCH), so his
  pass must force resto. Ararin's defence is 461, under the 490 floor
- **Tooling:** `gear-pass.sh`'s slot passes are disabled (item 1). The
  per-character route is `hprv-spec.sh <name> "<spec>"`. It forces the
  spec, but check whether it takes a gearscore cap before relying on it
  for `init=168` / `init=183`
- **Every pass wipes `co`/`nc`.** Re-convert Crumm (DK pair) and Ararin
  (paladin pair) after their passes, and verify the row contents
- [ ] Re-gear with `gear-pass.sh`, group by group, clearing `co` first
      (rule 2). The spec roll is forced, so this also lands the intended
      specs and heals the `ACTUAL-SPEC` regression
- [ ] **Bullwark by hand.** He is never re-rolled. His gear is snapshotted
      in `docs/bullwark-gear.md` (2026-09-26): 17 slots, ilvl 110–130, **no
      enchants or gems on anything**, defence **474, 16 short of 490**.
      Close it with defence enchants and gems before swapping any pieces.
      Crumm and Ararin need a defence top-up after their passes too
- [ ] Fimur, the only level-1 character in the 25, auto-levels and gears on
      first login behind Bullwark. Then give him an `init=183` pass,
      because the auto-gear is uncapped (`ITEM_QUALITY_LEGENDARY`). The
      same applies to any bench level-1 character when summoned
- [ ] Fix `gear-pass.sh:756`. It still says the cap limits what bots
      equip from drops, which ADR `0006` disproved
- [ ] Extra Karazhan prep for the ten: Darkmoon Faire (Terokkar) deck
      trinkets are exactly this tier

---

## 4. Riding maxed at 70 — already done

All 10 on account 101, and all 22 level-70 pool characters (plus Ralda), have
**riding 300/300** plus Apprentice → Artisan flying and Cold Weather
Flying. 300 (Artisan, 280% flying) is the level-70 maximum. There is
nothing to learn.

- [ ] Cosmetic: Daedana shows 300/**75** and Caugotsa 300/**225**. Set
      max = 300 with the character offline
- [ ] Check Fimur after his first login (and any level-1 bench character when summoned).
      Gerina came out of auto-level with 300/300, so this is expected to be automatic

---

## 5. PLAN — professions for the ten

**Opinion: worth doing for you, mostly flavour for the bots.** At 375
(the level-70 cap, Master) most profession-only perks are WotLK ones
that start at 400–450, so they don't apply. What you do get: engineering
goggles and gadgets for Bullwark, blacksmithing, TBC-era crafts, and a
roster that looks like real people. **Whether bots craft on command is
unverified.** Check the module for a craft action before promising
yourself flasks.

**Two risks to check in source first:**
1. Does `PlayerbotFactory` (`init=`, `InitSkills`) reset or overwrite
   professions? Random bots like Tebie and Zailan come out with *every*
   profession at 350, so the factory clearly touches skills. If it does,
   every future gear pass wipes this work. That is why this item comes
   after item 2.
2. Bullwark already has **Engineering 300/375**. He only has two slots,
   so Engineering + Blacksmithing fills him.

**Bullwark: done 2026-09-26** with `scripts/max-professions.sql`.
Blacksmithing (Armorsmith, 115 trainer recipes), Engineering (Goblin, 107),
Cooking (12), First Aid (12) and Fishing are all 375/375, with no Grand
Master anywhere. Herbalism 1/75 was dropped to stay within
`MaxPrimaryTradeSkill = 2`. 215 → 408 spells. Backup at
`pre-prof-bullwark-20260925-170942.sql.gz`. The script is generic by
name, so the other nine reuse it once risk 1 below is checked.

**Mechanism: SQL, not `.learn all recipes`.** The GM command also teaches
vendor and drop recipes, and you asked for trainer-learnable only. With
the character offline:
- `character_skills`: skill → 375/375
- `character_spell`: the Master rank spell, plus every trainer recipe with
  required skill ≤ 375 and required level ≤ 70, joined from the trainer
  tables at this pin (check the schema: `npc_trainer` or `trainer_spell`)
- Filter out the Northrend trainer recipes at 350–375, which would look
  out of place in a TBC world

**Draft split** (finalise after item 1). Every primary profession is
covered at least once:

| Character | Professions |
|---|---|
| Bullwark | Engineering, Blacksmithing (required) |
| Crumm | Mining, Jewelcrafting |
| Nathos | Enchanting, Jewelcrafting |
| Krast | Leatherworking, Skinning |
| Restofarian | Herbalism, Alchemy |
| Dijito | Tailoring, Enchanting |
| Izri | Tailoring, Inscription |
| Celerina | Tailoring, Alchemy |
| Ilyna | Leatherworking, Skinning |
| Anmine | Engineering, Herbalism |

- [x] **Decision E.** Include Inscription, since 3.3.5a allows it. Its
      trainer recipes up to 375 are taught like any other profession's
- [x] **Decision F.** Max Cooking, First Aid and Fishing to 375 for all
      ten, including Bullwark, with the same script. Trainer recipes only,
      as for the primaries

---

## 6. PLAN — a busier Orgrimmar

Right now **one** ambient bot is in Kalimdor at all. Ranked from cheapest
to most expensive:

1. **Item 3's fix.** Taking Northrend out of `RandomBotMaps` brings about
   half the ambient bots back to continents you visit. Free.
2. **Faction ratio.** `RandomBotHordeRatio = 50` means half of them can
   never be in Orgrimmar. Set it to 80–90. Free.
3. **City weighting.** `TeleToOrgrimmarWeight = 2` → ~6 (and Shattrath
   up, as the TBC hub). `ProbTeleToBankers = 0.25` → ~0.5, so bots go
   to the bank and auction house more often. Free, and easy to reverse.
4. **More ambient bots.** 20 → 35–40. This is the real lever, and the
   only one that costs CPU. Measure it with the `Update time diff` log
   on a quiet night before a raid night, because 60+ bodies is unmeasured.
5. **Static NPCs.** Extra grunts, peons and citizens as custom spawns in
   the 9100000 range, in the same style as `custom/`. They cost no AI.
   It is the most reliable way to fill the Valley of Strength around the
   Porter and vendors.
6. **Park the bench in town.** Summoned bots with `LogInGroupOnly = 1`
   stand idle, which is cheap. They disappear at logout, though, so this
   is a raid-night crowd only, and it costs bodies against the unmeasured
   performance ceiling.

Also relevant: event 91, *Brewfest Building (Orgrimmar)*, spawns festival
NPCs in the city (see item 7).

**Recommendation:** 1–3 as one config change, run for a week. Then 4,
measured. Then 5 if the Valley still feels empty.

---

## 7. PLAN — holidays tuned for level 80

**Brewfest is live now.** In AzerothCore it runs about 20 Sep – 6 Oct.
Events 24, 70 and 91 are in `game_event`. Confirm with `.event activelist`.
Hallow's End starts mid-October.

The festivals themselves are mostly level-neutral: ram racing, barking,
costumes, token vendors, city decorations. They are good for atmosphere
and item 6. **The level-80 problem is the bosses:**

| Festival | Boss | 3.3.5a | Problem |
|---|---|---|---|
| Brewfest | Coren Direbrew (BRD) | lvl 80, LFG holiday dungeon | WotLK ilvl 200+ loot |
| Hallow's End | Headless Horseman (SM) | lvl 80 | same |
| Midsummer | Ahune (Slave Pens) | lvl 80 | same |
| Love is in the Air | Apothecary Hummel (SFK) | lvl 80 | same |

**The real risk is loot, not difficulty.** One ilvl 200 trinket outclasses
everything in Karazhan and undoes the Tier 4 reset. The LFG holiday
entries probably need level 78+ to queue, which would make them
unreachable at 70 anyway. Unverified: check `LFGDungeons` min level.

Options:
1. **Keep the festivals, neutralise the bosses (recommended).** Disable
   the holiday dungeon entries and the boss spawns (`disables` table or
   creature flags), or empty their loot tables. Cheap, reversible, and it
   keeps the atmosphere.
2. **Retune the bosses to 70.** Set level, HP and damage to TBC values
   and swap in era-appropriate loot. The Horseman and Ahune both existed
   at 70 in TBC, so there is a reference. Coren's 2.4.3 form needs
   research. This is real per-boss SQL work and belongs in `tuning/`,
   with an ADR.
3. **Turn the events off.** You lose the thing that makes them worth having.

- [ ] Before the next Brewfest night: check whether any bot can reach
      Coren, and whether anyone already carries holiday-boss loot
- [ ] If option 2 is wanted later, do the Horseman first. His
      TBC-to-WotLK diff is the best documented
