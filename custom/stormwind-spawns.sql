-- HPRV — Porter and vendors in Stormwind (optional, for Alliance players)
--
-- A second spawn of each of the five NPCs, in Stormwind's Trade
-- District. The creatures themselves (templates, gossip, SmartAI, stock
-- lists) come from teleporter-npc.sql, tier-vendors.sql and
-- weapon-vendor.sql, so apply those first. This file adds spawns only.
-- All five are faction 35, so either faction can use either city's
-- spawns. This file saves Alliance players the walk to Orgrimmar.
--
-- ---------------------------------------------------------------------
-- IDS
--
-- Spawn guid = entry + 10: 9100010 (Porter) to 9100014 (weapons). That's
-- inside the project's 9100000-9100099 range. The base files leave spawns
-- in that range alone, so re-running either set never removes the other.
--
-- PLACEMENT (2026-09-26)
--
-- A row of five, 2.3 yd apart, running west to east at y 625.6, 3 yd
-- south of where `.tele Stormwind` lands. All five face north, toward
-- the arrival point. The Porter is at the west end. HPRV is all Horde,
-- so these were placed by measurement, not by eye:
--   * Each z is read from the server's navmesh (mmaps/0004830.mmtile)
--     and corrected by -0.22. That is the median offset of 151
--     stationary stock NPCs in the district.
--   * Across each 1.2 x 1.2 yd footprint, the ground varies by at most
--     0.17 yd.
--   * No stock creature or permanent gameobject is within 7.6 yd.
--   * Cross-check: the navmesh puts the `.tele Stormwind` point 0.13 yd
--     from its stock z.
-- Check them once in game (`.gm on`, `.tele Stormwind`). To adjust one,
-- `.npc move` it and copy the new position back here.
--
-- Needs a worldserver restart: spawn rows are read at startup.
-- Idempotent.
-- ---------------------------------------------------------------------

DELETE FROM `creature` WHERE `guid` BETWEEN 9100010 AND 9100014;

INSERT INTO `creature`
  (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
   `position_x`, `position_y`, `position_z`, `orientation`,
   `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`,
   `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `CreateObject`, `Comment`)
VALUES
  (9100010, 9100000, 0, 0, 0, 1, 1, 0, -8838.0, 625.6, 94.03, 1.5708, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV Porter - Stormwind'),
  (9100014, 9100004, 0, 0, 0, 1, 1, 0, -8835.7, 625.6, 94.10, 1.5708, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV weapon vendor - Stormwind'),
  (9100011, 9100001, 0, 0, 0, 1, 1, 0, -8833.4, 625.6, 94.02, 1.5708, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV Tier 4 vendor - Stormwind'),
  (9100012, 9100002, 0, 0, 0, 1, 1, 0, -8831.1, 625.6, 93.98, 1.5708, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV Tier 5 vendor - Stormwind'),
  (9100013, 9100003, 0, 0, 0, 1, 1, 0, -8828.8, 625.6, 93.96, 1.5708, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV Tier 6 vendor - Stormwind');
