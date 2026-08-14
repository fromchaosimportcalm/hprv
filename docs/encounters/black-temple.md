# Black Temple

Map 564. `RaidBlackTempleStrategy` ("blacktemple") is applied
automatically on entry by `ApplyInstanceStrategies()`
(`PlayerbotAI.cpp:1620`), which first strips every other instance
strategy — so nothing needs whispering, and the `+blacktemple` frozen
into 21 `co` rows by rule 2 is inert everywhere else.

Cleared: Naj'entus, Supremus. Furthest attempt: Illidari Council.

---

## The Illidari Council

**Fully scripted, and it takes no orders.** Eleven triggers, twelve
actions and seven multipliers in `src/Ai/Raid/BT/`, wired at
`BTStrategy.cpp:120-152`. It assigns by **role** and resolves each role
itself:

| Boss | Icon it sets | Role | Resolved by |
|---|---|---|---|
| Gathios the Shatterer | square | main tank | `IsMainTank()` |
| Lady Malande | star | assist tank 0 | `IsAssistTankOfIndex(bot, 0, false)` |
| Veras Darkshadow | circle | assist tank 1 | `IsAssistTankOfIndex(bot, 1, false)` |
| High Nethermancer Zerevor | triangle | a **mage** tank | `GetZerevorMageTank()` |
| — | — | dedicated healer | `IsAssistHealOfIndex(bot, 0, true)` |

All four share a health pool (`SPELL_EMPYREAL_BALANCE`, set on the
controller at `boss_illidari_council.cpp:151`; member damage is
forwarded to it in `DamageTaken`). **Kill order is meaningless.** The
entire fight is about which body absorbs whose damage.

### Setup, in order

**1. Main-tank flag onto `Bullwark`.** If it is sitting on `Ararin`, the
module's main tank is a rule-1-converted paladin with no tank
strategies, no taunt and no crit immunity. See `CLAUDE.md` rule 6.

**2. Restore tank strategies on two plate bodies — this fight only.**

```
/w Ararin co +tank,+tank assist,-dps,-dps assist
/w Crumm  co +tank,+tank assist,-dps,-dps assist
```

`IsAssistTankOfIndex` opens with `if (!IsTank(player)) return false;`, so
a correctly converted raid supplies **zero** assist tanks — Malande and
Veras go untanked and `IllidariCouncilAssignDpsTargetsAction` falls
through to Gathios for everyone.

Rule 1 cannot fire here: `IllidariCouncilDisableTankActionsMultiplier`
zeroes taunt, dark command, hand of reckoning, righteous defense,
challenging shout/roar, growl, cleave, shockwave, D&D and blood boil for
every `IsTank()` bot in combat with Gathios, and zeroes
`TankAssistAction` once they have a victim.

**Restore at the Council's door, not at the instance entrance.** The
suppression gates on `find target "gathios the shatterer"`, and
`FindTargetValue::Calculate()` (`TargetValue.cpp:160`) searches only the
bot's own threat list — so a restored tank is unprotected on the trash
in between. **Revert both before Illidan.** ADR `0004`.

**3. Promote both to raid assistant**, so they take index 0 and 1
deterministically rather than by group join order.

**4. Promote the healer you want as the Zerevor healer — not `Nathos`.**
Assist-heal-0 gets pinned to two fixed spots beside Zerevor and will not
move for anything else. You want your only single-target tank healer
free for `Bullwark`. `Olidina` or `Dehme`.

**5. Decide who tanks Zerevor.** `GetZerevorMageTank()`
(`BTHelpers.cpp:138`) returns the first **raid-assistant** mage — bot or
human, it does not check — and only then falls back to the first bot
mage. **If you are playing a mage and carry an assistant flag, you are
the Zerevor tank**, whether or not anyone told you.

Taking it is fine and is the intended shape of the fight:

- Spellsteal his Dampen Magic.
- Hold him away from Malande — DPS bots skip her entirely while Zerevor
  is within 15 yards of her.
- **Never Ice Block.** The module explicitly disables it for its own
  mage tank; dropping threat sends Zerevor into the raid.
- If you die, the role falls through to the first bot mage — position,
  marking and dedicated healer included. Verified live: `Lomul` picked
  it up mid-fight without a stutter.

### Before every attempt: reset the marks

Raid icons are group state and survive a wipe, and the script also sets
each bot's own `rti` to square/star/circle/triangle.
`DpsTargetValue::Calculate()` returns the RTI target **first**, gated
only on alive + LOS + sight range — so walking back into the room hands
every bot a live target and re-pulls the encounter instantly.

In `/raid`:

```
rti skull
```

then target each Council member and `/run SetRaidTarget("target",0)`.
You need leader or assistant for that macro to do anything at all.

### The pull

Mark Gathios skull and open on him. Expect:

- **~5 seconds of DPS bots doing nothing** —
  `IllidariCouncilWaitForDpsMultiplier` holds non-tank attacks and
  non-healing casts while the tanks establish.
- **No DPS cooldowns or trinkets until Gathios is under 90%**
  (`DelayDpsCooldownsMultiplier`).
- Bullwark rotating through four fixed positions, dragging Gathios out
  of his own Consecration.
- Ranged spreading to 4 yards on Blizzard/Flamestrike/Consecration.
- Hunters misdirecting by index in group order: hunter 0 sends Zerevor
  to the mage tank, hunter 1 sends Malande to assist tank 0, hunter 2
  Gathios to the main tank, hunter 3 Veras to assist tank 1. **With two
  hunters, nothing misdirects Gathios or Veras** — open slowly.

### The clock is the boss

Veras schedules a **15-minute berserk** on engage
(`boss_illidari_council.cpp:543`). When it fires (`:573`) he wipes his
own threat list and re-picks — onto a healer or caster, never a tank —
while the controller casts `SPELL_BERSERK` on all four (`:244`). There
is a yell attached; when you hear it the attempt is over. Nothing heals
through it and no positioning survives it.

**This is a gear check, and the ceiling is deliberate.** The shortfall
was measured on 2026-08-15 and the decision — raise the tier, do not
retune the fight — is ADR `0005`. The numbers live there and only
there, because a gear pass invalidates them.

### Known leak you cannot fix from chat

Gathios re-blesses a Council member with Blessing of Protection or
Blessing of Spell Warding every 15 seconds (`EVENT_SPELL_BLESSING`,
rescheduled `:329`). With a shared pool, damage into an immune target is
a total loss rather than a redirect.

`IllidariCouncilAssignDpsTargetsAction` only teaches **rogues and DPS
warriors** to avoid a Blessing-of-Protection target and **DPS shamans**
to avoid a Spell-Warding one. Mages, warlocks, shadow priests, hunters,
balance druids, retribution paladins and death knights keep hitting
through both. Marking cannot correct it — the script rewrites each
bot's RTI every tick. Module patch or nothing; it is listed with the
deferred patches in `CLAUDE.md`.

---

## Not yet written up

Naj'entus and Supremus are cleared but undocumented — write them up next
time they are run. Illidan has substantial scripted support in
`BTActions.cpp` (phase tracking, Flames of Azzinoth assist tanks,
Parasitic Shadowfiend handling, shadow traps) that nobody has tested
here yet.
