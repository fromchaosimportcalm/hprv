# Serpentshrine Cavern

Map 548. The `ssc` strategy is applied automatically on entry. Its
triggers, actions and multipliers are in `src/Ai/Raid/SSC/`, wired in
`SSCStrategy.cpp`. Every boss has a script: Hydross, the Lurker,
Leotheras, Karathress, Morogrim and Vashj, plus two trash mechanics
(Underbog Colossus toxic pools and Greyheart Tidecaller totems).

Karathress: killed 2026-10-08. Karathress and Vashj are written up below. The others are scripted but not
yet read. Add them here as they're fought.

---

## The Lurker Below: don't let bots fish

Casting Fishing to summon him used to give every bot in the group
`master fishing`. None of them owns a pole, so they whispered "I don't
have a Fishing Pole" until relog, because the strategy only ends 30 yd
from water. **Off since 2026-10-08** (`EnableFishingWithMaster = 0`;
`docs/build.md`, "Fishing"). If bots start whispering again, check that
setting first. Clear a stuck bot by relogging, not with `nc -master
fishing`, which saves its whole strategy list (CLAUDE.md rule 2).

---

## Fathom-Lord Karathress

**Fully scripted, by role.** It resolves each role itself, like the
Illidari Council (`black-temple.md`):

| Boss | Icon | Role | Resolved by | Where it's tanked |
|---|---|---|---|---|
| Karathress | triangle | main tank | `IsMainTank()` | near his start (`KARATHRESS_TANK_POSITION`) |
| Caribdis | diamond | assist tank 0 | `IsAssistTankOfIndex(bot, 0, false)` | the far west corner |
| Sharkkis | star | assist tank 1 | `IsAssistTankOfIndex(bot, 1, false)` | ~35 yd north of Karathress |
| Tidalvess | circle | assist tank 2 | `IsAssistTankOfIndex(bot, 2, false)` | ~35 yd north of Karathress, apart from Sharkkis |
| — | — | Caribdis healer | `IsAssistHealOfIndex(bot, 0, true)` | beside Caribdis's tank, and it won't move |

Coordinates are in `SSCHelpers.cpp:154-159`. The source says four tanks
for the full strategy, and that **two is the minimum that matters**,
because Caribdis has to be kept away from the other three.

When you tank, the main-tank row is yours to do by hand. The README's
rule applies: no main-tank trigger fires for a human.

### What the script does on its own

- **Bot tanks can't taunt.** `FathomLordKarathressDisableTankActionsMultiplier`
  zeroes taunt, growl, dark command, hand of reckoning, challenging
  shout/roar, and the AoE threat moves (thunder clap, consecration,
  swipe, D&D, blood boil and others) for every `IsTank()` bot. So rule 1
  can't fire here, and restoring tank bodies for this fight is safe.
- **Misdirection at the pull.** While Karathress is above 98%, the first
  three hunters in group order Misdirect onto the assist tanks and open
  with Steady Shot: hunter 1 Caribdis → assist tank 0, hunter 2
  Tidalvess → assist tank 2, hunter 3 Sharkkis → assist tank 1. A
  hunter whose tank doesn't exist does nothing. The usual Misdirection
  onto the main tank is turned off for this fight.
- **A 12-second hold.** From engage, DPS bots don't attack or cast
  anything except heals for 12 s (`dpsWaitSeconds`). That's the tanks'
  window to build threat.
- **No AoE from DPS bots** for the whole fight.
- **Kill order**, set in `FathomLordKarathressAssignDpsPriorityAction`:
  1. Spitfire Totems: melee
  2. Tidalvess: everyone
  3. Caribdis: ranged, from a fixed spot near her (melee skip this)
  4. Sharkkis: melee, and ranged once Caribdis is dead
  5. Sharkkis's pets (sporebat, lurker): melee
  6. Karathress: everyone

  The source says this order is deliberate. Bots handle Caribdis's
  Cyclone badly and need longer to kill her than players, so ranged go
  to her early instead of helping on Sharkkis first.

### Setup, in order

**1. Main-tank flag on `Bullwark`.** Without a flag, `GetMainTankGuid()`
picks the first `IsTank()` member in group order, which may be a bot.
That bot then takes Karathress and the script runs its main-tank
positioning on it, not you. (CLAUDE.md rule 6.)

**2. At least one assist tank.** A rule-1 converted raid has none, so
Caribdis goes loose among the healers. For this fight only, restore one
plate body:

```
/w Ararin co +tank,+tank assist,-dps,-dps assist
```

Ararin, the prot paladin with crit immunity, is the natural pick. He
takes Caribdis. Paladins have no interrupt, so her heals depend on the
shamans and rogues among the ranged near her. The source suggests a
warrior or druid on Caribdis for interrupts, if one is ever geared for it.

If there's only one assist tank, **Sharkkis and Tidalvess are yours**,
with Karathress.

**3. Afterwards, convert back** (CLAUDE.md rule 1, paladin row), and
check that both rows are clean:

```
/w Ararin co -tank,-tank assist,+dps,+dps assist
/w Ararin nc -tank assist,+dps assist
```

> **2026-10-08: Ararin had no `co` or `nc` row**, so he was already
> running full tank strategies from spec. That's convenient here and a
> live rule-1 fault everywhere else. What wiped the rows after
> 2026-09-26 is unknown. Check with a bare `co` before the night.

### The pull

- Stack the raid well back. The four stand together, and pulling one
  pulls all of them.
- Open on Karathress. Use the 12-second hold to pick up anything not
  Misdirected onto a bot tank: Thunder Clap, Demoralizing Shout, and
  tab-Devastate or Sunder. Hold them where Karathress started.
- Tidalvess dies first, so whatever you hold gets lighter early.
- Karathress gains each dead guard's abilities, so his damage on you
  climbs late. Save Shield Wall for the end.
- **Being thrown into the air over and over is a Cyclone.** Caribdis
  casts `SPELL_SUMMON_CYCLONE` (38337) on a random target
  (`boss_fathomlord_karathress.cpp:515`), and the cyclone knocks up
  whoever it reaches. If it settles on your tank spot, move. On the
  first kill (2026-10-08) it kept bouncing Bullwark until he moved
  Karathress, and then he went down.

---

## Lady Vashj

**Untested: written from the script on 2026-10-08, before the first
pull.** Correct this after the first attempt. The phase 2 hand-off is the
part most likely to need changing.

**You tank her. Ararin tanks only in phase 2, for the Striders.** Making
Ararin main tank looks easier but is worse, for two reasons:

- **The Strider tank would be you, without Fear Ward.** Striders go to
  assist tank 0. A human in prot spec counts as a tank
  (`IsTank(player)` falls back to spec), so with the main-tank flag on
  Ararin, Bullwark is assist tank 0 and the hunters Misdirect Striders
  onto him. The raid cheat (`BotCheats` includes `raid`) makes Striders
  tankable by putting Fear Ward on tanks, but only a *bot* casts that on
  itself (`LadyVashjTankAttackAndMoveAwayStriderAction`), so you'd be
  feared through phase 2.
- **Rule 1 is live here.** Unlike Karathress and the Council, nothing in
  the Vashj script turns off taunts. A tank-specced bot in phases 1 and
  3 follows your target, decides it has lost aggro, and taunts her.
  `TankAssistAction` is only blocked in phases 2 and 3
  (`LadyVashjDisableAutomaticTargetingAndMovementModifier`), and the
  lost-aggro taunt is a separate trigger.

Phases, as the script defines them (`SSCHelpers.cpp:209-230`): **1** is
above 70%; **2** is at or below 70% with Magic Barrier up; **3** is
after the barrier drops.

### What the script does on its own

| Phase | What it does |
|---|---|
| 1 | Hunters Misdirect her to the main tank above 90%. Ranged spread in an arc around the platform center. A bot with Static Charge runs from the group (the main tank is exempt). The shaman **in the main tank's party** drops Grounding Totem for Shock Blast, and won't use Windfury, Wrath of Air or Nature Resistance totems while she's up. DPS hold their cooldowns, and shamans hold Bloodlust until phase 3 |
| 2 | **Cores, all bots:** with the raid cheat, a melee DPS bot teleports to each Tainted Elemental, loots the core and passes it down a chain of four bots to the generators. The **raid leader is never in that chain** (`GetDesignatedCoreLooter`). Targets: hunters and mages kill Enchanted Elementals first; other ranged kill Striders, then Elites; melee DPS kill Enchanted, then Elites. Assist tank 0 takes Striders, gets Fear Ward and drags them 28 yd from Vashj. Bots stay within ~55–60 yd of the center, so they don't run down the stairs |
| 3 | Hunters kill Sporebats, bots avoid the poison clouds, and hunters Misdirect her to the main tank again between 50% and 40%. Bloodlust goes out |

What the script does for a bot main tank that **you do by hand**: drag
her to the platform center in phase 1 (`VASHJ_PLATFORM_CENTER_POSITION`),
and keep her 10 yd from Enchanted Elementals in phase 3.

### Setup

1. **Main-tank flag on `Bullwark`.** Grounding, the Misdirects and the
   Static Charge exemption all resolve the main tank from it. It was set
   on 2026-10-08.
2. **Ararin converted at the pull.** Check with a bare `co`; if `tank`
   shows, send the paladin pair (CLAUDE.md rule 1):
   ```
   /w Ararin co -tank,-tank assist,+dps,+dps assist
   /w Ararin nc -tank assist,+dps assist
   ```
3. **A shaman in your party.** On 2026-10-08, Bullwark's party (subgroup
   0: Anmine, Crumm, Ilyna, Restofarian) had none, so nobody grounds
   Shock Blast. Swap **Fimur** (enhancement) in and **Anmine** out to
   subgroup 2. Both are melee, so nothing else shifts. The layout
   persists (`docs/raid-layout.md`), so swap back after, or rerun
   `scripts/raid-layout.sql` at the next stop.

### Two macros, so nothing is typed mid-fight

Make these before the pull (Esc → Macros → New) and put them on your
bars. A macro sends each line as its own whisper.

**ARA TANK** (at 70%):
```
/w Ararin co +tank,+tank assist,-dps,-dps assist
```

**ARA DPS** (at the pull if needed, and when the shield drops):
```
/w Ararin co -tank,-tank assist,+dps,+dps assist
/w Ararin nc -tank assist,+dps assist
```

The real fix, if macros still feel like too much, is to do the switch in
`mod-hprv-city`. The module would watch Vashj's phase and change
Ararin's strategies in memory (`PlayerbotAI::ChangeStrategy`, like the
city wander). Then nothing is whispered and nothing is saved to
`playerbots_db_store`. That needs a module build and a short stop.

### The fight

- **Phase 1:** pull and drag her to the middle of the platform. If you
  get Static Charge, step out of the group.
- **At 70%, when the shield goes up:** press **ARA TANK**. He takes the Striders. You pick up the Coilfang Elites. Leave the
  cores to the bots.
- **When the shield drops (phase 3):** press **ARA DPS** straight away, and take Vashj back. Keep her away from the
  Enchanted Elementals.
- **After:** every whisper rewrote Ararin's saved row (rule 2). Check
  with a bare `co` that he ended up converted.
