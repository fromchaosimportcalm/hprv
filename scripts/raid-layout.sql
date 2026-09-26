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
-- It only moves characters already in Bullwark's raid. Anyone missing is
-- reported by the final check, and the transaction is rolled back. Invite
-- them in game, then re-run.

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

-- Moving a member cannot overfill a group mid-update: group_member has no
-- per-subgroup constraint, and the checks below assert the end state.
UPDATE acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
   SET gm.subgroup = CASE c.name
        -- Group 1: tank, melee, totems, tank healer        (the ten)
        WHEN 'Bullwark'    THEN 0
        WHEN 'Crumm'       THEN 0
        WHEN 'Anmine'      THEN 0
        WHEN 'Krast'       THEN 0
        WHEN 'Nathos'      THEN 0
        -- Group 2: casters, hunter, druid healer           (the ten)
        WHEN 'Celerina'    THEN 1
        WHEN 'Dijito'      THEN 1
        WHEN 'Izri'        THEN 1
        WHEN 'Ilyna'       THEN 1
        WHEN 'Restofarian' THEN 1
        -- Group 3: melee, enhancement totems
        WHEN 'Ararin'      THEN 2
        WHEN 'Gerina'      THEN 2
        WHEN 'Muhnun'      THEN 2
        WHEN 'Zaene'       THEN 2
        WHEN 'Fimur'       THEN 2
        -- Group 4: casters, elemental totems
        WHEN 'Sehjece'     THEN 3
        WHEN 'Lomul'       THEN 3
        WHEN 'Vestanza'    THEN 3
        WHEN 'Grohtarty'   THEN 3
        WHEN 'Tengwe'      THEN 3
        -- Group 5: healers, resto totems
        WHEN 'Tanke'       THEN 4
        WHEN 'Irntifumm'   THEN 4
        WHEN 'Olidina'     THEN 4
        WHEN 'Dehme'       THEN 4
        WHEN 'Fehmos'      THEN 4
        ELSE gm.subgroup
       END
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
