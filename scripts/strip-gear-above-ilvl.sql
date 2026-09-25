-- HPRV — delete equipped gear above an item-level cap
--
-- The reset back to Karazhan tier ("start the Tier 4 journey"). Run
-- 2026-09-25 at @CAP = 125 over the 25-body roster (scripts/roster.conf:
-- MASTER + BOT_01..24): 165 pieces in a first pass, then 189 more from
-- the 13 roster bots the first pass missed. DELETES, does not mail —
-- that was the explicit choice. Only EQUIPPED slots (bag 0, slots 0-18)
-- are touched; bags and bank are left alone.
--
-- DESTRUCTIVE. Take a dump first:
--   mysqldump --single-transaction --no-tablespaces acore_characters \
--     | gzip > /opt/hprv/backups/acore_characters-$(date +%Y%m%d-%H%M%S).sql.gz
--
-- SAFE WITH THE SERVER RUNNING, for offline characters only. An online
-- character holds its items in memory and writes them back on logout,
-- undoing the delete — so online characters are SKIPPED, and listed by
-- the first SELECT. Log them out (or stop worldserver) and re-run to
-- catch them. An offline character's items are only read at login.
--
-- ALSO REBUILDS characters.equipmentCache for everyone stripped. That
-- column is what the character-select screen draws, and the server only
-- rewrites it on save — so without this a stripped character still
-- LOOKS fully geared at character select until its next login. The
-- rebuild reproduces the server's own format: 23 "entry enchant" pairs
-- (equipment slots 0-18, then bag slots 19-22), where enchant is the
-- permanent enchant | temporary enchant << 16 and is 0 for bags.
-- Verified 2026-09-25 byte-identical to server-written caches on nine
-- characters.
--
-- Edit @CAP and the name list, then run against acore_characters.
-- Idempotent: a second run finds nothing to delete.
-- ---------------------------------------------------------------------

SET @CAP := 125;

DROP TEMPORARY TABLE IF EXISTS `roster`;
CREATE TEMPORARY TABLE `roster` (`name` VARCHAR(12) PRIMARY KEY);
INSERT INTO `roster` VALUES
  ('Bullwark'),
  ('Ararin'), ('Nathos'), ('Krast'), ('Tanke'), ('Izri'), ('Lomul'),
  ('Dijito'), ('Celerina'), ('Ilyna'), ('Anmine'), ('Sehjece'), ('Crumm'),
  ('Rechiw'), ('Ralda'), ('Zaene'), ('Muhnun'), ('Fehmos'), ('Dehme'),
  ('Olidina'), ('Irntifumm'), ('Mutlie'), ('Tengwe'), ('Vestanza'), ('Grohtarty');

SELECT c.`name` AS `skipped_online` FROM `acore_characters`.`characters` c
  JOIN `roster` r ON r.`name` = c.`name` WHERE c.`online` = 1;

DROP TEMPORARY TABLE IF EXISTS `strip`;
CREATE TEMPORARY TABLE `strip` (`item` INT UNSIGNED PRIMARY KEY, `owner` INT UNSIGNED, KEY (`owner`))
SELECT ci.`item`, c.`guid` AS `owner`
  FROM `acore_characters`.`characters` c
  JOIN `roster` r                                  ON r.`name`   = c.`name`
  JOIN `acore_characters`.`character_inventory` ci ON ci.`guid`  = c.`guid`
  JOIN `acore_characters`.`item_instance` ii       ON ii.`guid`  = ci.`item`
  JOIN `acore_world`.`item_template` it            ON it.`entry` = ii.`itemEntry`
 WHERE c.`online` = 0
   AND ci.`bag` = 0 AND ci.`slot` < 19
   AND it.`ItemLevel` > @CAP;

DROP TEMPORARY TABLE IF EXISTS `stripped_chars`;
CREATE TEMPORARY TABLE `stripped_chars` (`guid` INT UNSIGNED PRIMARY KEY)
SELECT DISTINCT `owner` AS `guid` FROM `strip`;

SELECT COUNT(*) AS `items_to_delete`, COUNT(DISTINCT `owner`) AS `characters` FROM `strip`;

START TRANSACTION;

DELETE FROM `acore_characters`.`character_inventory`       WHERE `item`      IN (SELECT `item` FROM `strip`);
DELETE FROM `acore_characters`.`character_gifts`           WHERE `item_guid` IN (SELECT `item` FROM `strip`);
DELETE FROM `acore_characters`.`item_refund_instance`      WHERE `item_guid` IN (SELECT `item` FROM `strip`);
DELETE FROM `acore_characters`.`item_soulbound_trade_data` WHERE `itemGuid`  IN (SELECT `item` FROM `strip`);
DELETE FROM `acore_characters`.`item_instance`             WHERE `guid`      IN (SELECT `item` FROM `strip`);

UPDATE `acore_characters`.`characters` c
  JOIN (
    SELECT sc.`guid`,
           GROUP_CONCAT(CONCAT(IFNULL(ii.`itemEntry`, 0), ' ',
                               IF(s.n < 19 AND ii.`guid` IS NOT NULL,
                                  CAST(SUBSTRING_INDEX(ii.`enchantments`, ' ', 1) AS UNSIGNED)
                                  | (CAST(SUBSTRING_INDEX(SUBSTRING_INDEX(ii.`enchantments`, ' ', 4), ' ', -1) AS UNSIGNED) << 16),
                                  0), ' ')
                        ORDER BY s.n SEPARATOR '') AS `cache`
      FROM `stripped_chars` sc
      CROSS JOIN (WITH RECURSIVE seq(n) AS (SELECT 0 UNION ALL SELECT n + 1 FROM seq WHERE n < 22) SELECT n FROM seq) s
      LEFT JOIN `acore_characters`.`character_inventory` ci ON ci.`guid` = sc.`guid` AND ci.`bag` = 0 AND ci.`slot` = s.n
      LEFT JOIN `acore_characters`.`item_instance` ii       ON ii.`guid` = ci.`item`
     GROUP BY sc.`guid`
  ) r ON r.`guid` = c.`guid`
   SET c.`equipmentCache` = r.`cache`;

COMMIT;
