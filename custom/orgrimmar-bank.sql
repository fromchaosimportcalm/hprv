-- HPRV — the Bank of Orgrimmar becomes the custom-NPC hall (2026-10-03)
--
-- HPRV only, and NOT packaged: it removes stock spawns, which another
-- server may want. Only family plays here, with big bags, so the bank and
-- guild bank are dead weight, and the bank's flat floor is a better home
-- for the custom NPCs than the ramp outside (tier-vendors.sql had to
-- measure a z per vendor there).
--
-- REMOVES (stock rows; orgrimmar-bank-revert.sql puts back exactly these)
--   Bankers Soran 4655, Karus 6598, Koma 4653, plus their phased Battle
--   for Undercity copies 1976083-85 (phaseMask 192: invisible to us, but
--   mod-hprv-city would still send bots to stand at their banker flag),
--   and their 3 creature_addon rows. Checked 2026-10-03: nothing else
--   references them (events, pools, formations, SmartAI all 0).
--   Both Guild Vaults in the bank, 12496 and 12497 (no addon/event/pool).
--   The "Bank of Orgrimmar" sign over the door, 10101 (no addon/event),
--   replaced by ours below.
--   Banks elsewhere (Undercity, Thunder Bluff, Shattrath) are untouched,
--   so anything already in a bank is still reachable.
--
-- MOVES the six custom NPCs onto the bankers' line, Soran's end (left as
-- you face them) to Koma's (right), stretched 1.5 yd past each and evenly
-- spaced 3.8 yd apart, all facing the door the way the bankers did
-- (3.578). z is the bankers' own floor height.
--
-- THE SIGN: our own template 9100006, "Hall of Champions", on the stock
-- Orc Armory sign model (display 717, ORCSIGN_ARMORY.MDX, in every 3.3.5a
-- client, so no patch). A new entry rather than renaming 173216: the
-- stock template stays clean, and clients have the old name cached
-- (WDB), which a new entry sidesteps. Spawned at 10101's exact position
-- and rotation, guid 9100006. Note: the first gameobject guid in our
-- range means the next in-game `.gobject add` lands at 9100007, inside
-- it (the same is already true of `.npc add`, see docs/custom-npcs.md).
--
-- ORDER: tier-vendors.sql, weapon-vendor.sql and teleporter-npc.sql still
-- spawn at the old Valley of Strength row. If you re-run any of them,
-- re-run this after. New spawns need a restart to show.

SET @O := 3.578;

DELETE FROM `creature_addon` WHERE `guid` IN (4653, 4655, 6598, 1976083, 1976084, 1976085);
DELETE FROM `creature`       WHERE `guid` IN (4653, 4655, 6598, 1976083, 1976084, 1976085);
DELETE FROM `gameobject`     WHERE `guid` IN (12496, 12497, 10101);

DELETE FROM `gameobject_template` WHERE `entry` = 9100006;
INSERT INTO `gameobject_template`
  (`entry`, `type`, `displayId`, `name`, `IconName`, `castBarCaption`, `unk1`, `size`,
   `Data0`, `Data1`, `Data2`, `Data3`, `Data4`, `Data5`, `Data6`, `Data7`, `Data8`, `Data9`, `Data10`, `Data11`,
   `Data12`, `Data13`, `Data14`, `Data15`, `Data16`, `Data17`, `Data18`, `Data19`, `Data20`, `Data21`, `Data22`, `Data23`,
   `AIName`, `ScriptName`, `VerifiedBuild`)
VALUES
  (9100006, 5, 717, 'Hall of Champions', '', '', '', 1.33,
   1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
   '', '', 0);

DELETE FROM `gameobject` WHERE `guid` = 9100006 OR (`id` = 9100006 AND `guid` NOT BETWEEN 9100000 AND 9100099);
INSERT INTO `gameobject`
  (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`,
   `position_x`, `position_y`, `position_z`, `orientation`,
   `rotation0`, `rotation1`, `rotation2`, `rotation3`,
   `spawntimesecs`, `animprogress`, `state`, `ScriptName`, `VerifiedBuild`, `Comment`)
VALUES
  (9100006, 9100006, 1, 1637, 1637, 1, 1, 1613.29, -4388.24, 10.1155, -2.6529,
   0, 0, -0.970296, 0.241922, 900, 100, 1, '', 0, 'HPRV Hall of Champions sign - Orgrimmar');

UPDATE `creature` SET `position_x` = 1622.01, `position_y` = -4367.85, `position_z` = 12.05, `orientation` = @O WHERE `guid` = 9100001;  -- Almari, T4
UPDATE `creature` SET `position_x` = 1624.26, `position_y` = -4370.92, `position_z` = 12.05, `orientation` = @O WHERE `guid` = 9100002;  -- Veshan, T5
UPDATE `creature` SET `position_x` = 1626.52, `position_y` = -4373.98, `position_z` = 12.05, `orientation` = @O WHERE `guid` = 9100003;  -- Oriel, T6
UPDATE `creature` SET `position_x` = 1628.77, `position_y` = -4377.05, `position_z` = 12.05, `orientation` = @O WHERE `guid` = 9100004;  -- Torvek, weapons
UPDATE `creature` SET `position_x` = 1631.03, `position_y` = -4380.11, `position_z` = 12.05, `orientation` = @O WHERE `guid` = 9100005;  -- Warpweaver, transmog
UPDATE `creature` SET `position_x` = 1633.28, `position_y` = -4383.18, `position_z` = 12.05, `orientation` = @O WHERE `guid` = 9100000;  -- Porter Nozdrel
