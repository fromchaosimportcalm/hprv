-- HPRV NPCs — remove everything the install files added
--
--   mysql <world_db> < uninstall.sql
--
-- Deletes every row in 9100000-9100099 from the tables the install
-- touches, so all five NPCs go, with their gossip, SmartAI, stock
-- lists and every spawn in both cities. Nothing outside that range is
-- touched.
--
-- If you applied weapon-vendor-free-prices.sql, also run
-- weapon-vendor-revert-prices.sql. That is the only stock change, and
-- this file does not undo it.
--
-- Needs a worldserver restart to clear NPCs that are already spawned.
-- ---------------------------------------------------------------------

DELETE FROM `creature`                WHERE `guid`        BETWEEN 9100000 AND 9100099;
DELETE FROM `creature`                WHERE `id`          BETWEEN 9100000 AND 9100099;
DELETE FROM `smart_scripts`           WHERE `entryorguid` BETWEEN 9100000 AND 9100099 AND `source_type` = 0;
DELETE FROM `npc_vendor`              WHERE `entry`       BETWEEN 9100000 AND 9100099;
DELETE FROM `gossip_menu_option`      WHERE `MenuID`      BETWEEN 9100000 AND 9100099;
DELETE FROM `gossip_menu`             WHERE `MenuID`      BETWEEN 9100000 AND 9100099;
DELETE FROM `npc_text`                WHERE `ID`          BETWEEN 9100000 AND 9100099;
DELETE FROM `creature_template_model` WHERE `CreatureID`  BETWEEN 9100000 AND 9100099;
DELETE FROM `creature_template`       WHERE `entry`       BETWEEN 9100000 AND 9100099;

SELECT 'removed; restart the worldserver' AS result;
