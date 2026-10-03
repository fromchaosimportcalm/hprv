-- HPRV — transmogrifier spawn (needs mod-transmog)
--
-- Spawns mod-transmog's "Warpweaver" with the other custom NPCs
-- in the Bank of Orgrimmar (orgrimmar-bank.sql), so Bullwark can wear Thunderfury's
-- look on King's Defender (TODO item 8).
--
-- ---------------------------------------------------------------------
-- IDS
--
-- The NPC itself is the module's: entry 190010, created by the module's
-- own SQL (data/sql/db-world/trasm_world_NPC.sql), which worldserver
-- applies at startup. It is outside our 9100000 range on purpose:
-- renumbering it would mean patching the module's SQL on every pin bump.
-- Only the spawn is ours, at guid 9100005, the next free Orgrimmar slot.
--
-- NOT PACKAGED. This needs the C++ module, so scripts/package-npcs.sh
-- leaves it out, the same as Kruul. Apply it only after the module's SQL
-- has run (the INSERT ... SELECT below adds nothing if entry 190010 is
-- missing), then restart: a new spawn appears only after a restart.
--
-- POSITION
--
-- In the Bank of Orgrimmar, between Torvek and the Porter, on the line
-- orgrimmar-bank.sql lays out (which also sets this same position).
-- ---------------------------------------------------------------------

SET @NPC   := 190010;
SET @GUID  := 9100005;

DELETE FROM `creature` WHERE `guid` = @GUID OR (`id` = @NPC AND `guid` NOT BETWEEN 9100000 AND 9100099);

INSERT INTO `creature`
  (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
   `position_x`, `position_y`, `position_z`, `orientation`,
   `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`,
   `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `CreateObject`, `Comment`)
SELECT @GUID, @NPC, 1, 0, 0, 1, 1, 0, 1631.03, -4380.11, 12.05, 3.578, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV transmogrifier - Orgrimmar'
  FROM `creature_template` WHERE `entry` = @NPC;
