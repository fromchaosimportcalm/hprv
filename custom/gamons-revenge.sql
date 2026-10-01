-- HPRV — Gamon's Revenge (SQL only)
--
--   mysql acore_world < gamons-revenge.sql      # then restart the worldserver
--
-- Gamon is the level-12 orc in Orgrimmar whom everyone has killed. Now,
-- about one time in a hundred, he doesn't stay dead. He comes back as a
-- giant, level 73, wielding Thunderfury and a Warglaive of Azzinoth, and
-- takes it out on whoever killed him, then on the rest of the town.
--
-- ---------------------------------------------------------------------
-- HOW IT TRIGGERS
--
-- Gamon (6466, the spawn at 1637.5, -4438 in Orgrimmar, 5-minute
-- respawn) gets a SmartAI death event with event_chance 1: each death has
-- a 1 % chance to summon Gamon's Revenge on top of his killer, attacking
-- them. That's "about every 100 kills" on average, with no counter to
-- keep. The unlucky can go 300 kills; the lucky get him on the first.
--
-- This is the one change to a stock row: Gamon's AIName becomes
-- 'SmartAI' (it was ''), so the death event can run. He still fights
-- exactly as before. The uninstall puts '' back.
--
-- To test without killing Gamon a hundred times, on a GM account:
--   .npc add temp 9100030
-- spawns him in front of you, not saved to the DB. He has no killer to
-- chase that way, so hit him first.
--
-- THE FIGHT
--
--   Level 73 boss, ~800k HP (HealthModifier 105), DamageModifier 30.
--   Faction 14 (hostile to everything), so the Orgrimmar guards pile in,
--   and so does every bot nearby. So do the city NPCs, who will die.
--   They respawn.
--   On arrival he yells to the whole server and goes for Gamon's killer.
--   (SmartAI's "everyone in range into combat" works in instances only,
--   and takes no range at this pin, so the town joins in by aggro.)
--     Cleave       31779  8-12 s
--     Thunderclap  36706  12-16 s
--     Thunderfury  21992  every 8-12 s: the real proc, which chains
--                         lightning off his target and cuts nature resist
--   He despawns 30 minutes after arriving, dead or not (summon type 1).
--   Loot: 15 Badges of Justice + 2 epics from Kazzak's table.
--
-- IDS
--
--   creature_template, creature_template_model, creature_equip_template,
--   creature_text, smart_scripts, creature_loot_template: 9100030
--   smart_scripts: 6466 (Gamon himself, death event only)
--
-- Idempotent: every DELETE is scoped to these IDs. Remove it all with
-- gamons-revenge-uninstall.sql.
-- ---------------------------------------------------------------------

SET @GAMON   := 6466;
SET @REVENGE := 9100030;
SET @KAZZAK  := 18728;  -- stat source: a level-73 world boss's row

-- ---------------------------------------------------------------------
-- Gamon's Revenge. Cloned from Kazzak so every column comes across, then
-- made into a big, hostile orc.
-- ---------------------------------------------------------------------

DELETE FROM `creature_template`       WHERE `entry`      = @REVENGE;
DELETE FROM `creature_template_model` WHERE `CreatureID` = @REVENGE;
DELETE FROM `creature_equip_template` WHERE `CreatureID` = @REVENGE;

DROP TEMPORARY TABLE IF EXISTS hprv_ct;
CREATE TEMPORARY TABLE hprv_ct AS SELECT * FROM `creature_template` WHERE `entry` = @KAZZAK;

UPDATE hprv_ct SET
  `entry` = @REVENGE, `name` = 'Gamon', `subname` = 'He Remembers',
  `type` = 7,                 -- humanoid
  `faction` = 14,             -- hostile to all
  `AIName` = 'SmartAI', `ScriptName` = '',
  `HealthModifier` = 105, `DamageModifier` = 30,
  `lootid` = @REVENGE;

INSERT INTO `creature_template` SELECT * FROM hprv_ct;
DROP TEMPORARY TABLE hprv_ct;

-- Gamon's own model, at 3x.
INSERT INTO `creature_template_model`
  (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`)
SELECT @REVENGE, `Idx`, `CreatureDisplayID`, 3, `Probability`, 0
  FROM `creature_template_model` WHERE `CreatureID` = @GAMON;

-- Thunderfury in the main hand, a Warglaive of Azzinoth in the off hand.
INSERT INTO `creature_equip_template` (`CreatureID`, `ID`, `ItemID1`, `ItemID2`, `ItemID3`, `VerifiedBuild`)
VALUES (@REVENGE, 1, 19019, 32838, 0, 0);

-- ---------------------------------------------------------------------
-- What he says. Type 14 = yell. TextRange 4 = the whole server, for the
-- arrival only; the rest is 2 = zone.
-- ---------------------------------------------------------------------

DELETE FROM `creature_text` WHERE `CreatureID` = @REVENGE;

INSERT INTO `creature_text`
  (`CreatureID`, `GroupID`, `ID`, `Text`, `Type`, `Language`, `Probability`, `Emote`, `Duration`, `Sound`, `BroadcastTextId`, `TextRange`, `comment`)
VALUES
  (@REVENGE, 0, 0, 'ENOUGH! A HUNDRED TIMES YOU HAVE KILLED GAMON! NOW GAMON KILLS YOU!',     14, 0, 100, 0, 0, 0, 0, 4, 'Gamon''s Revenge - arrival, server-wide'),
  (@REVENGE, 1, 0, 'Did someone say Thunderfury?',                                         14, 0, 100, 0, 0, 0, 0, 2, 'Gamon''s Revenge - Thunderfury'),
  (@REVENGE, 2, 0, 'Who''s laughing now?',                                                 14, 0, 100, 0, 0, 0, 0, 2, 'Gamon''s Revenge - kill'),
  (@REVENGE, 2, 1, 'Gamon never forgets a face!',                                          14, 0, 100, 0, 0, 0, 0, 2, 'Gamon''s Revenge - kill'),
  (@REVENGE, 2, 2, 'That one was for the Ragefire tax!',                                   14, 0, 100, 0, 0, 0, 0, 2, 'Gamon''s Revenge - kill'),
  (@REVENGE, 3, 0, 'Gamon... will... be back... in about... a hundred...',                 14, 0, 100, 0, 0, 0, 0, 2, 'Gamon''s Revenge - death');

-- ---------------------------------------------------------------------
-- SmartAI. Event types: 0 in-combat timer, 5 kill, 6 death,
-- 54 just summoned. Actions: 1 talk, 11 cast, 12 summon, 38 put everyone
-- in range into combat. Targets: 1 self, 2 victim, 5 random hostile,
-- 7 the event's invoker (on a death event: the killer).
-- ---------------------------------------------------------------------

DELETE FROM `smart_scripts` WHERE `entryorguid` IN (@GAMON, @REVENGE) AND `source_type` = 0;

UPDATE `creature_template` SET `AIName` = 'SmartAI' WHERE `entry` = @GAMON AND `AIName` = '';

INSERT INTO `smart_scripts`
  (`entryorguid`, `source_type`, `id`, `link`, `event_type`, `event_phase_mask`, `event_chance`, `event_flags`,
   `event_param1`, `event_param2`, `event_param3`, `event_param4`, `event_param5`, `event_param6`,
   `action_type`, `action_param1`, `action_param2`, `action_param3`, `action_param4`, `action_param5`, `action_param6`,
   `target_type`, `target_param1`, `target_param2`, `target_param3`, `target_param4`,
   `target_x`, `target_y`, `target_z`, `target_o`, `comment`)
VALUES
  -- Gamon: 1 % on death. Summon type 1 = despawn after 30 min or on death
  -- (the corpse stays for looting first). Target 7 is the killer: Revenge
  -- appears on top of them, and attackInvoker 1 sets him on them.
  -- (attackInvoker 2 is rejected at this pin: 0 or 1 only.)
  (@GAMON,   0, 0, 0,  6, 0,   1, 0,     0,     0,     0,     0, 0, 0, 12, @REVENGE, 1, 1800000, 1, 0, 0,  7,  0, 0, 0, 0,  0, 0, 0, 0, 'Gamon - death - 1% - Gamon''s Revenge on his killer'),

  (@REVENGE, 0, 0, 0, 54, 0, 100, 0,     0,     0,     0,     0, 0, 0,  1,     0,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Gamon''s Revenge - arrival - server-wide yell'),
  (@REVENGE, 0, 2, 0,  0, 0, 100, 0,  5000,  8000,  8000, 12000, 0, 0, 11, 31779,     0, 0, 0, 0, 0,  2,  0, 0, 0, 0,  0, 0, 0, 0, 'Gamon''s Revenge - Cleave'),
  (@REVENGE, 0, 3, 0,  0, 0, 100, 0, 10000, 12000, 12000, 16000, 0, 0, 11, 36706,     0, 0, 0, 0, 0,  2,  0, 0, 0, 0,  0, 0, 0, 0, 'Gamon''s Revenge - Thunderclap'),
  (@REVENGE, 0, 4, 0,  0, 0, 100, 0,  4000,  6000,  8000, 12000, 0, 0, 11, 21992,     0, 0, 0, 0, 0,  2,  0, 0, 0, 0,  0, 0, 0, 0, 'Gamon''s Revenge - Thunderfury on his target (melee range; it chains)'),
  (@REVENGE, 0, 5, 0,  0, 0,  25, 0,  4000,  6000,  8000, 12000, 0, 0,  1,     1,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Gamon''s Revenge - "Did someone say Thunderfury?"'),
  (@REVENGE, 0, 6, 0,  5, 0, 100, 0,  6000, 12000,     1,     0, 0, 0,  1,     2,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Gamon''s Revenge - killed a player - yell'),
  (@REVENGE, 0, 7, 0,  6, 0, 100, 0,     0,     0,     0,     0, 0, 0,  1,     3,     0, 0, 0, 0, 0,  1,  0, 0, 0, 0,  0, 0, 0, 0, 'Gamon''s Revenge - death - yell');

-- ---------------------------------------------------------------------
-- Loot.
-- ---------------------------------------------------------------------

DELETE FROM `creature_loot_template` WHERE `Entry` = @REVENGE;

INSERT INTO `creature_loot_template`
  (`Entry`, `Item`, `Reference`, `Chance`, `QuestRequired`, `LootMode`, `GroupId`, `MinCount`, `MaxCount`, `Comment`)
VALUES
  (@REVENGE, 29434,     0, 100, 0, 1, 0, 15, 15, 'Gamon''s Revenge (HPRV) - Badge of Justice x15'),
  (@REVENGE,     1, 26043, 100, 0, 1, 0,  2,  2, 'Gamon''s Revenge (HPRV) - 2 from Doom Lord Kazzak''s reference table');

SELECT 'Gamon''s Revenge installed; restart the worldserver. Test: .npc add temp 9100030' AS result;
