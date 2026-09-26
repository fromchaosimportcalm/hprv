-- HPRV — Tier 4 / 5 / 6 vendors (SQL only)
--
-- Three vendor NPCs beside Porter Nozdrel in Orgrimmar, one per tier,
-- each selling every class's set pieces for that tier at no cost.
--
-- ---------------------------------------------------------------------
-- WHY THREE NPCS, NOT ONE
--
-- The 3.3.5 vendor window holds at most 150 items (MAX_VENDOR_ITEMS in
-- Creature.h; the rest are silently dropped). The tiers are 85 + 85 +
-- 136 = 306 pieces, so one NPC per tier is the smallest split that
-- fits, and it keeps each list browsable.
--
-- WHY IT IS FREE WITHOUT TOUCHING PRICES
--
-- A vendor charges item_template.BuyPrice (plus ExtendedCost, 0 here).
-- Every tier piece below already has BuyPrice = 0 in the stock DB —
-- they were only ever obtained from tokens. So nothing global is
-- modified: this file only adds rows in its own ID range.
--
-- WHICH ITEMS
--
-- Selected by item set ID, read off item_template on 2026-09-25. Each
-- tier is exactly 17 sets (every class/spec variant, both factions —
-- AllowableRace is all-races on all 306). Classes that cannot wear a
-- piece see it red in the window, as with any vendor.
--   T4  Karazhan / Gruul / Mag      ilvl 120, 5 pieces per set
--   T5  SSC / Tempest Keep          ilvl 133, 5 pieces per set
--   T6  Hyjal / Black Temple        ilvl 146, 5 pieces per set
--       + Sunwell bracers/belt/boots ilvl 154, 3 pieces per set
--
-- IDS / RESTART
--
-- Entries 9100001-9100003, spawn guids 9100001-9100003 (the project's
-- 9100000-9100099 range; 9100000 is the Porter). New entries need one
-- worldserver restart. After that, changing what a vendor sells is
-- live: re-run this file, then `.reload npc_vendor`.
-- Idempotent: every DELETE is scoped to these entries/guids.
-- ---------------------------------------------------------------------

SET @T4 := 9100001;
SET @T5 := 9100002;
SET @T6 := 9100003;

-- ---------------------------------------------------------------------
-- The NPCs. npcflag 128 = vendor. Faction 35, non-attackable, as the
-- Porter. Models borrowed from the Shattrath quartermasters.
-- ---------------------------------------------------------------------

DELETE FROM `acore_world`.`creature_template`       WHERE `entry`      IN (@T4, @T5, @T6);
DELETE FROM `acore_world`.`creature_template_model` WHERE `CreatureID` IN (@T4, @T5, @T6);

INSERT INTO `acore_world`.`creature_template`
  (`entry`, `name`, `subname`, `minlevel`, `maxlevel`, `exp`,
   `faction`, `npcflag`, `unit_class`, `unit_flags`, `type`, `HealthModifier`, `VerifiedBuild`)
VALUES
  (@T4, 'Almari Stonebrand', 'Tier 4 Armor',  80, 80, 2, 35, 128, 1, 2, 7, 1, 0),
  (@T5, 'Veshan Coilhand',   'Tier 5 Armor',  80, 80, 2, 35, 128, 1, 2, 7, 1, 0),
  (@T6, 'Oriel Duskmantle',  'Tier 6 Armor',  80, 80, 2, 35, 128, 1, 2, 7, 1, 0);

INSERT INTO `acore_world`.`creature_template_model`
  (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`)
VALUES
  (@T4, 0, 20290, 1, 1, 0),   -- Almaador, Sha'tari Quartermaster
  (@T5, 0, 18735, 1, 1, 0),   -- Quartermaster Endarin (Aldor)
  (@T6, 0, 18769, 1, 1, 0);   -- Quartermaster Enuril (Scryer)

-- ---------------------------------------------------------------------
-- Stock lists. slot orders the window: by set, then by body slot, so
-- each class's pieces sit together.
-- ---------------------------------------------------------------------

DELETE FROM `acore_world`.`npc_vendor` WHERE `entry` IN (@T4, @T5, @T6);

INSERT INTO `acore_world`.`npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`, `VerifiedBuild`)
SELECT @T4, ROW_NUMBER() OVER (ORDER BY `itemset`, `InventoryType`, `entry`), `entry`, 0, 0, 0, 0
  FROM `acore_world`.`item_template`
 WHERE `itemset` IN (621, 624, 625, 626, 631, 632, 633, 638, 639, 640, 645, 648, 651, 654, 655, 663, 664);

INSERT INTO `acore_world`.`npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`, `VerifiedBuild`)
SELECT @T5, ROW_NUMBER() OVER (ORDER BY `itemset`, `InventoryType`, `entry`), `entry`, 0, 0, 0, 0
  FROM `acore_world`.`item_template`
 WHERE `itemset` IN (622, 627, 628, 629, 634, 635, 636, 641, 642, 643, 646, 649, 652, 656, 657, 665, 666);

INSERT INTO `acore_world`.`npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`, `VerifiedBuild`)
SELECT @T6, ROW_NUMBER() OVER (ORDER BY `itemset`, `ItemLevel`, `InventoryType`, `entry`), `entry`, 0, 0, 0, 0
  FROM `acore_world`.`item_template`
 WHERE `itemset` BETWEEN 668 AND 684;

-- ---------------------------------------------------------------------
-- SPAWNS — Orgrimmar, Valley of Strength: a row on the flat ground just
-- south-west of the Porter (1637.4, -4404.2), facing the same way she
-- does. Torvek (weapon-vendor.sql) heads the row.
--
-- Moved 2026-09-26. The first row, at x 1632.3, ran down a ramp with one
-- shared z, so Torvek floated about a yard and Oriel stood sunk. Each z
-- here is its own ground height, read from the navmesh
-- (mmaps/0012840.mmtile) and corrected by -0.37, the median offset of 45
-- stationary stock NPCs nearby. If one still looks off, `.npc move` it
-- and copy the new position back here.
-- ---------------------------------------------------------------------

DELETE FROM `acore_world`.`creature` WHERE `id` IN (@T4, @T5, @T6) OR `guid` IN (@T4, @T5, @T6);

INSERT INTO `acore_world`.`creature`
  (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
   `position_x`, `position_y`, `position_z`, `orientation`,
   `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`,
   `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `CreateObject`, `Comment`)
VALUES
  (@T4, @T4, 1, 0, 0, 1, 1, 0, 1634.5, -4408.8, 16.56, 3.06538, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV Tier 4 vendor - Orgrimmar'),
  (@T5, @T5, 1, 0, 0, 1, 1, 0, 1634.5, -4411.1, 16.85, 3.06538, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV Tier 5 vendor - Orgrimmar'),
  (@T6, @T6, 1, 0, 0, 1, 1, 0, 1634.5, -4413.4, 16.75, 3.06538, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV Tier 6 vendor - Orgrimmar');
