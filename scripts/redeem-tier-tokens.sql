-- HPRV — redeem the bots' Tier 4 tokens (TODO item 9)
--
-- mod-playerbots has no token code at all: bots need-roll a token their
-- class can use, then keep it in their bags forever. This turns each one
-- into its tier piece IN PLACE: the same item_instance row, the same bag
-- slot, only the item entry changes. So nothing new is created, and
-- nothing moves.
--
-- WHICH PIECE: the set for the bot's ROSTER spec (scripts/roster.conf),
-- not whatever it is wearing. A token redeems into any of its class's
-- sets, and Gerina's legs should be arms Battle-Gear, not prot Armor.
-- Sets were told apart by stats (2026-10-03): defence = prot, int+crit
-- without spirit = holy paladin / elemental, spirit+hit = shadow,
-- spirit+crit = balance, str/agi or AP = the melee set.
--
-- SKIPPED, and reported (never deleted):
--   - a second token for the same slot (Anmine's and Krast's spare shoulders)
--   - a token whose piece the bot already owns, equipped or in bags
--   - a token the bot's class can't use
--   - Bullwark: hand-geared, never touched by scripts (docs/bullwark-gear.md)
--   - anyone not in the ten or the 15 (the bench, ambient bots)
--
-- BEFORE RUNNING
--   1. Log out. systemctl stop hprv-worldserver
--   2. mysqldump --no-tablespaces --single-transaction acore_characters \
--        | gzip > /opt/hprv/backups/pre-tokens-$(date +%Y%m%d-%H%M%S).sql.gz
--      and check the tail reads "-- Dump completed".
-- AFTER: start, log in, then in raid chat
--   /ra equip upgrade     bots put on the new pieces if their weights agree
--   /ra maintenance       gems and enchants for the new sockets
-- (Not /ra maintenance with Bullwark in the raid as a bot: it would
--  overwrite his hand-picked gems.)
--
-- Re-running is safe: a redeemed token is no longer a token, so it is
-- simply not found again.

USE acore_characters;

-- Real tables, not TEMPORARY: MySQL can't open a temporary table twice in
-- one query (ERROR 1137). Created before the transaction because DDL
-- inside one commits it implicitly. Dropped at the end.
DROP TABLE IF EXISTS hprv_t4_spec;
CREATE TABLE hprv_t4_spec (name VARCHAR(12) PRIMARY KEY, itemset INT UNSIGNED NOT NULL);
INSERT INTO hprv_t4_spec VALUES
  -- the ten (Crumm: Death Knights have no TBC tier)
  ('Nathos',      624),  -- holy paladin       Justicar Raiment
  ('Krast',       631),  -- resto shaman       Cyclone Raiment
  ('Restofarian', 638),  -- resto druid        Malorne Raiment
  ('Dijito',      664),  -- shadow priest      Incarnate Regalia
  ('Izri',        648),  -- mage               Aldor Regalia
  ('Celerina',    645),  -- warlock            Voidheart
  ('Ilyna',       651),  -- hunter             Demon Stalker
  ('Anmine',      621),  -- rogue              Netherblade
  -- the 15
  ('Ararin',      625),  -- prot paladin       Justicar Armor
  ('Zaene',       626),  -- ret paladin        Justicar Battlegear
  ('Tanke',       638),  -- resto druid        Malorne Raiment
  ('Tengwe',      639),  -- balance druid      Malorne Regalia
  ('Dehme',       663),  -- disc priest        Incarnate Raiment
  ('Olidina',     663),  -- holy priest        Incarnate Raiment
  ('Irntifumm',   631),  -- resto shaman       Cyclone Raiment
  ('Sehjece',     632),  -- elemental shaman   Cyclone Regalia
  ('Fimur',       633),  -- enhancement shaman Cyclone Harness
  ('Gerina',      655),  -- arms warrior       Warbringer Battle-Gear
  ('Muhnun',      621),  -- rogue              Netherblade
  ('Fehmos',      651),  -- hunter             Demon Stalker
  ('Lomul',       648),  -- mage               Aldor Regalia
  ('Vestanza',    648),  -- mage               Aldor Regalia
  ('Grohtarty',   645);  -- warlock            Voidheart

-- Token entry -> the InventoryType(s) of the piece it buys. Tokens carry
-- InventoryType 0, so the slot is read off the token's name. Chest is 5,
-- or 20 for the robe-wearers' sets (Voidheart, Aldor, Incarnate).
DROP TABLE IF EXISTS hprv_t4_token;
CREATE TABLE hprv_t4_token (token INT UNSIGNED PRIMARY KEY, inv1 TINYINT UNSIGNED NOT NULL, inv2 TINYINT UNSIGNED NOT NULL);
INSERT INTO hprv_t4_token VALUES
  (29753, 5, 20), (29754, 5, 20), (29755, 5, 20),   -- Chestguard of the Fallen ...
  (29756, 10, 10), (29757, 10, 10), (29758, 10, 10), -- Gloves
  (29759, 1, 1), (29760, 1, 1), (29761, 1, 1),       -- Helm
  (29762, 3, 3), (29763, 3, 3), (29764, 3, 3),       -- Pauldrons
  (29765, 7, 7), (29766, 7, 7), (29767, 7, 7);       -- Leggings

-- Every token a roster bot holds, with its target piece and verdict.
DROP TABLE IF EXISTS hprv_t4_plan;
CREATE TABLE hprv_t4_plan AS
SELECT c.name, c.class, ii.guid AS item_guid, tok.entry AS token, tok.name AS token_name,
       pc.entry AS piece, pc.name AS piece_name, pc.MaxDurability AS durability,
       CAST(NULL AS CHAR(40)) AS verdict
  FROM character_inventory ci
  JOIN characters c       ON c.guid = ci.guid
  JOIN hprv_t4_spec s     ON s.name = c.name
  JOIN item_instance ii   ON ii.guid = ci.item
  JOIN hprv_t4_token t    ON t.token = ii.itemEntry
  JOIN acore_world.item_template tok ON tok.entry = t.token
  LEFT JOIN acore_world.item_template pc
         ON pc.itemset = s.itemset AND pc.InventoryType IN (t.inv1, t.inv2) AND pc.ItemLevel = 120;

UPDATE hprv_t4_plan SET verdict = 'class cannot use token'
 WHERE verdict IS NULL
   AND (SELECT AllowableClass FROM acore_world.item_template WHERE entry = token) & (1 << (class - 1)) = 0;
UPDATE hprv_t4_plan SET verdict = 'no piece found (check set table)'
 WHERE verdict IS NULL AND piece IS NULL;
UPDATE hprv_t4_plan p SET verdict = 'already owns the piece'
 WHERE verdict IS NULL
   AND EXISTS (SELECT 1 FROM character_inventory ci2
                 JOIN item_instance i2 ON i2.guid = ci2.item
                 JOIN characters c2 ON c2.guid = ci2.guid
                WHERE c2.name = p.name AND i2.itemEntry = p.piece);
-- Spare tokens: keep the lowest item guid per bot and piece, skip the rest.
UPDATE hprv_t4_plan p
  JOIN (SELECT name, piece, MIN(item_guid) AS keep FROM hprv_t4_plan WHERE verdict IS NULL GROUP BY name, piece) k
    ON k.name = p.name AND k.piece = p.piece
   SET p.verdict = 'spare: second token for this slot'
 WHERE p.verdict IS NULL AND p.item_guid <> k.keep;
UPDATE hprv_t4_plan SET verdict = 'REDEEM' WHERE verdict IS NULL;

START TRANSACTION;

-- Guards: a false condition raises ERROR 1242 and the transaction rolls
-- back on disconnect (same pattern as swap-standing-ten.sql).
SELECT IF(COUNT(*) = 0, 'ok: nobody online', (SELECT 1 UNION SELECT 2)) AS precheck_online
  FROM characters WHERE online = 1;
SELECT IF(COUNT(*) = 23, 'ok: all 23 names resolve', (SELECT 1 UNION SELECT 2)) AS precheck_names
  FROM hprv_t4_spec s JOIN characters c ON c.name = s.name;

-- The report: every token found, and what happens to it.
SELECT name, token_name, verdict, piece_name FROM hprv_t4_plan ORDER BY verdict <> 'REDEEM', name, token_name;

UPDATE item_instance ii
  JOIN hprv_t4_plan p ON p.item_guid = ii.guid AND p.verdict = 'REDEEM'
   SET ii.itemEntry  = p.piece,
       ii.durability = p.durability,
       ii.flags      = ii.flags | 1;   -- soulbound, as a bought tier piece is

SELECT IF(COUNT(*) = 0, 'ok: every REDEEM row changed', (SELECT 1 UNION SELECT 2)) AS postcheck
  FROM hprv_t4_plan p JOIN item_instance ii ON ii.guid = p.item_guid
 WHERE p.verdict = 'REDEEM' AND ii.itemEntry <> p.piece;

COMMIT;

DROP TABLE hprv_t4_plan;
DROP TABLE hprv_t4_token;
DROP TABLE hprv_t4_spec;

-- ROLLBACK: restore the pre-tokens dump of acore_characters.
