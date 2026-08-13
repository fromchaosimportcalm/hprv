# The 40-character pool

A rotatable roster of 40 bots that keep their gear, auto-login with you,
and can be re-specced and re-geared with one command.

Everything here was read out of the module source at the current pin.
Where something is untested, it says so.

---

## The shape

**Account 101 (yours) holds 10 characters, and they auto-login with you.**
That is a standing 10-man raid — Karazhan-capable — that costs no
commands. The other 31 pool characters stay on their type-2 `rndbot`
accounts and are summoned by name for 25-man nights.

### Why 10 and not 40

The client renders at most 10 characters per realm. `CharactersPerRealm`
is validated `> 0 && <= 10` (`WorldConfig.cpp:231`) and documented
`Default: 10 - (Client limitation)`. Raising it is silently rejected:

```
Server Config (Name: CharactersPerRealm) failed validation check '> 0 && <= 10'.
Default value '10' will be used instead.
```

And the cap is enforced **only at character creation**
(`CharacterHandler.cpp:420`), never at enum — so an account holding more
than 10 sends them all and the client answers *"Error retrieving
character list."* Hit for real at 41 characters.

### Three gates, routinely confused

| Capability | Gated on |
|---|---|
| Gearable by `init=` | `IsAccountType(id, 2)` — a row in `playerbots_account_type` |
| Safe from ambient gear churn | **account type 1 vs 2.** The ambient pool is built from `rndBotTypeAccounts` (type 1) only, and `IsRandomBot()` needs the `rndbot%` name *and* membership in `currentBots` |
| Auto-login + group persistence | `BotAutologin` / `KeepAltsInGroup` — **your own account only** |

**A type-2 `rndbot` character is already gearable and already churn-safe.**
Moving it to your account buys auto-login and group persistence, and
nothing else. That is worth 9 slots; it is not worth breaking the
character list.

### The standing ten

| Character | Role |
|---|---|
| Bullwark | human prot warrior — **main tank** |
| Ararin | prot paladin off-tank (converted) |
| Nathos, Krast, Tanke, Restofarian | holy pal, resto shaman, 2× resto druid |
| Izri, Dijito, Ilyna | mage, shadow priest, hunter |
| Anmine | rogue |

1 tank, 1 off-tank, 4 healers, 4 DPS. Swapping one is a single `UPDATE`
— move one out before moving one in, and never exceed 10. The procedure
is in `scripts/migrate-pool.sql` SECTION 2.

### 25-man nights

The nine bots are already in. Summon the extra bodies by name from the
remaining 31 — `roster-status.sh` prints the paste line. Nothing about
those characters is second-class: they gear, spec and switch exactly like
the standing ten.

## Faction is a hard constraint

`Bullwark` is a Tauren — **Horde**. Every character in the pool is Horde
(races 2 Orc, 5 Undead, 6 Tauren, 8 Troll, 10 Blood Elf). The AddClass
pool is roughly half Alliance, and those characters can never group with
him. Filter on race before drawing any replacement.

---

## Setup

### 1. Config changes

`worldserver.conf`: **no change.** Leave `CharactersPerRealm` at `10`.
An earlier version of this doc said to raise it to 45; that is rejected by
the validator and is the direct cause of "Error retrieving character
list".

`playerbots.conf`:

```
AiPlayerbot.BotAutologin     = 1     # was 0 — this is the auto-login
AiPlayerbot.KeepAltsInGroup  = 1     # was 0 — keeps the raid group intact
AiPlayerbot.MaxAddedBots     = 45    # was 40, which is exactly the pool size
```

Leave `AddClassAccountPoolSize` alone. Your account now counts as a
51st type-2 account, which is one more than the configured 50 — the
assignment loop only ever *tops up*, never trims, so nothing happens.

> **Do not enable SOAP.** An earlier version of this plan called for it.
> It does not work: `.playerbots bot` is registered `Console::No`, and its
> handler opens with `if (!m_session) { "You may only add bots from an
> active session" }`. SOAP and RA both execute as console sessions with
> no player, so this is not a permission bit that can be flipped. SOAP
> would buy you `.reload config` and nothing else.

### 2. Migrate

`scripts/migrate-pool.sql`, run by hand with the world server stopped and
a dump taken first. It inserts the `account_type` row for account 101 and
moves the standing ten into place.

**Section 2 is a warning, not a migration** — read it before moving any
further character onto the account. Section 4 is a rollback that restores
every original account from a backup table.

### 3. The level-1 draws bring themselves up

**This step is mostly automatic** — verified on the box 2026-08-13.
`OnBotLogin` carries:

```cpp
bool addClassBot = IsAccountType(accountId, 2);
if (addClassBot && master && abs(master->GetLevel() - bot->GetLevel()) > 3)
    PlayerbotFactory(bot, master->GetLevel(), ITEM_QUALITY_LEGENDARY,
                     mixedGearScore).Randomize(false);
```

So a level-1 draw logging in behind your level-70 master is levelled,
geared and specced in one login, with no pass at all. Gerina went 1 → 70
at avg ilvl 138 epics that way. `InitAttunementQuests()` runs too, so the
TBC raid attunements come free.

**But the spec is rolled at random** by `RandomClassSpecProb`. Gerina
happened to land on `arms pve`, which is what `pool.conf` wanted, at
roughly a 20% chance. Budget one `hprv-spec.sh` pass each for the other
nine to set the intended spec:

```
Delatasia (paladin)   Maroman  (priest)    Lonhwa  (warrior)
Fimur     (shaman)    Tyrnan   (rogue)     Gelanlan (hunter)
Cirtiglaz (shaman)    Alais    (warlock)   Bemarlarin (warlock)
```

**The same gate is why migrating the veterans is safe.** The level gap
must *exceed 3*, so a level-70 character behind a level-70 master is
never touched. Netohje came through the migration with his gear
bit-for-bit unchanged.

### 4. Fix the under-tier veterans

The tier is `AutoGearScoreLimit = 141` and most of the pool sits at
134–139. Six do not, all of them veterans carrying gear from the old
125-era limit:

| Character | avg ilvl | Note |
|---|---|---|
| Netohje | 115 | **blue**, and dual-wielding — fury-geared, not the crit-immune prot tank the old notes claim |
| Ararin | 119 | the off-tank, already under the defence floor at 476 |
| Anmine | 122 | |
| Restofarian | 122 | |
| Tanke | 127 | |
| Celerina | 127 | |

Note the irony before planning around it: **the level-1 draws come out of
auto-gear better equipped (~138) than five of your veterans.** Because
auto-gear only fires on a level gap, a stale level-70 never self-corrects.

Each is one `hprv-spec.sh` pass. Two carry extra cost:

- **Netohje** is the designated bot-mode main tank and cannot do that job
  as he stands. A pass to `prot pve` re-gears him at tier, then he needs
  the defence top-up.
- **Ararin** has hand-picked defence items and a persistent `co`
  conversion. A pass wipes the items and clears the override — both have
  to be redone. Read the tank-mode and defence-floor notes first.

## Switching spec and gear

Server-side tool — deploy first, then run it there:

```bash
./scripts/deploy.sh                        # from your checkout

H=root@192.168.4.124
ssh $H /opt/hprv/scripts/hprv-spec.sh --list [class]
ssh $H /opt/hprv/scripts/hprv-spec.sh <character> --show
ssh $H /opt/hprv/scripts/hprv-spec.sh <character> "<spec>" [--mode human|bot]
```

### Why the script exists

A respec never re-gears. `init=` picks a spec by `RandomClassSpecProb`
and *then* gears for whatever it rolled, so landing a chosen spec with
matching gear means forcing the probability table to 100% for that spec,
running `init=`, and putting the table back. By hand that is six steps
with two silent failure modes.

The script does the fiddly parts — probability-table surgery with backup
and guaranteed restore, **turning `EquipAndSpecPersistence` off for the
pass**, spec-name validation against the installed config, stale `co`
override deletion, and the post-pass defence check — then prints three
lines for you to paste.

> That persistence flag is the one that bites hardest. It gates both
> `resetTalents()` and `InitTalentsTree()` inside `PlayerbotFactory`
> (lines 625, 691), so with it on, `init=` on a level-70 bot re-gears the
> character and **silently keeps the old spec**. The pass looks like it
> worked and nothing changed. **It cannot run those three for
you** (see the SOAP note above).

### Tank mode

Rule 1 in `CLAUDE.md` forces a choice, so `--mode` picks one:

- **`--mode human`** (default). You main-tank. Any plate/bear body
  switched *into* a tank spec gets converted with
  `co -tank,-tank assist,+dps,+dps assist` — it keeps tank talents, tank
  gear and crit immunity but `IsTank()` goes false, so it off-tanks by
  damage threat and never taunts. The script prints this whisper; it is
  the one manual step. **Do not whisper `co -threat` in this mode.**
- **`--mode bot`**. You play something else — `Restofarian`, or a DPS.
  `Netohje` main-tanks and is not converted. If you run **two** bot tanks,
  whisper `co -threat` to both: `ThreatValue` scales each tank against the
  other tanks, so an unmodified pair mutes each other and neither holds
  anything.

### The defence floor survives nothing

490 defence skill is crit-immunity against a level 73 boss.
`StatsWeightCalculator` scores raw stats and has no concept of defence
skill or its cap, so **every** `init=` pass fills trinkets, neck and
shield with zero-defence pieces and drops the character back under the
floor.

So switching *into* a tank spec always costs a hand-itemisation step
afterwards. The script reports the resulting defence and flags it; it
cannot skip the `.additem` work.

Currently under the floor (measured 2026-08-13):

| Character | Defence skill | Needs |
|---|---|---|
| Ararin | 476 | 490 |
| Crumm | 475 | 490 |
| Rechiw | 447 | 490 |

`Bullwark` is fine at 534.

---

## The pool

40 characters, weighted toward hybrids because a hybrid body changes role
for the price of a gear pass rather than a different character.

| Class | N | Can fill |
|---|---|---|
| Paladin | 5 | tank / heal / melee |
| Druid | 5 | tank / heal / ranged / melee |
| Shaman | 5 | heal / melee / ranged |
| Priest | 4 | heal / ranged |
| Warrior | 4 | tank / melee |
| Mage | 4 | ranged |
| Warlock | 4 | ranged |
| Hunter | 4 | ranged |
| Rogue | 3 | melee |
| Death Knight | 2 | tank / melee |

16 bodies can tank, 19 can heal. Names, home specs and offspecs are in
`scripts/pool.conf`; every one of its 129 spec references was validated
against `PremadeSpecName` at this pin.

`Ralda` (unholy DK) is deliberately **not** in the 40 — the pool caps
death knights at 2 and keeps the two converted blood off-tanks. He stays
on his `rndbot` account and can be drawn back at any time.
