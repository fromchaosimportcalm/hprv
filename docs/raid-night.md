# Running a raid night

Start here to actually play. `CLAUDE.md` has the five rules that explain
*why* several of these steps exist; this file is the order to do them in.

---

## Starting a session

Bots log out when you do, so every session begins by rebuilding the raid.

> **This whole step goes away once the pool migration lands.** With the 40
> characters on your own account and `BotAutologin = 1`, they are added
> automatically the moment you log in — see `docs/pool.md`. Until then,
> summon by name as below.

**1. Check the server is up and ready.** The units are `Type=simple`, so
`systemctl start` returns while the server is still ~6 minutes from
accepting logins. Watch the journal, not the unit state:

```bash
ssh root@192.168.4.124 'systemctl status hprv-world --no-pager | head -5'
ssh root@192.168.4.124 'journalctl -u hprv-world -n 20 --no-pager'
```

**2. Check nothing drifted** while you were away:

```bash
scripts/roster-status.sh
```

Reports level, class, gear and spec straight from the DB, no login
needed. It reads **last-saved** state — if you hand-equipped anything
last session and did not `.save`, this lies.

**3. Log in as `Bullwark` and summon the raid.** Two lines, pasted in
game — 24 names plus the command exceeds a comfortable chat length:

```
.playerbots bot add Ararin,Nathos,Krast,Tanke,Izri,Lomul,Dijito,Celerina,Ilyna,Anmine,Sehjece,Crumm
.playerbots bot add Rechiw,Ralda,Zaene,Muhnun,Fehmos,Dehme,Olidina,Irntifumm,Mutlie,Tengwe,Vestanza,Grohtarty
```

The command is `.playerbots bot`, **not** `.bot`. There is no such alias
at this pin, whatever the guides say.

**4. Invite to raid.** No raid-frame flags are needed — you are the only
body `IsTank()` accepts, so `GetMainTankGuid()` resolves to you on its
own. Do not flag anyone.

**5. Confirm the raid strategy activated** on instance entry. It
auto-applies and whispers when it does.

**That is the whole opener.** No `co` whispers, no `-threat`, nothing
per-session. Every override this raid needs is already persisted in
`playerbots_db_store`.

### Only when a *new* bot joins the raid

If you draw a fresh body from the pool and it is a plate class that
arrives tank-specced, convert it before it raids — once, ever:

```
/w <bot> co -tank,-tank assist,+dps,+dps assist
```

Skipping this is not subtle: it will taunt bosses off you on cooldown
all night. See `CLAUDE.md` rule 1.

### If the server was restarted

Nothing extra. The overrides are in the database, not in memory. But
budget the ~6-minute start, of which 311 seconds is the module parsing
its own 102 KB config.

---

## Ending a session

Just log out. The bots go with you and the raid lockout stays bound to
their names — which is exactly why `scripts/roster.conf` is committed.
Re-summoning *those* names next time puts you back in front of the same
half-cleared instance.

---

## Cheatsheet

### Driving the raid from chat

Bots read party **and** raid chat, so a bare command typed in `/raid`
drives all 24 at once. No addon needed.

| Mark | Effect |
|---|---|
| **skull** | every DPS bot focuses it (`RtiValue` default) |
| **moon** | mages, hunters and rogues CC it (`RtiCcValue` default) |

The vocabulary at this pin:

```
stay  follow  flee  runaway  disperse  ready
pull  pull back  pull rti    attack  attackers  target
tank attack     max dps      dps     heal    focus
```

`disperse` is the one to remember for Netherspite and Malchezaar.

**Marking is the engage order, not a hint.** `DpsTargetValue::Calculate()`
returns the RTI target the moment one exists, so the instant the skull
lands, every DPS bot has a valid target and `dps assist` walks them into
range. This ruins a line-of-sight pull. `+threat` does not hold them —
`ThreatMultiplier` only zeroes actions that *have* a threat type, and
walking into position is not one.

The `pull` / `pull back` strategies would do the right thing, but
`AiFactory` grants them to tank specs only — and with a human tank and
three converted plate bots, **no body in the raid has them.**

Two ways round it. Easiest: **mark after the pull lands** — pull with
your own shot, let the pack reach you, then skull. Otherwise hold them
explicitly:

```
stay            <- in /raid, before you pull
                   ...pull, let them come to you...
follow          <- release
```

`StayAction` calls `StopMoving()` and clears CHASE and FOLLOW, so it is a
real hold. Release promptly — while staying they will not step out of
fire or back into healer range.

### Repairs

Drop a **Field Repair Bot 74A** among the raid (not at the edge —
interaction range is enforced) and type `repair` in `/raid`. Repairs
everyone.

| Item | Creature | Engineering needed |
|---|---|---|
| Field Repair Bot 74A (18232) | 14337 | **300** |
| Field Repair Bot 110G (34113) | 24780 | 325 |

Gold is not a constraint — the chat command has no budget gate, and the
roster carries four figures each.

### "A bot has the wrong spec"

Whisper `talents spec <name>`. The name must match
`AiPlayerbot.PremadeSpecName.*` **exactly** — the index number from
`talents spec list` is not accepted.

**A respec never re-gears.** `init=` picks a spec by
`RandomClassSpecProb` and *then* gears for it; changing spec afterwards
leaves the old gear in place. A spec change is a `gear-pass.sh` job, not
a whisper.

And if that bot carries a `co` override, clear it first with `co !` —
otherwise it logs in running the *previous* spec's strategies
(`CLAUDE.md` rule 2).

### "A bot keeps pulling aggro and dying"

Per-bot, persistent:

```
/w <bot> co -aoe
```

The global `+threat` cap is the raid's main brake and it works correctly
now that there is exactly one tank. `co -aoe` is the targeted remedy for
a specific offender.

### "I need to edit playerbots.conf"

```
.reload config
.playerbots bot reload
```

**In that order.** `.playerbots bot reload` alone re-applies what
`ConfigMgr` cached at startup — it never reads disk, reports success,
and changes nothing.

### Things not to run

- **`.learn all my talents`** — fills all three trees, and because
  `EquipAndSpecPersistence` gates `resetTalents()`, `init=` can then
  never repair the character. Recovery is `.reset talents` plus a gear
  pass.
- **`.playerbots bot initself=...` on a character you care about** — it
  clears bags, spells, skills and quests and rolls a random spec. Safe
  on a fresh 70, a disaster on a played one. `gear-pass.sh master`
  refuses to print this line for `Bullwark`.
- **Deleting the `rndbot` accounts.** 50 of the 100 are the AddClass
  pool that makes the roster addable by name at all.
- **`.playerbots bot init=` on the whole raid casually** — it re-rolls
  specs (see above) and will undo hand-picked tank itemization.

---

## Chatter

There is **no built-in raid/non-raid gate.** Nothing in the config
suppresses bot chat by instance — `BroadcastChanceSuggestInstance` is a
broadcast *about* instances, not a gate.

What exists instead:

| Key | Current | What it governs |
|---|---|---|
| `AiPlayerbot.RandomBotTalk` | `1` | ambient random-bot chatter |
| `AiPlayerbot.RandomBotSayWithoutMaster` | `1` | talking with no master present |
| `AiPlayerbot.EnableBroadcasts` | `1` | the whole broadcast system |
| `AiPlayerbot.BroadcastTo*GlobalChance` | `30000` | per-channel rates (guild, world, general, trade, LFG, defense…) |
| `AiPlayerbot.BroadcastChance*` | varies | per-event rates (loot by quality, quests, kills, level-ups) |
| `AiPlayerbot.GuildRepliesRate` | `100` | guild reply frequency |
| `AiPlayerbot.ToxicLinksRepliesChance` | `30` | ...exactly what it sounds like |

These are believed to govern the **ambient** pool rather than your
summoned raid bots — different code path — which would mean the
"chatty outside, quiet inside" split comes for free by construction.
**That is a hypothesis, not a verified fact.** If the raid turns out to
be noisy mid-boss, the levers are the `BroadcastChance*` family, and the
finding belongs in an ADR.

---

## Moving the raid to a new tier

`AiPlayerbot.AutoGearScoreLimit` sets the ceiling. Currently `141`.

The order matters, and one step will bite you:

1. Raise `AutoGearScoreLimit`.
2. `.reload config` then `.playerbots bot reload`.
3. Run `scripts/gear-pass.sh` — it forces the spec roll *before* gearing,
   which is the whole reason it exists (`init=` rolls a spec by
   probability and then gears for whatever it rolled).
4. Re-verify the tank floor by hand (below).
5. `.save` before trusting `roster-status.sh` — it reads last-saved
   state.

**`restore` is not cleanup.** It is easy to confuse with a reset and it
does not do what the name suggests. Read the archive repo's
`docs/session.md` §"The step that will bite you" before using it.

### The tank has a hard floor

490 defence, and it is met by **hand-picking items, not by raising the
tier**. `StatsWeightCalculator` scores raw stats and has no concept of
defence skill or its cap, so it fills trinkets, neck and shield with
zero-defence pieces. The budget is never the constraint — at any given
tier the available items total well past what is needed. Four `.additem`
calls fix it.

`Bullwark` is hand-itemized and never re-rolled. He is currently at
**534 defence skill — crit-immune, comfortably clear.**

> **The three off-tanks are NOT, and this is live.** Measured
> 2026-08-13:
>
> | Bot | Defence skill | Needs |
> |---|---|---|
> | Ararin | 476 | 490 |
> | Crumm | 475 | 490 |
> | Rechiw | 447 | 490 |
>
> All three are crittable by a level 73 boss. `roster-status.sh` also
> reports **3 defence items sitting in Ararin's bags, unequipped** — so
> at least part of his gap is free to close.
>
> This is the expected failure mode, not a surprise:
> `StatsWeightCalculator` scores raw stats and has no concept of defence
> skill or its cap, so an automated pass never fills the gap on its own.
> It matters less for an off-tank than a main tank — they are holding
> adds, not bosses — but a crit on a plate body holding a Black Temple
> add pack is still how a wipe starts. Worth an evening with `.additem`
> before the next serious night.

If a gear pass ever re-rolls one of the three, their crit immunity is the
first thing to re-check — and clear the `co` override with `co !` first,
or they come back running the old spec's strategies.

---

## Encounter notes

### Karazhan's Chess event — skip it

mod-playerbots has no chess code whatsoever, and the encounter is built
around players charming pieces: uncharmed friendly pieces never move and
cast at half the enemy rate, so "let the AI play it" loses by design, not
by luck. Open the Gamesman's exit door with `.gobject activate` and move
on. `.instance setbossstate` does not work here.

### The mechanics you now execute by hand

Nine triggers across Karazhan gate on `IsTank(bot)` / `IsMainTank(bot)`,
evaluated inside each *bot's* own AI. With a human tanking they are dead
code. Most are tank positioning and target marking — which a human tank
does natively and enjoys doing. **Two are genuinely more work:**

- **Netherspite's beam rotation.** Yours to call.
- **Prince Malchezaar's Infernals.** `disperse` is your friend.

This is the accepted price of the human tanking. It is not a bug and it
is not fixable without patching the module.

### Zul'Aman — the hunter is load-bearing

All six ZA "pulling boss" triggers open with
`if (bot->getClass() != CLASS_HUNTER) return false;`. Every pull in the
instance is a hunter's Misdirection. Bring `Fehmos` or `Ilyna`.

Note also that ZA's Nalorakk and Halazzi branch on
`IsAssistTankOfIndex(bot, 0, true)` — bot self-checks, so those swap
mechanics are hand-executed too, same as Karazhan's.

### Magtheridon's cube phase

Needs five bodies clicking Manticron Cubes on a timer, with the strategy
auto-assigning one non-Warlock ranged per cube and reassigning on death.
Attemptable at 25 bodies, but expect it to be the messy part. Known
issue: below ~30% Mag may cast Blast Nova on a ~20s timer against the
~55s baseline — too fast for Mind Exhaustion to fade from clickers.
Expect some late wipes; that is a module bug, not your setup.

### There is no generic Misdirection

`grep -ri misdirection` across the module hits only `src/Ai/Raid/SSC/`
and `src/Ai/Raid/ZA/`. Hunters do not misdirect outside those two
scripted instances, so **no bot assists your threat anywhere else.**
Recorded because it is the obvious thing to assume and it is false.
