-- HPRV — put the 25 in one guild, "HPRV", led by Bullwark (2026-10-03)
--
-- Vanity, but it sticks: an init= pass only assigns a guild to a bot
-- with none (PlayerbotFactory::InitGuild), so gear passes leave this
-- alone. And because the leader is on account 101, not a random-bot
-- account, PlayerbotGuildMgr counts HPRV as a real player's guild and
-- never assigns ambient bots to it.
--
-- HOW: rename, don't create. Before this, the bot module had put the 25
-- in four of its own guilds. One of them, Cerulean Union (guildid 14),
-- was already led by Bullwark, and all five of its members are in the
-- 25. So it is renamed to HPRV, keeping its ranks, and the other 20 move
-- in. Two bot guilds lose their leader that way (Ilyna led Sweet Bear,
-- Tengwe led Brotherhood of Truth), so each is handed to its
-- highest-ranked remaining member before the move.
--
-- Ranks: Bullwark Guild Master (0), the ten Veteran (2), the 15 Member (3).
-- The 25 are written out below; they're scripts/roster.conf's GROUP=ten
-- and GROUP=25 plus MASTER_NAME, as of 2026-10-03.
--
-- BEFORE RUNNING
--   1. Log out. Then: systemctl stop hprv-worldserver
--   2. mysqldump --single-transaction acore_characters \
--        | gzip > /opt/hprv/backups/pre-guild-hprv-$(date +%Y%m%d-%H%M%S).sql.gz
--      and check the tail reads "-- Dump completed".
-- Re-running after success fails the "no guild named HPRV" guard, which
-- is the point: nothing is applied twice.

USE acore_characters;

-- A real table, not TEMPORARY: MySQL can't open a temporary table twice in
-- one query (ERROR 1137, caught in the dry run). Created before the
-- transaction because DDL inside one commits it implicitly.
DROP TABLE IF EXISTS hprv_guild_roster;
CREATE TABLE hprv_guild_roster (name VARCHAR(12) PRIMARY KEY, `rank` TINYINT UNSIGNED NOT NULL);
INSERT INTO hprv_guild_roster VALUES
  ('Bullwark', 0),
  -- the ten
  ('Nathos', 2), ('Crumm', 2), ('Krast', 2), ('Restofarian', 2), ('Dijito', 2),
  ('Izri', 2), ('Celerina', 2), ('Ilyna', 2), ('Anmine', 2),
  -- the 15
  ('Ararin', 3), ('Tanke', 3), ('Dehme', 3), ('Olidina', 3), ('Irntifumm', 3),
  ('Muhnun', 3), ('Zaene', 3), ('Gerina', 3), ('Fimur', 3), ('Sehjece', 3),
  ('Fehmos', 3), ('Lomul', 3), ('Vestanza', 3), ('Grohtarty', 3), ('Tengwe', 3);

START TRANSACTION;

-- Guards: a false condition raises ERROR 1242 and the transaction rolls
-- back on disconnect (same pattern as swap-standing-ten.sql).
SELECT IF(COUNT(*) = 0, 'ok: nobody online', (SELECT 1 UNION SELECT 2)) AS precheck_online
  FROM characters WHERE online = 1;
SELECT IF(COUNT(*) = 0, 'ok: no guild named HPRV yet', (SELECT 1 UNION SELECT 2)) AS precheck_name
  FROM guild WHERE name = 'HPRV';
SELECT IF(COUNT(*) = 1, 'ok: guild 14 is led by Bullwark', (SELECT 1 UNION SELECT 2)) AS precheck_leader
  FROM guild g JOIN characters c ON c.guid = g.leaderguid
 WHERE g.guildid = 14 AND c.name = 'Bullwark';

SELECT IF(COUNT(*) = 25, 'ok: all 25 names resolve', (SELECT 1 UNION SELECT 2)) AS precheck_names
  FROM hprv_guild_roster r JOIN characters c ON c.name = r.name;

-- 1. Any other guild led by one of the 25 gets a new leader: its
--    highest-ranked member outside the 25 (lowest guid breaks ties).
--    A guild left with nobody outside the 25 would be emptied; none is,
--    but the guard checks rather than assumes.
DROP TEMPORARY TABLE IF EXISTS hprv_new_leader;
CREATE TEMPORARY TABLE hprv_new_leader AS
SELECT g.guildid,
       (SELECT gm.guid FROM guild_member gm
          JOIN characters c ON c.guid = gm.guid
         WHERE gm.guildid = g.guildid
           AND c.name NOT IN (SELECT name FROM hprv_guild_roster)
         ORDER BY gm.`rank`, gm.guid LIMIT 1) AS new_leader
  FROM guild g
  JOIN characters lc ON lc.guid = g.leaderguid
 WHERE g.guildid <> 14
   AND lc.name IN (SELECT name FROM hprv_guild_roster);

SELECT IF(SUM(new_leader IS NULL) = 0, CONCAT('ok: ', COUNT(*), ' guild(s) get a new leader'), (SELECT 1 UNION SELECT 2)) AS precheck_handover
  FROM hprv_new_leader;

UPDATE guild g JOIN hprv_new_leader n ON n.guildid = g.guildid
   SET g.leaderguid = n.new_leader;
UPDATE guild_member gm JOIN hprv_new_leader n ON n.new_leader = gm.guid
   SET gm.`rank` = 0;

-- 2. Move the 25: out of wherever they are, into guild 14.
DELETE gm FROM guild_member gm
  JOIN characters c ON c.guid = gm.guid
  JOIN hprv_guild_roster r ON r.name = c.name;
DELETE w FROM guild_member_withdraw w
  JOIN characters c ON c.guid = w.guid
  JOIN hprv_guild_roster r ON r.name = c.name;

INSERT INTO guild_member (guildid, guid, `rank`, pnote, offnote)
SELECT 14, c.guid, r.`rank`, '', ''
  FROM hprv_guild_roster r JOIN characters c ON c.name = r.name;

-- 3. The rename.
UPDATE guild SET name = 'HPRV', motd = 'Hellfire Peninsula Retirement Village' WHERE guildid = 14;

-- Post-checks.
SELECT IF(COUNT(*) = 25, 'ok: HPRV has 25 members', (SELECT 1 UNION SELECT 2)) AS postcheck_count
  FROM guild_member WHERE guildid = 14;
SELECT IF(COUNT(*) = 0, 'ok: every guild leader is a member of it', (SELECT 1 UNION SELECT 2)) AS postcheck_leaders
  FROM guild g LEFT JOIN guild_member gm ON gm.guid = g.leaderguid AND gm.guildid = g.guildid
 WHERE gm.guid IS NULL;

COMMIT;

DROP TABLE hprv_guild_roster;

-- ROLLBACK: restore the pre-guild-hprv dump of acore_characters.
