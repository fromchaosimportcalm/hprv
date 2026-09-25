## Reset the roster to Tier 4 and progress again from Karazhan
Date: 2026-09-25
Tags: gear,tier,reset,autogearscorelimit,vendors,custom-npcs,hprv

Context: The raid had outrun its content. `AutoGearScoreLimit` stood at 141 with most of the pool at 134–139, and hand-added pieces well past that — Bullwark up to ilvl 154, Tanke to 164, Vestanza to 151. Karazhan no longer bit, and Black Temple was gated on a 30% DPS gap (ADR `0005`). Clinton chose to restart progression at Tier 4 and gear up through Karazhan again, with free tier and weapon vendors (`docs/custom-npcs.md`) as the way pieces get handed out.

Decision: Every equipped item above **ilvl 125** was **deleted** — not mailed; that was the explicit choice — from all 25 roster bodies (`scripts/roster.conf`: Bullwark + BOT_01..24): 165 pieces, then 189 from the 13 bots the first pass missed, 354 in all. Bags and bank were not touched. `AutoGearScoreLimit` was lowered 141 → 125 with `gear-pass.sh tier kara`. Full `acore_characters` dumps were taken before each pass: `/opt/hprv/backups/acore_characters-20260925-035723.sql.gz` and `-041426.sql.gz`.

Reasoning: 125 is the Phase 1 ceiling (Karazhan, Gruul, Magtheridon) as `playerbots.conf` defines it, i.e. the true start of Tier 4. Deleting rather than mailing keeps it a clean restart; the dumps are the undo.

**What the cap actually does — corrects earlier docs.** Read in the module source at this pin, `autoGearScoreLimit` is consulted only by the `autogear` and `autogear bis` whisper commands (`TrainerAction.cpp`), plus whatever `init=` gearscore `gear-pass.sh` derives from it. **Nothing in the loot or equip path reads it: bots equip drops regardless of the cap.** So it does not have to be raised for the raid to progress through drops. It stays at 125 as a guard against a stray `autogear` pulling gear with no ceiling, and gets raised with `gear-pass.sh tier <t>` only if `autogear` or a re-roll is wanted at the next tier.

**Consequence to handle before tanking: Bullwark's defence.** He was hand-itemized to 534 defence skill (crit-immune, floor 490), and those pieces were above 125. He is below the floor until re-itemized at Tier 4 — the archive's ADR `0008` did exactly this at Karazhan tier with four `.additem` calls, and `docs/raid-night.md` §"The tank has a hard floor" still applies. The converted off-tanks were already under the floor and now have less.

**Six pool characters outside the 25 were not stripped** and still carry ilvl 141–146 gear: Daedana, Caugotsa, Drusun, Eriona, Gerina, Grahlukk. The pool's other eleven non-roster characters are ungeared or already at ≤125. Run `scripts/strip-gear-above-ilvl.sql` with their names if they are ever summoned.

Alternatives: Mail the stripped pieces to their owners — declined, a clean restart was wanted. Remove the cap entirely — asked about, and left at 125 for now: since the cap does not gate drops, removing it buys nothing for progression and only removes the guard on `autogear`. Revisit if `autogear` is wanted uncapped. Strip at 141 (only the 23 hand-added pieces above the old cap) — declined, it would have left the raid in Tier 5 gear rather than at the start of Tier 4.

Affected: scripts/strip-gear-above-ilvl.sql, custom/, docs/custom-npcs.md, docs/raid-night.md, docs/pool.md, docs/build.md, CLAUDE.md, README.md, decisions/README.md
