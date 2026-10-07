# Serpentshrine Cavern

Map 548. The `ssc` strategy is applied automatically on entry. Its
triggers, actions and multipliers are in `src/Ai/Raid/SSC/`, wired in
`SSCStrategy.cpp`. Every boss has a script: Hydross, the Lurker,
Leotheras, Karathress, Morogrim and Vashj, plus two trash mechanics
(Underbog Colossus toxic pools and Greyheart Tidecaller totems).

Only Karathress is written up below. The others are scripted but not
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
