-- HPRV — Highlord Kruul, a 25-man world boss test in Shadowmoon Valley (SQL only)
--
--   mysql acore_world < world-boss-kruul.sql      # then restart the worldserver
--   .event start 240                              # in game, GM account
--
-- Kruul was the demon lord who roamed Azeroth before TBC. The world DB
-- already has him (18338: level 63, unscripted, never spawned). This file
-- leaves that row alone and builds our own Kruul from Doom Lord Kazzak's
-- row, so he inherits a level-73 world boss's immunities and flags, with
-- the stock Kruul model on top.
--
-- ---------------------------------------------------------------------
-- THE FIGHT (all SmartAI, no C++)
--
--   HP        ~1.2M (HealthModifier 158 x 7,588 base at level 73). For a
--             6-7 minute fight from the tier-4 25. Kazzak is 0.85M,
--             Doomwalker 1.59M.
--   Damage    DamageModifier 40. Kazzak is 65; this is a softer first
--             test for Bullwark. Raise it once we've seen a kill.
--   Shadow Volley   32963  every 10-14 s   raid-wide, healer pressure
--   Cleave          31779  every 8-12 s    frontal; face him away
--   Thunderclap     36706  every 18-24 s   melee pressure
--   Hounds          3 x Hound of Kruul every 60 s from 45 s, each one
--                   dropped on a random raider and attacking them.
--                   Tests whether DPS bots peel adds off healers with
--                   no bot tank (CLAUDE.md rule 1)
--   Frenzy          32964  below 20 %, every 30 s
--   Berserk         32965  at 10 minutes
--   Loot            10 Badges of Justice + 2 epics from Kazzak's table
--
-- THE EVENT
--
-- game_event 240 owns the spawn, so Kruul is only in the world while the
-- event runs. It never starts on its own: the stored window opens in
-- 2037. `.event start 240` moves its start to now, and it runs 90
-- minutes, then despawns him, mid-fight or not. `announce = 1` puts the
-- start in everyone's chat. `.event stop 240` ends it early.
--
-- Respawn is 90 minutes too, so a dead Kruul doesn't come back inside the
-- same event. The respawn timer is saved, so the next `.event start`
-- within 90 minutes of a kill brings an event with no Kruul in it.
--
-- WHERE
--
-- Shadowmoon Valley, the felboar plains between Deathforge and Legion
-- Hold: (-3557.3, 2074.0, 71.3), a felboar spawn point, so the ground is
-- real. Two felboars within 60 yd, no camps. Doomwalker is ~1,800 yd
-- south. To move him: stand there, `.npc move` on him, and copy the new
-- position back into this file.
--
-- IDS
--
--   creature_template   9100020 Kruul, 9100021 Hound of Kruul
--   creature (spawn)    9100020
--   game_event          240 (game_event IDs are a tinyint, so they can't
--                       use 9100000+; 240-249 is ours, docs/custom-npcs.md)
--   creature_text, smart_scripts, creature_loot_template: the entries above
--
-- Idempotent: every DELETE is scoped to these IDs. Remove it all with
-- world-boss-kruul-uninstall.sql.
--
-- RESTART
--
-- New creatures and game events are read at startup only. After the
-- first install, a SmartAI change reaches Kruul the next time he spawns
-- (`.reload smart_scripts`, then `.event stop 240` and `.event start
-- 240`), not mid-event.
-- ---------------------------------------------------------------------

SET @KRUUL  := 9100020;
SET @HOUND  := 9100021;
SET @GUID   := 9100020;
SET @EVENT  := 240;

SET @KAZZAK        := 18728;  -- stat source for Kruul
SET @STOCK_KRUUL   := 18338;  -- model source
SET @FELHOUND      := 18605;  -- Felhound Manastalker, level 70: the hounds

-- ---------------------------------------------------------------------
-- The creatures. Cloned row-for-row so every column, renamed or not,
-- comes across; then only what differs is changed.
-- ---------------------------------------------------------------------

DELETE FROM `creature_template`       WHERE `entry`      IN (@KRUUL, @HOUND);
DELETE FROM `creature_template_model` WHERE `CreatureID` IN (@KRUUL, @HOUND);

DROP TEMPORARY TABLE IF EXISTS hprv_ct;
CREATE TEMPORARY TABLE hprv_ct AS SELECT * FROM `creature_template` WHERE `entry` IN (@KAZZAK, @FELHOUND);

UPDATE hprv_ct SET
  `entry` = @KRUUL, `name` = 'Highlord Kruul', `subname` = NULL,
  `AIName` = 'SmartAI', `ScriptName` = '',
  `HealthModifier` = 158, `DamageModifier` = 40,
  `lootid` = @KRUUL
WHERE `entry` = @KAZZAK;

-- Elite, ~15k HP (2.15 x 6,986 base at 70). No AI script: they bite.
UPDATE hprv_ct SET
  `entry` = @HOUND, `name` = 'Hound of Kruul', `subname` = NULL,
  `rank` = 1, `unit_class` = 1,
  `AIName` = '', `ScriptName` = '',
  `HealthModifier` = 2.15,
  `lootid` = 0
WHERE `entry` = @FELHOUND;

INSERT INTO `creature_template` SELECT * FROM hprv_ct;
DROP TEMPORARY TABLE hprv_ct;

INSERT INTO `creature_template_model`
  (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`)
SELECT @KRUUL, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, 0
  FROM `creature_template_model` WHERE `CreatureID` = @STOCK_KRUUL
UNION ALL
SELECT @HOUND, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, 0
  FROM `creature_template_model` WHERE `CreatureID` = @FELHOUND;

-- ---------------------------------------------------------------------
-- What he says. Type 14 = yell, 41 = raid boss emote. TextRange 2 = zone.
-- ---------------------------------------------------------------------

DELETE FROM `creature_text` WHERE `CreatureID` = @KRUUL;

INSERT INTO `creature_text`
  (`CreatureID`, `GroupID`, `ID`, `Text`, `Type`, `Language`, `Probability`, `Emote`, `Duration`, `Sound`, `BroadcastTextId`, `TextRange`, `comment`)
VALUES
  (@KRUUL, 0, 0, 'Shadowmoon burns, and you came to warm your hands? Kneel, mortals!', 14, 0, 100, 0, 0, 0, 0, 2, 'Highlord Kruul - aggro'),
  (@KRUUL, 1, 0, '%s calls the Hounds of Kruul!',                                       41, 0, 100, 0, 0, 0, 0, 2, 'Highlord Kruul - hounds'),
  (@KRUUL, 2, 0, 'Enough! I will tear this valley apart!',                              14, 0, 100, 0, 0, 0, 0, 2, 'Highlord Kruul - frenzy at 20%'),
  (@KRUUL, 3, 0, 'Another soul for the Legion.',                                        14, 0, 100, 0, 0, 0, 0, 2, 'Highlord Kruul - kill'),
  (@KRUUL, 4, 0, 'This... is not... the end. The Legion... is endless...',              14, 0, 100, 0, 0, 0, 0, 2, 'Highlord Kruul - death'),
  (@KRUUL, 5, 0, 'You have wasted my time. Now you will waste away!',                   14, 0, 100, 0, 0, 0, 0, 2, 'Highlord Kruul - berserk');

-- ---------------------------------------------------------------------
-- SmartAI. Event types: 0 in-combat timer (initial min/max, repeat
-- min/max), 2 health %, 4 aggro, 5 kill, 6 death. Actions: 1 talk,
-- 11 cast, 12 summon. Targets: 1 self, 2 victim, 5 random hostile
-- (max distance, players only). event_flags 1 = once.
--
-- The four hound rows share one fixed timer so the pack and the emote
-- arrive together. Summon type 4 = despawn 15 s after leaving combat,
-- which also clears corpses. attackInvoker 1 = attack the raider it was
-- dropped on.
-- ---------------------------------------------------------------------

DELETE FROM `smart_scripts` WHERE `entryorguid` IN (@KRUUL, @HOUND) AND `source_type` = 0;

INSERT INTO `smart_scripts`
  (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
   `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`,
   `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
   `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`,
   `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
  (@KRUUL, 0,  0, 0, 4, 0, 100, 0,       0,      0,      0,      0, 0, 0,  1,     0,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - on aggro - yell'),
  (@KRUUL, 0,  1, 0, 0, 0, 100, 0,    8000,  12000,  10000,  14000, 0, 0, 11, 32963,     0, 0, 0, 0, 0,  2,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - IC - Shadow Volley'),
  (@KRUUL, 0,  2, 0, 0, 0, 100, 0,    7000,   7000,   8000,  12000, 0, 0, 11, 31779,     0, 0, 0, 0, 0,  2,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - IC - Cleave'),
  (@KRUUL, 0,  3, 0, 0, 0, 100, 0,   15000,  18000,  18000,  24000, 0, 0, 11, 36706,     0, 0, 0, 0, 0,  2,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - IC - Thunderclap'),
  (@KRUUL, 0,  4, 0, 0, 0, 100, 0,   45000,  45000,  60000,  60000, 0, 0, 12, @HOUND,    4, 15000, 1, 0, 0,  5, 80, 1, 0, 0,  0, 0, 0, 0, 'Kruul - IC - hound on a random raider'),
  (@KRUUL, 0,  5, 0, 0, 0, 100, 0,   45000,  45000,  60000,  60000, 0, 0, 12, @HOUND,    4, 15000, 1, 0, 0,  5, 80, 1, 0, 0,  0, 0, 0, 0, 'Kruul - IC - hound on a random raider'),
  (@KRUUL, 0,  6, 0, 0, 0, 100, 0,   45000,  45000,  60000,  60000, 0, 0, 12, @HOUND,    4, 15000, 1, 0, 0,  5, 80, 1, 0, 0,  0, 0, 0, 0, 'Kruul - IC - hound on a random raider'),
  (@KRUUL, 0,  7, 0, 0, 0, 100, 0,   45000,  45000,  60000,  60000, 0, 0,  1,     1,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - IC - hounds emote'),
  (@KRUUL, 0,  8, 0, 2, 0, 100, 0,       0,     20,  30000,  30000, 0, 0, 11, 32964,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - below 20% - Frenzy, every 30 s'),
  (@KRUUL, 0,  9, 0, 2, 0, 100, 1,       0,     20,      0,      0, 0, 0,  1,     2,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - below 20% - yell, once'),
  (@KRUUL, 0, 10, 0, 0, 0, 100, 1,  600000, 600000,      0,      0, 0, 0, 11, 32965,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - 10 min - Berserk'),
  (@KRUUL, 0, 11, 0, 0, 0, 100, 1,  600000, 600000,      0,      0, 0, 0,  1,     5,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - 10 min - berserk yell'),
  (@KRUUL, 0, 12, 0, 5, 0, 100, 0,    5000,  10000,      1,      0, 0, 0,  1,     3,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - killed a player - yell'),
  (@KRUUL, 0, 13, 0, 6, 0, 100, 0,       0,      0,      0,      0, 0, 0,  1,     4,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Kruul - on death - yell');

-- ---------------------------------------------------------------------
-- Loot. Badges are one stack to whoever wins it; the bots roll need on
-- upgrades and greed on the rest.
-- ---------------------------------------------------------------------

DELETE FROM `creature_loot_template` WHERE `Entry` = @KRUUL;

INSERT INTO `creature_loot_template`
  (`Entry`, `Item`, `Reference`, `Chance`, `QuestRequired`, `LootMode`, `GroupId`, `MinCount`, `MaxCount`, `Comment`)
VALUES
  (@KRUUL, 29434,     0, 100, 0, 1, 0, 10, 10, 'Highlord Kruul (HPRV) - Badge of Justice x10'),
  (@KRUUL,     1, 26043, 100, 0, 1, 0,  2,  2, 'Highlord Kruul (HPRV) - 2 from Doom Lord Kazzak''s reference table');

-- ---------------------------------------------------------------------
-- The spawn, and the event that owns it.
-- ---------------------------------------------------------------------

DELETE FROM `game_event_creature` WHERE `eventEntry` = @EVENT OR `guid` = @GUID;
DELETE FROM `creature` WHERE `guid` = @GUID OR `id` IN (@KRUUL, @HOUND);

INSERT INTO `creature`
  (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
   `position_x`, `position_y`, `position_z`, `orientation`,
   `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`,
   `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `CreateObject`, `Comment`)
VALUES
  (@GUID, @KRUUL, 530, 0, 0, 1, 1, 0, -3557.3, 2074.0, 71.3, 0, 5400, 0, 0, 1198904, 0, 0, 0, 0, 0, '', 0,
   'HPRV world boss - Highlord Kruul, Shadowmoon (game_event 240)');

DELETE FROM `game_event` WHERE `eventEntry` = @EVENT;

INSERT INTO `game_event`
  (`eventEntry`, `start_time`, `end_time`, `occurence`, `length`, `holiday`, `holidayStage`, `description`, `world_event`, `announce`)
VALUES
  (@EVENT, '2037-01-01 00:00:00', '2037-12-31 00:00:00', 5184000, 90, 0, 0,
   'Highlord Kruul has come to Shadowmoon Valley', 0, 1);

INSERT INTO `game_event_creature` (`eventEntry`, `guid`) VALUES (@EVENT, @GUID);

SELECT 'Highlord Kruul installed; restart the worldserver, then .event start 240' AS result;
