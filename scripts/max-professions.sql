-- HPRV — max a character's professions to 375 with every trainer recipe
--
-- TODO item 5. First used on Bullwark, 2026-09-26: Blacksmithing
-- (Armorsmith) + Engineering (Goblin) + Cooking, First Aid, Fishing.
-- Generic by name: edit the three SET blocks, nothing else.
--
-- WHAT "MAXED" MEANS HERE
--   * skill value and max 375 (Master, the level-70 cap). No Grand Master.
--   * every rank spell Apprentice -> Master. All of them, not only Master:
--     Player::SetSkill's unlearn loop walks the chain from its first rank,
--     and a missing first rank leaves stray ranks re-granting the skill
--     after relog (core issue #2330, noted in cs_learn.cpp).
--   * every TRAINER recipe with ReqSkillRank <= 375 and ReqLevel <= 70,
--     taught by at least one trainer outside Northrend (map 571).
--     Northrend-only trainer recipes are excluded to fit a TBC world.
--   * spec-gated recipes only for the specialisation granted below.
--   Not .learn all recipes: that command teaches drop and vendor recipes
--   and every rank to Grand Master (450), which is the opposite of the brief.
--
-- NOT TAUGHT: the trainer's rank-teaching wrapper spells (the rank spells
-- are inserted directly instead), including the five that teach
-- Grand Master.
--
-- RUN WITH THE CHARACTER OFFLINE. An online character's in-memory state
-- overwrites these rows at its next save. The worldserver can stay up.
-- Dump acore_characters first.
--
-- A bot re-rolled by init= may lose this (PlayerbotFactory touches skills).
-- Bullwark is never init='d, so it's safe for him. Check the factory before
-- using this on the rest of the ten (TODO item 5).

-- Multi-table statements with aliases need a default DB (ERROR 1046).
USE acore_characters;

SET @name := 'Bullwark';

START TRANSACTION;

SET @guid := (SELECT guid FROM acore_characters.characters WHERE name = @name);

-- Guards: a false condition raises ERROR 1242 and the client stops. The
-- open transaction rolls back on disconnect.
SELECT IF(@guid IS NOT NULL, CONCAT('ok: ', @name, ' is guid ', @guid), (SELECT 1 UNION SELECT 2)) AS precheck_exists;
SELECT IF(online = 0, 'ok: offline', (SELECT 1 UNION SELECT 2)) AS precheck_offline
  FROM acore_characters.characters WHERE guid = @guid;

-- ---- EDIT: which skills --------------------------------------------------
--   164 Blacksmithing  202 Engineering  (primaries, max 2 — MaxPrimaryTradeSkill)
--   185 Cooking  129 First Aid  356 Fishing  (secondaries)
DROP TEMPORARY TABLE IF EXISTS hprv_prof_skill;
CREATE TEMPORARY TABLE hprv_prof_skill (skill INT PRIMARY KEY);
INSERT INTO hprv_prof_skill VALUES (164), (202), (185), (129), (356);

-- ---- EDIT: specialisations granted (quest-learned in game) ---------------
--   9788 Armorsmith, 9787 Weaponsmith (17039/17040/17041 master sword/hammer/axe)
--   20222 Goblin Engineer, 20219 Gnomish Engineer
DROP TEMPORARY TABLE IF EXISTS hprv_prof_spec;
CREATE TEMPORARY TABLE hprv_prof_spec (spell INT PRIMARY KEY);
INSERT INTO hprv_prof_spec VALUES (9788), (20222);

-- ---- EDIT: primary professions to REMOVE to stay within 2 ------------------
--   Bullwark carried Herbalism 1/75 (skill 182, Apprentice rank 2366).
DROP TEMPORARY TABLE IF EXISTS hprv_prof_drop;
CREATE TEMPORARY TABLE hprv_prof_drop (skill INT, spell INT);
INSERT INTO hprv_prof_drop VALUES (182, 2366);

-- ---- fixed data: rank chains, Apprentice -> Master -----------------------
-- Checked 2026-09-26: 164/202 chains are exactly the ReqAbility1
-- prerequisites in trainer_spell; the 202/185/129/356 chains match what
-- the all-profession bot Tebie knows.
DROP TEMPORARY TABLE IF EXISTS hprv_prof_rank;
CREATE TEMPORARY TABLE hprv_prof_rank (skill INT, spell INT, PRIMARY KEY (skill, spell));
INSERT INTO hprv_prof_rank VALUES
  (164, 2018), (164, 3100), (164, 3538), (164, 9785), (164, 29844),
  (202, 4036), (202, 4037), (202, 4038), (202, 12656), (202, 30350),
  (185, 2550), (185, 3102), (185, 3413), (185, 18260), (185, 33359),
  (129, 3273), (129, 3274), (129, 7924), (129, 10846), (129, 27028),
  (356, 7620), (356, 7731), (356, 7732), (356, 18248), (356, 33095);

-- Rank-teaching wrappers: trainer spells whose prerequisite is the
-- previous rank. The last in each row teaches GRAND MASTER.
DROP TEMPORARY TABLE IF EXISTS hprv_prof_wrapper;
CREATE TEMPORARY TABLE hprv_prof_wrapper (spell INT PRIMARY KEY);
INSERT INTO hprv_prof_wrapper VALUES
  (2021), (3539), (9786), (29845), (51298),
  (4040), (4041), (12657), (30351), (61464),
  (3412), (54257), (18261), (54256), (51295),
  (3280), (54254), (10847), (54255), (50299),
  (7734), (54083), (18249), (54084), (51293);

-- 1. Drop the surplus primary.
DELETE s FROM acore_characters.character_skills s
  JOIN hprv_prof_drop d ON d.skill = s.skill
 WHERE s.guid = @guid;
DELETE sp FROM acore_characters.character_spell sp
  JOIN hprv_prof_drop d ON d.spell = sp.spell
 WHERE sp.guid = @guid;

-- 2. Ranks and specialisations. specMask 255 = both talent specs, as the
--    character's existing rows carry.
INSERT IGNORE INTO acore_characters.character_spell (guid, spell, specMask)
SELECT @guid, r.spell, 255 FROM hprv_prof_rank r JOIN hprv_prof_skill k ON k.skill = r.skill;

INSERT IGNORE INTO acore_characters.character_spell (guid, spell, specMask)
SELECT @guid, spell, 255 FROM hprv_prof_spec;

-- 3. Recipes. The prerequisite must be none, or something the character
--    now knows (covers the chosen spec and the riding-gated flying
--    machines), which leaves out other specs' recipes automatically.
--    Staged through a temp table, because INSERT ... SELECT can't read
--    the table it inserts into here.
DROP TEMPORARY TABLE IF EXISTS hprv_prof_known;
CREATE TEMPORARY TABLE hprv_prof_known (spell INT PRIMARY KEY)
SELECT spell FROM acore_characters.character_spell WHERE guid = @guid;

INSERT IGNORE INTO acore_characters.character_spell (guid, spell, specMask)
SELECT DISTINCT @guid, ts.SpellId, 255
  FROM acore_world.trainer_spell ts
  JOIN hprv_prof_skill k ON k.skill = ts.ReqSkillLine
 WHERE ts.ReqSkillRank <= 375
   AND ts.ReqLevel <= 70
   AND ts.SpellId NOT IN (SELECT spell FROM hprv_prof_wrapper)
   AND (ts.ReqAbility1 = 0 OR ts.ReqAbility1 IN (SELECT spell FROM hprv_prof_known))
   AND EXISTS (SELECT 1 FROM acore_world.creature_default_trainer cdt
                 JOIN acore_world.creature cr ON cr.id = cdt.CreatureId
                WHERE cdt.TrainerId = ts.TrainerId AND cr.map <> 571);

-- 4. Skill values.
INSERT INTO acore_characters.character_skills (guid, skill, value, max)
SELECT @guid, skill, 375, 375 FROM hprv_prof_skill
ON DUPLICATE KEY UPDATE value = 375, max = 375;

-- 5. Verify inside the transaction. (A temp table can't be opened twice
--    in one statement, ERROR 1137, hence the variable.)
SET @nskill := (SELECT COUNT(*) FROM hprv_prof_skill);
SELECT IF(COUNT(*) = @nskill, 'ok: every chosen skill at 375/375', (SELECT 1 UNION SELECT 2)) AS check_skills
  FROM acore_characters.character_skills s JOIN hprv_prof_skill k ON k.skill = s.skill
 WHERE s.guid = @guid AND s.value = 375 AND s.max = 375;

-- Primary professions held: must be <= 2.
SELECT IF(COUNT(*) <= 2, CONCAT('ok: ', COUNT(*), ' primary professions'), (SELECT 1 UNION SELECT 2)) AS check_primaries
  FROM acore_characters.character_skills
 WHERE guid = @guid AND skill IN (164,165,171,182,186,197,202,333,393,755,773);

-- No Grand Master rank or wrapper crept in.
SELECT IF(COUNT(*) = 0, 'ok: no Grand Master / wrapper spells', (SELECT 1 UNION SELECT 2)) AS check_no_gm
  FROM acore_characters.character_spell
 WHERE guid = @guid AND (spell IN (51300,51306,51296,45542,51294) OR spell IN (SELECT spell FROM hprv_prof_wrapper));

SELECT ts.ReqSkillLine AS skill, COUNT(DISTINCT sp.spell) AS trainer_recipes_known
  FROM acore_characters.character_spell sp
  JOIN acore_world.trainer_spell ts ON ts.SpellId = sp.spell
 WHERE sp.guid = @guid AND ts.ReqSkillLine IN (SELECT skill FROM hprv_prof_skill)
 GROUP BY ts.ReqSkillLine;

COMMIT;
