-- HPRV — raid teleporter NPC (SQL-only proof of concept)
--
-- A gossip NPC in Orgrimmar that teleports the talker AND their whole
-- party/raid to the BC raid entrances. No C++, no rebuild: the behaviour
-- is SmartAI rows in smart_scripts.
--
-- ---------------------------------------------------------------------
-- ID RANGE
--
-- Everything custom lives in 9100000-9100099, in every table it touches
-- (creature_template, gossip_menu, npc_text, smart_scripts, creature).
-- Checked
-- empty on the box 2026-09-25; the highest stock creature entry is
-- 3,460,603. The DELETEs below are scoped to that range, so re-running
-- this file only ever replaces its own rows — idempotent, per project
-- convention.
--
-- ---------------------------------------------------------------------
-- WHAT NEEDS A RESTART AND WHAT DOES NOT (measured at the current pin)
--
-- First apply: ONE worldserver restart (~6 min). `.reload
-- creature_template` only refreshes entries already in memory, so a new
-- entry, its model and its npc_text are only picked up at startup.
--
-- After that:
--   gossip_menu_option  ->  .reload gossip_menu_option. Live: the menu
--                          is read on every click.
--   smart_scripts       ->  .reload smart_scripts is NOT enough on its
--                          own. It refreshes the stored copy, but each
--                          spawned NPC copied its script when it spawned
--                          and keeps that copy (SmartScript::GetScript
--                          runs at AI init). Found 2026-09-25: after the
--                          reload she still teleported only the clicker.
--                          The live NPC has to respawn — a restart, or
--                          `.npc delete` her and let the restart bring
--                          back the guid-9100000 spawn below.
-- So a new destination's menu entry appears at once, but its teleport
-- only works once she respawns.
--
-- ---------------------------------------------------------------------
-- SPAWN
--
-- One spawn, in Orgrimmar's Valley of Strength (bottom section). It was
-- placed in game with `.npc add 9100000` and copied back here. To move
-- her: `.npc move` in game, then copy the new position into this file,
-- or re-run it and she snaps back here at the next restart.
-- ---------------------------------------------------------------------

SET @ENTRY := 9100000;
SET @MENU  := 9100000;
SET @TEXT  := 9100000;

-- ---------------------------------------------------------------------
-- The creature. Faction 35 = friendly to everyone, bots included.
-- npcflag 1 = gossip. unit_flags 2 = non-attackable. Model is Zephyr's
-- (25967), the Shattrath bronze dragon who already runs a teleport.
-- ---------------------------------------------------------------------

DELETE FROM `acore_world`.`creature_template`       WHERE `entry`      = @ENTRY;
DELETE FROM `acore_world`.`creature_template_model` WHERE `CreatureID` = @ENTRY;

INSERT INTO `acore_world`.`creature_template`
  (`entry`, `name`, `subname`, `gossip_menu_id`, `minlevel`, `maxlevel`, `exp`,
   `faction`, `npcflag`, `unit_class`, `unit_flags`, `type`,
   `AIName`, `HealthModifier`, `VerifiedBuild`)
VALUES
  (@ENTRY, 'Porter Nozdrel', 'Raid Teleports', @MENU, 80, 80, 2,
   35, 1, 1, 2, 7,
   'SmartAI', 1, 0);

INSERT INTO `acore_world`.`creature_template_model`
  (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`)
VALUES
  (@ENTRY, 0, 19282, 1, 1, 0);

-- ---------------------------------------------------------------------
-- Gossip: greeting text + one option per destination.
-- OptionIcon 2 = taxi icon. OptionType 1 = plain gossip (SmartAI handles
-- the click via SMART_EVENT_GOSSIP_SELECT).
-- ---------------------------------------------------------------------

DELETE FROM `acore_world`.`npc_text`           WHERE `ID`     = @TEXT;
DELETE FROM `acore_world`.`gossip_menu`        WHERE `MenuID` = @MENU;
DELETE FROM `acore_world`.`gossip_menu_option` WHERE `MenuID` = @MENU;

INSERT INTO `acore_world`.`npc_text` (`ID`, `text0_0`, `Probability0`, `VerifiedBuild`)
VALUES (@TEXT, 'Where to, $n? Try to bring all nine of them back this time.', 1, 0);

INSERT INTO `acore_world`.`gossip_menu` (`MenuID`, `TextID`) VALUES (@MENU, @TEXT);

INSERT INTO `acore_world`.`gossip_menu_option`
  (`MenuID`, `OptionID`, `OptionIcon`, `OptionText`, `OptionBroadcastTextID`,
   `OptionType`, `OptionNpcFlag`, `ActionMenuID`, `ActionPoiID`,
   `BoxCoded`, `BoxMoney`, `BoxText`, `BoxBroadcastTextID`, `VerifiedBuild`)
VALUES
  (@MENU, 0, 2, 'Shattrath City',       0, 1, 1, 0, 0, 0, 0, '', 0, 0),
  (@MENU, 1, 2, 'Karazhan',             0, 1, 1, 0, 0, 0, 0, '', 0, 0),
  (@MENU, 2, 2, 'Zul''Aman',            0, 1, 1, 0, 0, 0, 0, '', 0, 0),
  (@MENU, 3, 2, 'Gruul''s Lair',        0, 1, 1, 0, 0, 0, 0, '', 0, 0),
  (@MENU, 4, 2, 'Magtheridon''s Lair',  0, 1, 1, 0, 0, 0, 0, '', 0, 0),
  (@MENU, 5, 2, 'Black Temple',         0, 1, 1, 0, 0, 0, 0, '', 0, 0);

-- ---------------------------------------------------------------------
-- SmartAI. Each option is a linked pair:
--   id 2n    event 62 GOSSIP_SELECT (menu, option n) -> action 72 CLOSE_GOSSIP, link 2n+1
--   id 2n+1  event 61 LINK                            -> action 62 TELEPORT (param1 = map)
-- Close-gossip targets 7 (the clicker). Teleport targets 16
-- (INVOKER_PARTY): every member of the clicker's party or raid who is
-- on the same map, at any distance -- bots included, since they are
-- real Players. Anyone on another map is left behind; with no group it
-- falls back to just the clicker. The destination lives in
-- target_x/y/z/o. Coordinates are the stock `game_tele` rows (.tele
-- names in the comments), read off the box 2026-09-25.
-- ---------------------------------------------------------------------

DELETE FROM `acore_world`.`smart_scripts` WHERE `entryorguid` = @ENTRY AND `source_type` = 0;

INSERT INTO `acore_world`.`smart_scripts`
  (`entryorguid`, `source_type`, `id`, `link`,
   `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
   `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`,
   `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
   `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`,
   `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
  -- 0: Shattrath (.tele Shattrath)
  (@ENTRY, 0,  0,  1, 62, 0, 100, 0, @MENU, 0, 0, 0, 0, 0, 72,   0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0,     0,        0,        0,       0,       'Porter - Gossip 0 - Close Gossip'),
  (@ENTRY, 0,  1,  0, 61, 0, 100, 0, 0,     0, 0, 0, 0, 0, 62, 530, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, -1838.16,  5301.79,  -12.428,  5.9517,  'Porter - Linked - Teleport Shattrath'),
  -- 1: Karazhan (.tele Karazhan)
  (@ENTRY, 0,  2,  3, 62, 0, 100, 0, @MENU, 1, 0, 0, 0, 0, 72,   0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0,     0,        0,        0,       0,       'Porter - Gossip 1 - Close Gossip'),
  (@ENTRY, 0,  3,  0, 61, 0, 100, 0, 0,     0, 0, 0, 0, 0, 62,   0, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, -11118.9, -2010.33,   47.0819, 0.649895, 'Porter - Linked - Teleport Karazhan'),
  -- 2: Zul'Aman (.tele ZulAman)
  (@ENTRY, 0,  4,  5, 62, 0, 100, 0, @MENU, 2, 0, 0, 0, 0, 72,   0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0,     0,        0,        0,       0,       'Porter - Gossip 2 - Close Gossip'),
  (@ENTRY, 0,  5,  0, 61, 0, 100, 0, 0,     0, 0, 0, 0, 0, 62, 530, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0,  6851.78, -7972.57,  179.242,  4.64691, 'Porter - Linked - Teleport Zul''Aman'),
  -- 3: Gruul's Lair (.tele GruulsLair)
  (@ENTRY, 0,  6,  7, 62, 0, 100, 0, @MENU, 3, 0, 0, 0, 0, 72,   0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0,     0,        0,        0,       0,       'Porter - Gossip 3 - Close Gossip'),
  (@ENTRY, 0,  7,  0, 61, 0, 100, 0, 0,     0, 0, 0, 0, 0, 62, 530, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0,  3530.06,  5104.08,    3.50861, 5.51117, 'Porter - Linked - Teleport Gruul''s Lair'),
  -- 4: Magtheridon's Lair (.tele MagtheridonsLair)
  (@ENTRY, 0,  8,  9, 62, 0, 100, 0, @MENU, 4, 0, 0, 0, 0, 72,   0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0,     0,        0,        0,       0,       'Porter - Gossip 4 - Close Gossip'),
  (@ENTRY, 0,  9,  0, 61, 0, 100, 0, 0,     0, 0, 0, 0, 0, 62, 530, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0,  -312.7,    3087.26, -116.52,   5.19026, 'Porter - Linked - Teleport Magtheridon''s Lair'),
  -- 5: Black Temple (.tele BlackTemple)
  (@ENTRY, 0, 10, 11, 62, 0, 100, 0, @MENU, 5, 0, 0, 0, 0, 72,   0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0,     0,        0,        0,       0,       'Porter - Gossip 5 - Close Gossip'),
  (@ENTRY, 0, 11,  0, 61, 0, 100, 0, 0,     0, 0, 0, 0, 0, 62, 530, 0, 0, 0, 0, 0, 16, 0, 0, 0, 0, -3649.92,   317.469,  35.2827, 2.94285, 'Porter - Linked - Teleport Black Temple');

-- ---------------------------------------------------------------------
-- SPAWN — Orgrimmar, Valley of Strength (map 1)
--
-- Position is from the in-game `.npc add` on 2026-09-25. That wrote
-- guid 5300681, which sits in the stock guid space; this file re-homes
-- her to guid 9100000 so a future world-DB update can never collide.
-- The DELETE is by creature id, so re-running always converges on
-- exactly this one spawn, wherever else she has been placed. Spawn
-- rows are only read at startup: the new guid takes over on the next
-- restart, and the live NPC is unaffected until then.
-- ---------------------------------------------------------------------

SET @GUID := 9100000;

DELETE FROM `acore_world`.`creature` WHERE `id` = @ENTRY OR `guid` = @GUID;

INSERT INTO `acore_world`.`creature`
  (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
   `position_x`, `position_y`, `position_z`, `orientation`,
   `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`,
   `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `CreateObject`, `Comment`)
VALUES
  (@GUID, @ENTRY, 1, 0, 0, 1, 1, 0,
   1637.41, -4404.22, 16.6179, 3.06538,
   300, 0, 0, 12600, 0,
   0, 0, 0, 0, '', 0, 'HPRV Porter - Orgrimmar');
