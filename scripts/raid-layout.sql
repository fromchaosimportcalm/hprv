-- HPRV — put the raid back in its standard party layout
--
-- The layout is docs/raid-layout.md. You normally never need this file:
-- group_member.subgroup persists across logout and restart, so a layout
-- set once holds. This is the repair for when something has scrambled it
-- (a disband, a kick, a bot re-invited into the first free slot).
--
-- RUN WITH THE SERVER STOPPED. While it runs, the group lives in memory
-- and is written back over any change made here.
--
--   systemctl stop <worldserver unit>
--   mysql < raid-layout.sql
--   systemctl start <worldserver unit>     # then watch for `ready...`
--
-- subgroup is 0-based: 0 is "Group 1" in the raid UI.
--
-- It removes anyone in Bullwark's raid who isn't one of the 25, and moves
-- the rest into place. It never adds anyone: a missing member fails the
-- final check, and the transaction is rolled back. Invite them in game,
-- then re-run.

USE acore_characters;

START TRANSACTION;

-- Guards: a false condition raises ERROR 1242 ("Subquery returns more
-- than 1 row"), the client stops, and the open transaction rolls back on
-- disconnect. Same pattern as swap-standing-ten.sql.
SELECT IF(COUNT(*) = 0, 'ok: nobody online', (SELECT 1 UNION SELECT 2)) AS precheck_online
  FROM acore_characters.characters WHERE online = 1;

SELECT gm.guid INTO @raid
  FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 WHERE c.name = 'Bullwark';

SELECT IF(@raid IS NOT NULL, 'ok: Bullwark is in a raid', (SELECT 1 UNION SELECT 2)) AS precheck_raid;

-- The 25 and their parties. 0-based: 0 is "Group 1" in the raid UI.
DROP TEMPORARY TABLE IF EXISTS hprv_layout;
CREATE TEMPORARY TABLE hprv_layout (name VARCHAR(12) PRIMARY KEY, subgroup TINYINT UNSIGNED);
INSERT INTO hprv_layout VALUES
  -- Group 1: tank, melee, hunter, druid healer       (the ten)
  ('Bullwark', 0), ('Crumm', 0), ('Anmine', 0), ('Ilyna', 0), ('Restofarian', 0),
  -- Group 2: casters and the tank healer in Krast's resto totems (the ten)
  ('Krast', 1), ('Nathos', 1), ('Celerina', 1), ('Dijito', 1), ('Izri', 1),
  -- Group 3: melee, enhancement totems
  ('Ararin', 2), ('Gerina', 2), ('Muhnun', 2), ('Zaene', 2), ('Fimur', 2),
  -- Group 4: casters, elemental totems
  ('Sehjece', 3), ('Lomul', 3), ('Vestanza', 3), ('Grohtarty', 3), ('Tengwe', 3),
  -- Group 5: healers, resto totems
  ('Tanke', 4), ('Irntifumm', 4), ('Olidina', 4), ('Dehme', 4), ('Fehmos', 4);

-- Anyone in the raid who isn't one of the 25 leaves it: a bench body
-- summoned for a night, or a stray picked up by `.playerbots bot add *`
-- (2026-10-01: Ralda, Mutlie and Netohje). They are named here first.
SELECT c.name AS removing_from_raid
  FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 WHERE gm.guid = @raid AND c.name NOT IN (SELECT name FROM hprv_layout);

DELETE gm FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 WHERE gm.guid = @raid AND c.name NOT IN (SELECT name FROM hprv_layout);

-- Moving a member cannot overfill a group mid-update: group_member has no
-- per-subgroup constraint, and the checks below assert the end state.
UPDATE acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
  JOIN hprv_layout l ON l.name = c.name
   SET gm.subgroup = l.subgroup
 WHERE gm.guid = @raid;

-- Verify inside the transaction. Every line must read ok.
SELECT IF(COUNT(*) = 25, 'ok: 25 in the raid', (SELECT 1 UNION SELECT 2)) AS check_count
  FROM acore_characters.group_member WHERE guid = @raid;

SELECT IF(MAX(n) <= 5, 'ok: no group over 5', (SELECT 1 UNION SELECT 2)) AS check_sizes
  FROM (SELECT subgroup, COUNT(*) n FROM acore_characters.group_member
         WHERE guid = @raid GROUP BY subgroup) s;

-- The ten must sit in groups 1-2 alone, so a 10-man night is intact
-- with the 15 offline.
SELECT IF(COUNT(*) = 10, 'ok: the ten in groups 1-2', (SELECT 1 UNION SELECT 2)) AS check_ten
  FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 WHERE gm.guid = @raid AND gm.subgroup IN (0, 1) AND c.account = 101;

SELECT gm.subgroup + 1 AS `group`, GROUP_CONCAT(c.name ORDER BY c.name) AS members
  FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 WHERE gm.guid = @raid
 GROUP BY gm.subgroup ORDER BY gm.subgroup;

COMMIT;
