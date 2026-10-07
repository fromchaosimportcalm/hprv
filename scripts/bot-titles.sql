-- HPRV — every bot in guild HPRV wears a random, era-believable title (2026-10-08)
--
-- Where the raid is: back in Karazhan and Gruul after the Tier 4 reset, but
-- with Black Temple behind them. All 25 already know "Hand of A'dal" (bit
-- 39), the BT attunement title, and Bullwark and Nathos wear it. So the
-- pool is what a 2.4.3 Horde raider who'd seen BT might have earned:
--
--   PvE    Hand of A'dal (most likely), Champion of the Naaru, of the
--          Shattered Sun, and one-in-a-hundred Scarab Lord
--   Honor  the old Horde PvP ranks, Scout to High Warlord. Common at the
--          bottom, rare at the top. They're the retirement village's
--          vanilla veterans
--   Arena  Challenger, Rival, Duelist, then a rare Gladiator,
--          Merciless, Vengeful or Brutal
--
-- Nothing from WotLK: no achievement, holiday, profession or city titles.
-- The weights are in hprv_title_pool below and sum to 100.
--
-- Bullwark is left alone: he's the human and picks his own. Every other
-- member of HPRV is rolled, so this re-rolls Nathos. The new title is
-- added to knownTitles (the old ones stay known) and set as chosenTitle,
-- which holds the CharTitles *bit index*, not its ID. Titles survive gear
-- passes: PlayerbotFactory has no title code at this pin. Bench characters
-- aren't in the guild, so they get one only if they join it and this runs
-- again.
--
-- Re-running re-rolls everyone. That's deliberate: you can roll again if
-- you don't like the spread.
--
-- BEFORE RUNNING
--   1. Log out. Then: systemctl stop hprv-worldserver
--      (bots on account 101 are online whenever you are, and a logout
--      writes chosenTitle back over this)
--   2. mysqldump --single-transaction acore_characters \
--        | gzip > /opt/hprv/backups/pre-titles-$(date +%Y%m%d-%H%M%S).sql.gz
--      and check the tail reads "-- Dump completed".

USE acore_characters;

-- Real tables, not TEMPORARY (ERROR 1137, see guild-hprv.sql), created
-- before the transaction because DDL commits implicitly.
DROP TABLE IF EXISTS hprv_title_pool;
CREATE TABLE hprv_title_pool (
  bit    TINYINT UNSIGNED PRIMARY KEY,  -- CharTitles.dbc Mask_ID
  title  VARCHAR(40) NOT NULL,
  weight DECIMAL(5,2) NOT NULL,
  lo     DECIMAL(6,2) NULL,             -- cumulative range [lo, hi)
  hi     DECIMAL(6,2) NULL
);
INSERT INTO hprv_title_pool (bit, title, weight) VALUES
  -- PvE: 40.5
  (39, '%s, Hand of A''dal',          23.50),
  (36, '%s, Champion of the Naaru',   12.00),
  (38, '%s of the Shattered Sun',      4.00),
  (33, 'Scarab Lord %s',               1.00),
  -- Honor ranks: 43
  (15, 'Scout %s',                     3.50),
  (16, 'Grunt %s',                     5.00),
  (17, 'Sergeant %s',                  5.00),
  (18, 'Senior Sergeant %s',           5.00),
  (19, 'First Sergeant %s',            5.00),
  (20, 'Stone Guard %s',               4.00),
  (21, 'Blood Guard %s',               4.00),
  (22, 'Legionnaire %s',               3.00),
  (23, 'Centurion %s',                 3.00),
  (24, 'Champion %s',                  2.00),
  (25, 'Lieutenant General %s',        1.50),
  (26, 'General %s',                   1.00),
  (27, 'Warlord %s',                   0.75),
  (28, 'High Warlord %s',              0.25),
  -- Arena, seasons 1-4: 16.5
  (32, 'Challenger %s',                5.00),
  (31, 'Rival %s',                     5.00),
  (30, 'Duelist %s',                   3.00),
  (29, 'Gladiator %s',                 1.50),
  (37, 'Merciless Gladiator %s',       1.00),
  (40, 'Vengeful Gladiator %s',        0.50),
  (49, 'Brutal Gladiator %s',          0.50);

UPDATE hprv_title_pool p
  JOIN (SELECT bit, SUM(weight) OVER (ORDER BY bit) AS hi FROM hprv_title_pool) c ON c.bit = p.bit
   SET p.hi = c.hi, p.lo = c.hi - p.weight;

DROP TABLE IF EXISTS hprv_title_roll;
CREATE TABLE hprv_title_roll (guid INT UNSIGNED PRIMARY KEY, roll DECIMAL(6,2) NOT NULL, bit TINYINT UNSIGNED NULL);

START TRANSACTION;

-- Guards: a false condition raises ERROR 1242 and the transaction rolls
-- back on disconnect (same pattern as swap-standing-ten.sql).
SELECT IF(COUNT(*) = 0, 'ok: nobody online', (SELECT 1 UNION SELECT 2)) AS precheck_online
  FROM characters WHERE online = 1;
SELECT IF(SUM(weight) = 100, 'ok: weights sum to 100', (SELECT 1 UNION SELECT 2)) AS precheck_weights
  FROM hprv_title_pool;
-- The pool is Horde-only (the honor ranks are). Orc, Undead, Tauren, Troll, Blood Elf.
SELECT IF(COUNT(*) = 0, 'ok: the guild is all Horde', (SELECT 1 UNION SELECT 2)) AS precheck_horde
  FROM guild g JOIN guild_member gm ON gm.guildid = g.guildid JOIN characters c ON c.guid = gm.guid
 WHERE g.name = 'HPRV' AND c.race NOT IN (2, 5, 6, 8, 10);
SELECT IF(COUNT(*) = 24, 'ok: 24 bots to roll', (SELECT 1 UNION SELECT 2)) AS precheck_count
  FROM guild g JOIN guild_member gm ON gm.guildid = g.guildid JOIN characters c ON c.guid = gm.guid
 WHERE g.name = 'HPRV' AND c.name <> 'Bullwark';

INSERT INTO hprv_title_roll (guid, roll)
SELECT c.guid, TRUNCATE(RAND() * 100, 2)
  FROM guild g JOIN guild_member gm ON gm.guildid = g.guildid JOIN characters c ON c.guid = gm.guid
 WHERE g.name = 'HPRV' AND c.name <> 'Bullwark';

UPDATE hprv_title_roll r JOIN hprv_title_pool p ON r.roll >= p.lo AND r.roll < p.hi SET r.bit = p.bit;

SELECT IF(COUNT(*) = 0, 'ok: every roll landed on a title', (SELECT 1 UNION SELECT 2)) AS check_rolls
  FROM hprv_title_roll WHERE bit IS NULL;

-- knownTitles is six space-separated uint32 words ("0 128 0 0 0 0 "). Set
-- the rolled bit in word bit DIV 32, keep everything else, and keep the
-- trailing space the server writes.
UPDATE characters c JOIN hprv_title_roll r ON r.guid = c.guid
   SET c.knownTitles = CONCAT(
         CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(c.knownTitles, ' ', 1), ' ', -1) AS UNSIGNED) | IF(r.bit DIV 32 = 0, 1 << (r.bit % 32), 0), ' ',
         CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(c.knownTitles, ' ', 2), ' ', -1) AS UNSIGNED) | IF(r.bit DIV 32 = 1, 1 << (r.bit % 32), 0), ' ',
         CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(c.knownTitles, ' ', 3), ' ', -1) AS UNSIGNED) | IF(r.bit DIV 32 = 2, 1 << (r.bit % 32), 0), ' ',
         CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(c.knownTitles, ' ', 4), ' ', -1) AS UNSIGNED) | IF(r.bit DIV 32 = 3, 1 << (r.bit % 32), 0), ' ',
         CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(c.knownTitles, ' ', 5), ' ', -1) AS UNSIGNED) | IF(r.bit DIV 32 = 4, 1 << (r.bit % 32), 0), ' ',
         CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(c.knownTitles, ' ', 6), ' ', -1) AS UNSIGNED) | IF(r.bit DIV 32 = 5, 1 << (r.bit % 32), 0), ' '),
       c.chosenTitle = r.bit;

-- Every rolled bit must now read back as known, or the server drops
-- chosenTitle to 0 at login.
SELECT IF(COUNT(*) = 0, 'ok: every chosen title is known', (SELECT 1 UNION SELECT 2)) AS check_known
  FROM characters c JOIN hprv_title_roll r ON r.guid = c.guid
 WHERE CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(c.knownTitles, ' ', (r.bit DIV 32) + 1), ' ', -1) AS UNSIGNED)
       & (1 << (r.bit % 32)) = 0
    OR c.chosenTitle <> r.bit;

SELECT c.name, REPLACE(p.title, '%s', c.name) AS wears, r.roll
  FROM hprv_title_roll r JOIN characters c ON c.guid = r.guid JOIN hprv_title_pool p ON p.bit = r.bit
 ORDER BY p.bit, c.name;

COMMIT;

DROP TABLE hprv_title_roll;
DROP TABLE hprv_title_pool;
