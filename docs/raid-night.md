# Running a raid night

Start here to actually play. `CLAUDE.md` has the five rules that explain
*why* several of these steps exist; this file is the order to do them in.

---

## Starting a session

**For a 10-man, there is no opener.** Log in as `Bullwark` and the nine
bots on your account are added automatically — `BotAutologin` adds every
character on your own account, and `KeepAltsInGroup` brings them back
already grouped.

That standing ten is:

| | |
|---|---|
| Bullwark | human prot warrior — **main tank** |
| Ararin | prot paladin off-tank (converted, 511 defence) |
| Nathos, Krast, Tanke, Restofarian | holy pal, resto shaman, 2× resto druid |
| Izri, Dijito, Ilyna | mage, shadow priest, hunter |
| Anmine | rogue |

Two things worth a glance before pulling:

1. **The server takes ~6 minutes to become ready.** The units are
   `Type=simple`, so `systemctl start` returns while the world is still
   loading. Watch the journal, not the unit state:
   ```bash
   ssh root@192.168.4.124 'journalctl -u hprv-worldserver -n 20 --no-pager'
   ```
2. **Check the raid-frame flags.** They are role assignments, they
   persist in the database, and a stale one silently hands the raid to
   the wrong body. This file used to say "do not flag anyone" — that was
   wrong, and it cost a Black Temple night. See "Raid flags are
   assignments" below, and ADR `0003`.

### Raid flags are assignments — check them before a serious night

Two flags in `group_member.memberFlags` drive module behaviour, they
survive logout and server restart, and nothing in the game announces
them:

| Flag | Value | What the module does with it |
|---|---|---|
| `MEMBER_FLAG_ASSISTANT` | `1` | orders **every** per-role index — assist tank 0/1, assist heal 0, assist ranged. Assistants sort ahead of everyone else; group join order only breaks ties |
| `MEMBER_FLAG_MAINTANK` | `2` | `GetMainTankGuid()` returns this body **without checking `IsTank()`** |
| `MEMBER_FLAG_MAINASSIST` | `4` | nothing. The module never reads it |

The trap is the second one. `GetMainTankGuid()` (`PlayerbotAI.cpp:2378`)
looks for the flag first and only falls back to "first alive `IsTank()`
body" if nobody carries it. So a flag left on a rule-1-converted plate
bot makes *that* bot the main tank — no taunt, no tank strategies, and
in `Ararin`'s case 476 defence and crittable — while your actual tank is
not main tank at all. Everything keyed on `IsMainTank()` follows it,
including scripted raid assignments and every hunter Misdirection in the
raid.

Read them out of the database; the raid frames will not tell you:

```sql
SELECT c.name, c.class, c.online, gm.memberFlags, gm.subgroup
  FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 ORDER BY gm.subgroup, gm.memberGuid;
```

**Set them deliberately.** When a bot main-tanks, put the main-tank flag
on that bot rather than trusting the fallback — join order changes every
time a body is summoned. Promote to assistant the bodies you actually
want as assist tank 0/1 and assist heal 0.

The same query is also your roster check. Run on 2026-08-15 it turned up
`Netohje` and `Gerina` in the raid — neither is in `roster.conf`.

#### Who can do what, and taking lead back from a bot

| Action | Needs |
|---|---|
| Set/clear raid target icons | leader **or** assistant (`GroupHandler.cpp:629`) |
| Set main tank / main assist | leader **or** assistant (`:727`) |
| Promote someone to assistant | **leader only** (`:713`) |

A bot holding raid lead is normal, not a fault: `KeepAltsInGroup`
restores whatever group existed, and a group formed while you played
`Bullwark` keeps him as leader forever after. Take it back:

```
/w Bullwark give leader
```

`GiveLeaderAction` needs an active player master and the bot to be
holding lead — both true in that situation. GM fallback if it ever
misbehaves: `.group leader <yourname>`.

Note that being **leader does not make you an assistant** — the flags
are independent. That matters more than it sounds: some encounter code
picks its body by assistant flag alone (see the Zerevor tank, below).

### For a 25-man night

Summon the extra bodies by name from the wider pool. The nine are already
in, so you need 15 more:

```bash
ssh root@192.168.4.124 /opt/hprv/scripts/roster-status.sh
```

prints the paste line ready to go. The command is `.playerbots bot`, not
`.bot` — there is no such alias at this pin.

### Only when a *new* plate bot joins

If you draw a fresh body from the pool and it arrives tank-specced,
convert it before it raids — once, ever:

```
/w <bot> co -tank,-tank assist,+dps,+dps assist
```

Skipping this is not subtle: it will taunt bosses off you on cooldown all
night. See `CLAUDE.md` rule 1.

### Playing someone other than Bullwark

**Auto-login is all-or-nothing.** The module runs a bare `SELECT name FROM
characters WHERE account = <yours>` and adds the lot — there is no
per-character exclusion. So whoever you pick, the other nine arrive, and
`Bullwark` is one of them. He has never taken a `co` (verified on the box
2026-08-14 — six of the ten carry overrides, he is not one), so as a bot
he arrives a **full tank**: `IsTank()` true, `LoseAggroTrigger` on
`taunt`, `tank assist` locked to the master's target.

That makes the swap safe or unsafe depending purely on what you pick.

| You play | What happens |
|---|---|
| **A DPS or healer** — Izri, Dijito, Ilyna, Anmine, Nathos, Krast, Tanke, Restofarian | **Fine, no preparation.** `Bullwark` main-tanks, which is what you want. Still exactly one `IsTank()` body, so the `+threat` cap works and `co -threat` stays forbidden. |
| **Ararin**, or any plate body | **Rule 1, mirrored.** Two `IsTank()` bodies — you via the prot spec fallback, him via his tank strategies. He taunts the boss off you on cooldown all night. |

One exception to "no preparation": **play a mage into Black Temple while
carrying a raid-assistant flag and the Illidari Council script makes you
its Zerevor tank**, silently, healer and all. That is a fine way to run
the fight — see the Council section below — but it should be a choice.

If you do want to tank on someone else, convert `Bullwark` once, ever,
while he is in your group as a bot:

```
/w Bullwark co -tank,-tank assist,+dps,+dps assist
```

Safe to leave in place permanently — `co` only governs bot AI, so it does
nothing on the nights you play him yourself, and `gear-pass.sh` already
refuses to re-roll his spec, so there is no rule-2 collision to worry
about. It is not applied by default precisely because leaving him
unconverted is what makes the DPS swap free.

> **`Bullwark` is the right bot tank, not `Netohje`.** `pool.conf` used
> to nominate Netohje for bot-tanked nights; he is ilvl 115 blue and
> fury-geared, i.e. crittable, and he costs a summon. Bullwark is
> hand-itemized at 534 defence and arrives for free. See ADR `0002`.

**Nobody advances the raid.** On any character, you lead. Every movement
primitive is relative to the master — `stay` calls `StopMoving()` and
clears CHASE and FOLLOW, `follow` releases it, `dps assist` only walks
DPS into range once a target exists. No body scouts ahead, picks a
route, or pulls the next pack unprompted. Playing a DPS hands `Bullwark`
the boss; it does not hand him the instance.

### Rechiw was never converted — do this before the next 25-man

**Verified on the box 2026-08-14.** `Rechiw` (guid 826) has **zero** rows
in `playerbots_db_store`, and his talents include Rune Tap (48982), Mark
of Blood (49005) and Vampiric Blood (55233) — deep blood *tank* talents.
With no override to modify them, `AiFactory` grants him the full tank
strategy set from his spec on every login. He has been taunting bosses
off you in every 25-man since he joined.

**This does not affect 10-man nights.** `Rechiw` lives on account 83, not
101, so he is not in the standing ten and does not auto-login. The only
plate body in the standing ten is `Ararin`, and he is genuinely
converted — a Karazhan night off auto-login is clean, with or without
this fix.

**The fix is gated on him being summoned.** `co` is whispered to a bot in
your group, so it can only land on a 25-man night. There is no way to
apply it from the console, and no DB-side shortcut worth trusting — the
module writes the row from the *entire live strategy list*, so hand-
inserting one means guessing what `AiFactory` would have built. Summon
him, whisper, done.

Fix it once, ever, the next time he is summoned:

```
/w Rechiw co -tank,-tank assist,+dps,+dps assist
```

Then confirm the row exists — the absence is the whole bug:

```sql
SELECT c.name, s.value FROM acore_playerbots.playerbots_db_store s
  JOIN acore_characters.characters c ON c.guid = s.guid
 WHERE s.`key` = 'co' AND c.name = 'Rechiw';
```

> **Why this hid for a day.** `roster.conf` recorded "Verified in
> `playerbots_db_store` 2026-08-13: none carries `+tank` or `+tank
> assist`." That query asks whether anyone *carries* the tank
> strategies — and a bot with no rows at all answers "no" while running
> them from spec. The check passed vacuously. **Absence of a `co` row is
> not evidence of conversion; it is evidence of the opposite.** Always
> assert the row is present, never that the string is missing.

`Crumm` and `Ararin` are genuinely converted and need nothing. Of the 24
raid bots, 21 carry a `co` row; the three that do not are `Rechiw`,
`Tanke` and `Anmine` — and the latter two are a resto druid and a rogue,
so they need no conversion.

### If the server was restarted

Nothing extra. Every override lives in the database, not in memory.

## Ending a session

Just log out. The bots go with you, and the raid lockout stays bound to
their names — which is why the pool is written down. Logging back in
restores the standing ten automatically and puts you in front of the same
half-cleared instance; for a 25-man, re-summon *the same* extra names, or
the raid resets in usefulness even though the lockout survives.

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

The `pull` / `pull back` strategies do the right thing. `AiFactory`
grants them to tank specs only, which is why this file used to claim no
body in the raid had them — **that was wrong.** Verified on the box
2026-08-14: `Ararin`'s saved `co` list carries `+pull,+pull back`.

That is rule 2 working in your favour for once. The conversion whisper
took away `+tank` and `+tank assist`, but `Save()` wrote his *entire*
strategy list — including the pull strategies `AiFactory` had already
granted him while he was tank-specced. They are frozen in and they apply
on every login. `Crumm` carries them too, for the same reason. `Rechiw`
does not — he carries no override at all, which is a live fault; see
"Rechiw was never converted" below.

So `pull` in `/raid` is available today. Do not "fix" those entries out.

**What `pull` actually looks like, and why the tank turns his back.**
`pull` records **the bot's own position at the moment you type it** as
`position["pull"]`, walks him into range of his pull action, and fires.
For a warrior that action is `"shoot"` (`WarriorPullStrategy.h:15`) —
`heroic throw` is checked first but is a level-80 ability, so at 70 he
always falls through to the ranged slot. `Bullwark` carries a Windspear
Longbow, so he pulls at bow range; **a warrior with an empty ranged slot
cannot pull at all** (`CanDoPullAction` refuses; only paladins and
druids are exempt from that check).

Then `pull back` — a *separate* strategy — walks him back to the
recorded spot, which is the "turns around and runs into the group"
part. The pull ends when he is within follow range of it, or after 15
seconds flat (`GetMaxPullTime()`).

That is correct behaviour for trash: it drags the pack to the raid. It
is a bad deal on a boss, because **your tank spends the return leg with
his back turned** — no dodge, parry or block, and no threat generated.
Three options, cheapest first: stand him where you want the fight and
*then* type `pull`, since the return spot comes from his feet at that
instant; or skip `pull` for boss pulls and open yourself, letting `tank
assist` hand him the boss; or `/w Bullwark co -pull back`, which keeps
the pull and drops the return — at the cost of writing him a `co` row
he does not currently have (rule 2).

If you would rather not use it, two ways round the marking problem.
Easiest: **mark after the pull lands** — pull with your own shot, let the
pack reach you, then skull. Otherwise hold them explicitly:

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

### Black Temple — the Illidari Council

**The fight is fully scripted at this pin and takes no orders.** Eleven
triggers and seven multipliers in `src/Ai/Raid/BT/`, wired at
`BTStrategy.cpp:120-152`, applied automatically on entering map 564 by
`ApplyInstanceStrategies()`. It assigns by **role**, and resolves each
role itself:

| Boss | Icon it sets | Role | Resolved by |
|---|---|---|---|
| Gathios | square | main tank | `IsMainTank()` |
| Lady Malande | star | assist tank 0 | `IsAssistTankOfIndex(bot, 0, false)` |
| Veras Darkshadow | circle | assist tank 1 | `IsAssistTankOfIndex(bot, 1, false)` |
| Zerevor | triangle | a **mage** tank | `GetZerevorMageTank()` |
| — | — | dedicated healer | `IsAssistHealOfIndex(bot, 0, true)` |

All four share a health pool (`SPELL_EMPYREAL_BALANCE`), so kill order
is meaningless — the whole fight is about who absorbs whose damage.

**Setup, in order:**

1. **Main-tank flag onto `Bullwark`.** If it is sitting on `Ararin` the
   module's main tank is a converted, crittable DPS-strategy paladin.
2. **Restore tank strategies on two plate bodies** — this fight only:
   ```
   /w Ararin co +tank,+tank assist,-dps,-dps assist
   /w Crumm  co +tank,+tank assist,-dps,-dps assist
   ```
   `IsAssistTankOfIndex` gates on `IsTank()`, so a fully converted raid
   supplies **zero** assist tanks and Malande and Veras go untanked.
   Rule 1 cannot fire here — the encounter's own
   `IllidariCouncilDisableTankActionsMultiplier` zeroes taunt, dark
   command, hand of reckoning, righteous defense, challenging
   shout/roar, growl, cleave, shockwave, D&D and blood boil for every
   `IsTank()` bot in combat with Gathios, and zeroes `TankAssistAction`
   once they have a victim. **Restore at the Council's door, not at the
   instance entrance** — the suppression only applies once the bot is
   actually on Gathios's threat list. **Revert both before Illidan.**
   See ADR `0004`.
3. **Promote both to assistant**, so they take index 0 and 1
   deterministically instead of by join order.
4. **Promote the healer you want as the Zerevor healer** — *not*
   `Nathos`. Assist-heal-0 gets pinned to two fixed spots beside
   Zerevor and will not move for anything else; you want your only
   single-target tank healer free for `Bullwark`. `Olidina` or `Dehme`.
5. **Decide who tanks Zerevor.** `GetZerevorMageTank()` returns the
   first **raid-assistant** mage — bot or human, it does not check —
   and only then falls back to the first bot mage. So if you are
   playing a mage and carry an assistant flag, **you are the Zerevor
   tank** whether or not anyone told you. Taking it is fine and is the
   intended shape of the fight: Spellsteal his Dampen Magic, hold him
   away from Malande, and **never Ice Block** (the module explicitly
   disables Ice Block for its own mage tank — dropping threat sends him
   into the raid). If you die, the role falls through to the first bot
   mage, position, marking, healer and all.

**Before every attempt, reset the marks.** Raid icons are group state and
survive a wipe, and the script also sets each bot's own `rti` to
square/star/circle/triangle. `DpsTargetValue::Calculate()` returns the
RTI target first, gated only on alive + LOS + sight range — so walking
back into the room hands every bot a live target and re-pulls the
encounter instantly. In `/raid`:

```
rti skull
```

then target each Council member and `/run SetRaidTarget("target",0)`.
You need leader or assistant for that macro to do anything at all.

**Then pull:** mark Gathios skull and open on him. Expect ~5 seconds of
DPS bots doing nothing (`IllidariCouncilWaitForDpsMultiplier` holds
non-tank attacks while the tanks establish), and no DPS cooldowns or
trinkets until Gathios drops under 90%.

**The clock is the boss.** Veras schedules a **15-minute berserk**
(`boss_illidari_council.cpp:543`): all four gain `SPELL_BERSERK` and
Veras wipes his threat list in the same instant, landing on a healer.
There is a yell attached — when you hear it the attempt is over. The
pool is ~4.89M, which needs ~5,430 raid DPS. At `AutoGearScoreLimit =
141` the raid does ~4,130. **Gear pass first; see ADR `0005`.**

Known leak you cannot fix from chat: Gathios re-blesses a Council member
with Blessing of Protection or Spell Warding every 15s, and only rogues,
DPS warriors and DPS shamans know to switch off an immune target.
Everything else keeps hitting it, and with a shared pool that damage is
simply lost.

### Misdirection: generic for the main tank, scripted in seven raids

This file used to say there is no generic Misdirection and that "no bot
assists your threat anywhere else". **That is wrong at this pin.**
`GenericHunterStrategy.cpp:68` wires the `low tank threat` trigger to
`misdirection on main tank`, so hunters misdirect anywhere, in any
content, whenever tank threat runs low.

The catch is who they misdirect to: `BuffOnMainTankAction` resolves its
target through `FindMainTankPlayer::Check → IsMainTank()`, which follows
`MEMBER_FLAG_MAINTANK`. A stale flag therefore feeds every hunter
Misdirection in the raid to the wrong body, everywhere — one more
reason to audit the flags.

Scripted, instance-specific misdirection additionally exists in
`src/Ai/Raid/` under `BT/`, `Gruul/`, `Hyjal/`, `Mag/`, `SSC/`, `TK/`
and `ZA/` — not only SSC and ZA as previously recorded.
