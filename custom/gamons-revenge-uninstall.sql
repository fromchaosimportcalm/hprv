-- HPRV — remove Gamon's Revenge (gamons-revenge.sql)
--
--   mysql acore_world < gamons-revenge-uninstall.sql    # then restart
--
-- Deletes exactly the rows gamons-revenge.sql writes, and puts Gamon's
-- (6466) AIName back to '' as it was in the stock DB.
-- ---------------------------------------------------------------------

SET @GAMON   := 6466;
SET @REVENGE := 9100030;

DELETE FROM `smart_scripts`           WHERE `entryorguid` IN (@GAMON, @REVENGE) AND `source_type` = 0;
UPDATE `creature_template` SET `AIName` = '' WHERE `entry` = @GAMON AND `AIName` = 'SmartAI';
DELETE FROM `creature_loot_template`  WHERE `Entry` = @REVENGE;
DELETE FROM `creature_text`           WHERE `CreatureID` = @REVENGE;
DELETE FROM `creature_equip_template` WHERE `CreatureID` = @REVENGE;
DELETE FROM `creature_template_model` WHERE `CreatureID` = @REVENGE;
DELETE FROM `creature_template`       WHERE `entry` = @REVENGE;

SELECT 'Gamon''s Revenge removed; restart the worldserver' AS result;
