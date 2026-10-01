-- HPRV — remove Highlord Kruul (world-boss-kruul.sql)
--
--   mysql acore_world < world-boss-kruul-uninstall.sql    # then restart
--
-- Deletes exactly the rows world-boss-kruul.sql writes. The stock Kruul
-- (18338), Kazzak and the felhound it was cloned from are untouched.
-- ---------------------------------------------------------------------

SET @KRUUL := 9100020;
SET @HOUND := 9100021;
SET @GUID  := 9100020;
SET @EVENT := 240;

DELETE FROM `game_event_creature`     WHERE `eventEntry` = @EVENT OR `guid` = @GUID;
DELETE FROM `game_event`              WHERE `eventEntry` = @EVENT;
DELETE FROM `creature`                WHERE `guid` = @GUID OR `id` IN (@KRUUL, @HOUND);
DELETE FROM `creature_loot_template`  WHERE `Entry` = @KRUUL;
DELETE FROM `smart_scripts`           WHERE `entryorguid` IN (@KRUUL, @HOUND) AND `source_type` = 0;
DELETE FROM `creature_text`           WHERE `CreatureID` = @KRUUL;
DELETE FROM `creature_template_model` WHERE `CreatureID` IN (@KRUUL, @HOUND);
DELETE FROM `creature_template`       WHERE `entry` IN (@KRUUL, @HOUND);

SELECT 'Highlord Kruul removed; restart the worldserver' AS result;
