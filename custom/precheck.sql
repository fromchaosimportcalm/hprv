-- HPRV NPCs — precheck. Run first, against the world DB. Changes nothing.
--
--   mysql <world_db> < precheck.sql
--
-- It checks three things. Each check prints `ok: ...`, and a failing one
-- stops the client with ERROR 1242 ("Subquery returns more than 1 row").
-- The same guard pattern is used across HPRV. A failure prints what's
-- wrong just above the error.
--
--   1. SCHEMA. Every column the install files write or read exists. They
--      were written against the AzerothCore + playerbots pin in
--      pins.conf (2026-07), with creature_template_model split out and
--      creature.id as one column. A world DB much older or newer than
--      that may have renamed some of them. This check fails before any
--      install file runs, rather than halfway through one.
--   2. ID RANGE. 9100000-9100099 is free, or holds only these five NPCs
--      (so re-running is fine).
--   3. ITEM DATA. The stock items the vendors sell are all present: 306
--      tier pieces, 95 weapons.
-- ---------------------------------------------------------------------

-- 1. Schema --------------------------------------------------------------

DROP TEMPORARY TABLE IF EXISTS hprv_req;
CREATE TEMPORARY TABLE hprv_req (t VARCHAR(64), c VARCHAR(64));
INSERT INTO hprv_req VALUES
  ('creature_template','entry'),('creature_template','name'),('creature_template','subname'),
  ('creature_template','gossip_menu_id'),('creature_template','minlevel'),('creature_template','maxlevel'),
  ('creature_template','exp'),('creature_template','faction'),('creature_template','npcflag'),
  ('creature_template','unit_class'),('creature_template','unit_flags'),('creature_template','type'),
  ('creature_template','AIName'),('creature_template','HealthModifier'),('creature_template','VerifiedBuild'),
  ('creature_template_model','CreatureID'),('creature_template_model','Idx'),
  ('creature_template_model','CreatureDisplayID'),('creature_template_model','DisplayScale'),
  ('creature_template_model','Probability'),('creature_template_model','VerifiedBuild'),
  ('npc_text','ID'),('npc_text','text0_0'),('npc_text','Probability0'),('npc_text','VerifiedBuild'),
  ('gossip_menu','MenuID'),('gossip_menu','TextID'),
  ('gossip_menu_option','MenuID'),('gossip_menu_option','OptionID'),('gossip_menu_option','OptionIcon'),
  ('gossip_menu_option','OptionText'),('gossip_menu_option','OptionBroadcastTextID'),
  ('gossip_menu_option','OptionType'),('gossip_menu_option','OptionNpcFlag'),
  ('gossip_menu_option','ActionMenuID'),('gossip_menu_option','ActionPoiID'),
  ('gossip_menu_option','BoxCoded'),('gossip_menu_option','BoxMoney'),('gossip_menu_option','BoxText'),
  ('gossip_menu_option','BoxBroadcastTextID'),('gossip_menu_option','VerifiedBuild'),
  ('smart_scripts','entryorguid'),('smart_scripts','source_type'),('smart_scripts','id'),
  ('smart_scripts','link'),('smart_scripts','event_type'),('smart_scripts','event_phase_mask'),
  ('smart_scripts','event_chance'),('smart_scripts','event_flags'),
  ('smart_scripts','event_param1'),('smart_scripts','event_param2'),('smart_scripts','event_param3'),
  ('smart_scripts','event_param4'),('smart_scripts','event_param5'),('smart_scripts','event_param6'),
  ('smart_scripts','action_type'),('smart_scripts','action_param1'),('smart_scripts','action_param2'),
  ('smart_scripts','action_param3'),('smart_scripts','action_param4'),('smart_scripts','action_param5'),
  ('smart_scripts','action_param6'),('smart_scripts','target_type'),('smart_scripts','target_param1'),
  ('smart_scripts','target_param2'),('smart_scripts','target_param3'),('smart_scripts','target_param4'),
  ('smart_scripts','target_x'),('smart_scripts','target_y'),('smart_scripts','target_z'),
  ('smart_scripts','target_o'),('smart_scripts','comment'),
  ('creature','guid'),('creature','id'),('creature','map'),('creature','zoneId'),('creature','areaId'),
  ('creature','spawnMask'),('creature','phaseMask'),('creature','equipment_id'),
  ('creature','position_x'),('creature','position_y'),('creature','position_z'),('creature','orientation'),
  ('creature','spawntimesecs'),('creature','wander_distance'),('creature','currentwaypoint'),
  ('creature','curhealth'),('creature','curmana'),('creature','MovementType'),('creature','npcflag'),
  ('creature','unit_flags'),('creature','dynamicflags'),('creature','ScriptName'),
  ('creature','CreateObject'),('creature','Comment'),
  ('npc_vendor','entry'),('npc_vendor','slot'),('npc_vendor','item'),('npc_vendor','maxcount'),
  ('npc_vendor','incrtime'),('npc_vendor','ExtendedCost'),('npc_vendor','VerifiedBuild'),
  ('item_template','entry'),('item_template','itemset'),('item_template','InventoryType'),
  ('item_template','ItemLevel'),('item_template','BuyPrice');

SELECT r.t AS missing_table, r.c AS missing_column
  FROM hprv_req r
  LEFT JOIN information_schema.COLUMNS k
    ON k.TABLE_SCHEMA = DATABASE() AND k.TABLE_NAME = r.t AND k.COLUMN_NAME = r.c
 WHERE k.COLUMN_NAME IS NULL;

-- MySQL can't open a temporary table twice in one query, so count first.
SET @hprv_req = (SELECT COUNT(*) FROM hprv_req);
SET @hprv_missing = (SELECT COUNT(*) FROM hprv_req r
  LEFT JOIN information_schema.COLUMNS k
    ON k.TABLE_SCHEMA = DATABASE() AND k.TABLE_NAME = r.t AND k.COLUMN_NAME = r.c
 WHERE k.COLUMN_NAME IS NULL);

SELECT IF(@hprv_missing = 0, CONCAT('ok: all ', @hprv_req, ' columns present'),
          (SELECT 1 UNION SELECT 2)) AS check_schema;

-- 2. ID range ------------------------------------------------------------

SELECT 'creature_template' AS tbl, `entry` AS id, `name` AS holder FROM `creature_template`
 WHERE `entry` BETWEEN 9100000 AND 9100099
   AND (`entry`, `name`) NOT IN ((9100000, 'Porter Nozdrel'), (9100001, 'Almari Stonebrand'),
        (9100002, 'Veshan Coilhand'), (9100003, 'Oriel Duskmantle'), (9100004, 'Torvek Ashforge'))
UNION ALL
SELECT 'creature', `guid`, CONCAT('spawn of entry ', `id`) FROM `creature`
 WHERE `guid` BETWEEN 9100000 AND 9100099 AND `id` NOT BETWEEN 9100000 AND 9100004
UNION ALL
SELECT 'gossip_menu', `MenuID`, CONCAT('text ', `TextID`) FROM `gossip_menu`
 WHERE `MenuID` BETWEEN 9100000 AND 9100099 AND NOT (`MenuID` = 9100000 AND `TextID` = 9100000)
UNION ALL
SELECT 'npc_text', `ID`, LEFT(`text0_0`, 40) FROM `npc_text`
 WHERE `ID` BETWEEN 9100000 AND 9100099 AND `ID` <> 9100000
UNION ALL
SELECT 'smart_scripts', `entryorguid`, `comment` FROM `smart_scripts`
 WHERE `entryorguid` BETWEEN 9100000 AND 9100099 AND `source_type` = 0 AND `comment` NOT LIKE 'Porter - %';

SELECT IF(
  (SELECT COUNT(*) FROM `creature_template` WHERE `entry` BETWEEN 9100000 AND 9100099
      AND (`entry`, `name`) NOT IN ((9100000, 'Porter Nozdrel'), (9100001, 'Almari Stonebrand'),
           (9100002, 'Veshan Coilhand'), (9100003, 'Oriel Duskmantle'), (9100004, 'Torvek Ashforge')))
 + (SELECT COUNT(*) FROM `creature` WHERE `guid` BETWEEN 9100000 AND 9100099 AND `id` NOT BETWEEN 9100000 AND 9100004)
 + (SELECT COUNT(*) FROM `gossip_menu` WHERE `MenuID` BETWEEN 9100000 AND 9100099 AND NOT (`MenuID` = 9100000 AND `TextID` = 9100000))
 + (SELECT COUNT(*) FROM `npc_text` WHERE `ID` BETWEEN 9100000 AND 9100099 AND `ID` <> 9100000)
 + (SELECT COUNT(*) FROM `smart_scripts` WHERE `entryorguid` BETWEEN 9100000 AND 9100099 AND `source_type` = 0 AND `comment` NOT LIKE 'Porter - %')
 = 0, 'ok: 9100000-9100099 is free or holds only these NPCs', (SELECT 1 UNION SELECT 2)) AS check_id_range;

-- 3. Item data -----------------------------------------------------------

SELECT IF(
  (SELECT COUNT(*) FROM `item_template` WHERE `itemset` IN (621, 624, 625, 626, 631, 632, 633, 638, 639, 640, 645, 648, 651, 654, 655, 663, 664)) = 85
  AND (SELECT COUNT(*) FROM `item_template` WHERE `itemset` IN (622, 627, 628, 629, 634, 635, 636, 641, 642, 643, 646, 649, 652, 656, 657, 665, 666)) = 85
  AND (SELECT COUNT(*) FROM `item_template` WHERE `itemset` BETWEEN 668 AND 684) = 136,
  'ok: tier pieces 85 / 85 / 136', (SELECT 1 UNION SELECT 2)) AS check_tier_items;

SELECT IF((SELECT COUNT(*) FROM `item_template` WHERE `entry` IN (
  28767, 39769, 28773, 28794, 28772, 28522, 28657, 28771, 28800, 28774,
  28729, 28749, 28802, 28604, 28633, 28658, 28782, 28524, 28768, 28770,
  28659, 28826, 28673, 28783, 28525, 28603, 28728, 28734, 28781, 28606,
  28611, 28754, 28825, 29458, 28568, 28523, 29924, 30105, 29949, 29996,
  30108, 30090, 30082, 30095, 29993, 29981, 30021, 29988, 29948, 32944,
  29962, 30103, 30025, 29982, 30080, 29923, 30049, 30051, 30023, 32236,
  32254, 32348, 30906, 32336, 32325, 32262, 32943, 34009, 32500, 32248,
  32369, 30910, 32837, 32838, 30902, 32344, 30908, 32374, 32945, 32946,
  32237, 32269, 32471, 32326, 32253, 32343, 32361, 30911, 32255, 34011,
  30909, 32375, 32368, 32257, 32330)) = 95,
  'ok: all 95 weapons present', (SELECT 1 UNION SELECT 2)) AS check_weapon_items;

DROP TEMPORARY TABLE hprv_req;
SELECT 'precheck passed' AS result;
