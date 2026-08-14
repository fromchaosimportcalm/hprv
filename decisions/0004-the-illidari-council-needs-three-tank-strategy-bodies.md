## The Illidari Council needs three tank-strategy bodies, and rule 1 is suspended inside it
Date: 2026-08-15
Tags: playerbots,blacktemple,illidari-council,rule-1,co,tanking,hprv

Context: The Illidari Council is fully scripted at this pin. `src/Ai/Raid/BT/` carries eleven Council triggers, twelve actions and seven multipliers, wired in `BTStrategy.cpp:120-152` and `:238-245`, and applied automatically on entering map 564 by `ApplyInstanceStrategies()` (`PlayerbotAI.cpp:1620`) — which first strips every other instance strategy, so nothing needs to be whispered and the `+blacktemple` frozen into 21 `co` rows by rule 2 is confirmed inert outside Black Temple. The script does not take orders. It assigns by role, and it resolves each role itself:

| Council member | Icon it sets | Role | Resolved by |
|---|---|---|---|
| Gathios the Shatterer | square | main tank | `IsMainTank()` |
| Lady Malande | star | assist tank 0 | `IsAssistTankOfIndex(bot, 0, false)` |
| Veras Darkshadow | circle | assist tank 1 | `IsAssistTankOfIndex(bot, 1, false)` |
| High Nethermancer Zerevor | triangle | a mage "tank" | `GetZerevorMageTank()` |
| — | — | dedicated healer | `IsAssistHealOfIndex(bot, 0, true)` |

`IsAssistTankOfIndex` opens with `if (!IsTank(player)) return false;` (`PlayerbotAI.cpp:2500`), and `IsTank()` for a bot is `ContainsStrategy(STRATEGY_TYPE_TANK)` (`:2245`) — precisely what rule 1's conversion whisper clears. So a correctly rule-1-converted raid supplies **zero** assist tanks: Malande and Veras go untanked, and `IllidariCouncilAssignDpsTargetsAction` falls through its else-branch and points everyone at Gathios. Measured on the first attempt, 2026-08-15: total wipe, no visible assignments, no way to tell from inside the game which body was supposed to be where.

Decision: **For the Illidari Council, and only for it, restore tank strategies on two plate bodies and promote both to raid assistant. Revert immediately after the encounter, before Illidan.**

```
/w Ararin co +tank,+tank assist,-dps,-dps assist
/w Crumm  co +tank,+tank assist,-dps,-dps assist
```

then promote both to assistant so they take index 0 and 1 deterministically (ADR `0003`), and revert with the standard conversion whisper the moment the Council dies.

**Rule 1's failure mode is switched off inside this encounter by the encounter script itself.** `IllidariCouncilDisableTankActionsMultiplier` (`BTMultipliers.cpp`) returns `0.0f` for `CastTauntAction`, `CastDarkCommandAction`, `CastHandOfReckoningAction`, `CastRighteousDefenseAction`, `CastChallengingShoutAction`, `CastChallengingRoarAction`, `CastGrowlAction`, `CastCleaveAction`, `CastShockwaveAction`, `CastSwipeBearAction`, `CastDeathAndDecayAction` and `CastBloodBoilAction` for every `IsTank()` bot, and zeroes `TankAssistAction` once the bot has a victim of its own. The taunt-on-cooldown behaviour that rule 1 exists to prevent — `LoseAggroTrigger` firing forever because `tank assist` points the bot at the master's target — cannot execute here, because both halves of it are multiplied to zero.

That protection is scoped, and the scope is worth knowing: the multiplier gates on `AI_VALUE2(Unit*, "find target", "gathios the shatterer")`, and `FindTargetValue::Calculate()` (`TargetValue.cpp:160`) only searches the bot's own `GetThreatenedByMeList()`. A bot is protected while it is genuinely in combat with Gathios and not before. Since the controller calls `SetInCombatWithZone()` on all four members at pull (`boss_illidari_council.cpp:168`), that is satisfied for the whole raid from the first second of the fight — but it is emphatically not satisfied on the trash before it, which is the window where a restored tank can still misbehave. Restore the strategies at the Council's door, not at the instance entrance.

Reasoning: The alternative is not "one tank instead of three" — it is "one tank and two untanked bosses". The Council share a health pool (`SPELL_EMPYREAL_BALANCE`, set on the controller at `boss_illidari_council.cpp:151`), so kill order is meaningless and the entire fight is about which body absorbs which boss's damage. Malande free-casting Circle of Healing and Divine Wrath into a raid with nobody on her, and Veras roaming with no threat anchor, is not a tuning problem that better healing solves; it is four bosses' output landing on cloth. The second attempt, with the roles filled, ran cleanly for fifteen minutes and reached 24% — see ADR `0005` for why it still ended in a wipe, which was a DPS gate and not an assignment failure.

The costs are real and both are rule collisions, which is why this is a per-fight toggle rather than a standing configuration. Rule 2: the whisper calls `Save()` and rewrites the bot's **entire** strategy list, so restoring and reverting rewrites the frozen list twice; any gear pass that re-rolls these specs must still clear with `co !` first, and the conversions must be re-applied *after* the pass, not before. Rule 3: three `IsTank()` bodies restore the mutual-muting in `ThreatValue::Calculate()` (`ThreatValues.cpp`), which scales a bot's threat against the highest threat held by any *other* `IsTank()` member on that same target — outside this fight that is exactly the fault the single-tank layout was built to avoid. Hence: revert before Illidan, every time.

One detail that makes the human's part of this cheaper than it looks. `GetZerevorMageTank` skips dead members, so when the human mage holding Zerevor died, the assistant-mage branch stopped matching and the role fell through to the first bot mage — `Lomul` — who inherited the position, the marking and the dedicated healer without a hitch. The Zerevor assignment has a live fallback. The human's death costs a DPS body and the Spellsteal, not the role.

Alternatives: Leave the raid rule-1-converted and attempt the fight anyway — measured, and it is the wipe that prompted this. Convert nobody, permanently, so the Council works for free — that is rules 1 and 3 live on every other night of the year to buy one encounter. Flag two converted bodies as main tank / assistants without restoring their strategies — does nothing: `IsAssistTankOfIndex` checks `IsTank()` before it ever looks at flags, so the roles stay unfilled (and per ADR `0003`, a flag on a converted body is actively harmful for the main-tank slot). Patch `IsAssistTankOfIndex` to accept a DPS-strategy plate body, or teach the Council triggers to accept a human off-tank — the durable fix, and it belongs with the other two deferred module patches in `CLAUDE.md`'s open questions, to be costed at the next relink rather than paid for twice.

Affected: docs/encounters/black-temple.md, docs/raid-night.md, CLAUDE.md, decisions/README.md
