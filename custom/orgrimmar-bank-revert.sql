-- HPRV — undo orgrimmar-bank.sql: put back the stock bankers, guild
-- vaults and bank sign exactly as they were (dumped from acore_world 2026-10-03), and
-- the five custom NPCs at their old Valley of Strength row. Restart after.
-- The transmogrifier (9100005) stays where it is; move it by hand if wanted.

DELETE FROM `creature_addon` WHERE `guid` IN (4653, 4655, 6598, 1976083, 1976084, 1976085);
DELETE FROM `creature`       WHERE `guid` IN (4653, 4655, 6598, 1976083, 1976084, 1976085);
DELETE FROM `gameobject`     WHERE `guid` IN (12496, 12497, 10101, 9100006);
DELETE FROM `gameobject_template` WHERE `entry` = 9100006;

INSERT INTO `creature` VALUES (4653,3318,1,0,0,1,1,1,1632.39,-4381.97,12.0438,3.57792,300,0,0,5544,0,0,0,0,0,'',0,0,NULL);
INSERT INTO `creature` VALUES (4655,3320,1,0,0,1,1,1,1622.9,-4369.06,12.0536,3.57792,300,0,0,5544,0,0,0,0,0,'',0,0,NULL);
INSERT INTO `creature` VALUES (6598,3309,1,0,0,1,1,1,1627.32,-4376.07,12.0576,3.4383,300,0,0,5544,0,0,0,0,0,'',0,0,NULL);
INSERT INTO `creature` VALUES (1976083,31420,1,0,0,1,192,1,1627.42,-4376.04,12.0548,3.68265,300,0,0,5544,0,0,0,0,0,'',0,0,NULL);
INSERT INTO `creature` VALUES (1976084,31421,1,0,0,1,192,1,1632.61,-4381.89,12.0115,3.59538,300,0,0,5544,0,0,0,0,0,'',0,0,NULL);
INSERT INTO `creature` VALUES (1976085,31422,1,0,0,1,192,1,1623.04,-4368.92,12.0296,3.92699,300,0,0,5544,0,0,0,0,0,'',0,0,NULL);
INSERT INTO `creature_addon` VALUES (4653,0,0,0,1,0,0,NULL);
INSERT INTO `creature_addon` VALUES (4655,0,0,0,1,0,0,NULL);
INSERT INTO `creature_addon` VALUES (6598,0,0,0,1,0,0,NULL);
INSERT INTO `gameobject` VALUES (12496,187292,1,1637,1637,1,1,1624.84,-4362.77,12.4746,-2.30383,0,0,-0.913544,0.406739,900,100,1,'',0,NULL);
INSERT INTO `gameobject` VALUES (12497,187292,1,1637,1637,1,1,1638.22,-4382.22,12.5441,1.15192,0,0,0.54464,0.83867,900,100,1,'',0,NULL);
UPDATE `creature` SET `position_x` = 1637.41, `position_y` = -4404.22, `position_z` = 16.6179, `orientation` = 3.06538 WHERE `guid` = 9100000;
UPDATE `creature` SET `position_x` = 1634.5, `position_y` = -4408.8, `position_z` = 16.56, `orientation` = 3.06538 WHERE `guid` = 9100001;
UPDATE `creature` SET `position_x` = 1634.5, `position_y` = -4411.1, `position_z` = 16.85, `orientation` = 3.06538 WHERE `guid` = 9100002;
UPDATE `creature` SET `position_x` = 1634.5, `position_y` = -4413.4, `position_z` = 16.75, `orientation` = 3.06538 WHERE `guid` = 9100003;
UPDATE `creature` SET `position_x` = 1634.5, `position_y` = -4406.5, `position_z` = 16.41, `orientation` = 3.06538 WHERE `guid` = 9100004;
INSERT INTO `gameobject` VALUES (10101,173216,1,1637,1637,1,1,1613.29,-4388.24,10.1155,-2.6529,0,0,-0.970296,0.241922,900,100,1,'',0,NULL);
