-- HPRV — put Ararin over the 490 defence floor (docs/tank-defence.md)
--
-- RUN WITH THE SERVER STOPPED. Two reasons:
--   * the in-memory character is written back over any change made while
--     he is loaded, and it will look like this silently did nothing
--   * new item guids are taken from MAX(guid); a running server allocates
--     from its own counter and could collide
--
-- Re-run after EVERY init= pass on Ararin: the pass re-rolls his gear,
-- and StatsWeightCalculator ignores defence, so it lands him back under.
-- It is idempotent: a slot already holding the wanted item is skipped,
-- and the enchants are simply set again.
--
-- ---------------------------------------------------------------------
-- WHAT IT DOES (measured 2026-09-26, after the item 2 pass)
--
-- He was at 251 rating (220 items + 31 enchants) -> 455 skill. Four slots
-- held pure-DPS pieces with zero defence. Each is replaced with a new item
-- written straight into the equip slot, and the displaced piece is parked
-- in the BANK. That matters: bots re-equip from their BAGS on their own
-- scoring, which ignores defence, so anything left in a bag comes back.
-- The bank is invisible to that scan.
--
--   slot 5  waist    Girdle of Valorous Deeds     29253  +24 def  +37 sta
--   slot 7  feet     Boots of the Righteous Path  29254  +23 def  +34 sta
--   slot 8  wrists   Bracers of Dignity           29252  +21 def  +30 sta
--   slot 12 trinket  Adamantine Figurine          27891  +32 def
--
-- Then two permanent enchants (enchant id from SpellItemEnchantment.dbc):
--
--   slot 4  chest    Enchant Chest - Defense        1951  +16 def  (replaces +150 health)
--   slot 8  wrists   Enchant Bracer - Major Defense 2648  +12 def
--
-- Expected: 251 + 100 + 28 = 379 rating -> 509 skill.
-- ---------------------------------------------------------------------

USE acore_characters;

START TRANSACTION;

-- Guards: a false condition raises ERROR 1242 ("Subquery returns more
-- than 1 row"), the client stops, and the open transaction rolls back on
-- disconnect. Same pattern as swap-standing-ten.sql.
SELECT IF(COUNT(*) = 0, 'ok: nobody online', (SELECT 1 UNION SELECT 2)) AS precheck_online
  FROM acore_characters.characters WHERE online = 1;

SET @g = (SELECT guid FROM acore_characters.characters WHERE name = 'Ararin');
SELECT IF(@g IS NOT NULL, 'ok: Ararin found', (SELECT 1 UNION SELECT 2)) AS precheck_char;

SET @next = (SELECT MAX(guid) FROM acore_characters.item_instance);
SET @zero = REPEAT('0 ', 36);   -- 12 enchant slots x (id duration charges)

-- ---------------------------------------------------------------------
-- One block per slot. Identical apart from the first SET line.
-- ---------------------------------------------------------------------

-- Waist
SET @slot = 5, @want = 29253, @old = NULL, @oldentry = NULL, @bank = NULL;
SELECT i.item, ii.itemEntry INTO @old, @oldentry
  FROM acore_characters.character_inventory i
  JOIN acore_characters.item_instance ii ON ii.guid = i.item
 WHERE i.guid = @g AND i.bag = 0 AND i.slot = @slot;
SET @do = (@oldentry IS NULL OR @oldentry <> @want);
WITH RECURSIVE n(x) AS (SELECT 39 UNION ALL SELECT x + 1 FROM n WHERE x < 66)
SELECT MIN(x) INTO @bank FROM n
 WHERE x NOT IN (SELECT slot FROM acore_characters.character_inventory WHERE guid = @g AND bag = 0);
SELECT IF(NOT @do OR @old IS NULL OR @bank IS NOT NULL, 'ok: waist', (SELECT 1 UNION SELECT 2)) AS check_bank_space;
UPDATE acore_characters.character_inventory SET slot = @bank WHERE item = @old AND @do;
SET @next = @next + 1;
INSERT INTO acore_characters.item_instance
       (guid, itemEntry, owner_guid, creatorGuid, giftCreatorGuid, count, duration, charges, flags, enchantments, randomPropertyId, durability, playedTime, text)
SELECT @next, @want, @g, 0, 0, 1, 0, '0 0 0 0 0 ', 1, @zero, 0, t.MaxDurability, 0, NULL
  FROM acore_world.item_template t WHERE t.entry = @want AND @do;
INSERT INTO acore_characters.character_inventory (guid, bag, slot, item)
SELECT @g, 0, @slot, @next FROM DUAL WHERE @do;

-- Feet
SET @slot = 7, @want = 29254, @old = NULL, @oldentry = NULL, @bank = NULL;
SELECT i.item, ii.itemEntry INTO @old, @oldentry
  FROM acore_characters.character_inventory i
  JOIN acore_characters.item_instance ii ON ii.guid = i.item
 WHERE i.guid = @g AND i.bag = 0 AND i.slot = @slot;
SET @do = (@oldentry IS NULL OR @oldentry <> @want);
WITH RECURSIVE n(x) AS (SELECT 39 UNION ALL SELECT x + 1 FROM n WHERE x < 66)
SELECT MIN(x) INTO @bank FROM n
 WHERE x NOT IN (SELECT slot FROM acore_characters.character_inventory WHERE guid = @g AND bag = 0);
SELECT IF(NOT @do OR @old IS NULL OR @bank IS NOT NULL, 'ok: feet', (SELECT 1 UNION SELECT 2)) AS check_bank_space;
UPDATE acore_characters.character_inventory SET slot = @bank WHERE item = @old AND @do;
SET @next = @next + 1;
INSERT INTO acore_characters.item_instance
       (guid, itemEntry, owner_guid, creatorGuid, giftCreatorGuid, count, duration, charges, flags, enchantments, randomPropertyId, durability, playedTime, text)
SELECT @next, @want, @g, 0, 0, 1, 0, '0 0 0 0 0 ', 1, @zero, 0, t.MaxDurability, 0, NULL
  FROM acore_world.item_template t WHERE t.entry = @want AND @do;
INSERT INTO acore_characters.character_inventory (guid, bag, slot, item)
SELECT @g, 0, @slot, @next FROM DUAL WHERE @do;

-- Wrists
SET @slot = 8, @want = 29252, @old = NULL, @oldentry = NULL, @bank = NULL;
SELECT i.item, ii.itemEntry INTO @old, @oldentry
  FROM acore_characters.character_inventory i
  JOIN acore_characters.item_instance ii ON ii.guid = i.item
 WHERE i.guid = @g AND i.bag = 0 AND i.slot = @slot;
SET @do = (@oldentry IS NULL OR @oldentry <> @want);
WITH RECURSIVE n(x) AS (SELECT 39 UNION ALL SELECT x + 1 FROM n WHERE x < 66)
SELECT MIN(x) INTO @bank FROM n
 WHERE x NOT IN (SELECT slot FROM acore_characters.character_inventory WHERE guid = @g AND bag = 0);
SELECT IF(NOT @do OR @old IS NULL OR @bank IS NOT NULL, 'ok: wrists', (SELECT 1 UNION SELECT 2)) AS check_bank_space;
UPDATE acore_characters.character_inventory SET slot = @bank WHERE item = @old AND @do;
SET @next = @next + 1;
INSERT INTO acore_characters.item_instance
       (guid, itemEntry, owner_guid, creatorGuid, giftCreatorGuid, count, duration, charges, flags, enchantments, randomPropertyId, durability, playedTime, text)
SELECT @next, @want, @g, 0, 0, 1, 0, '0 0 0 0 0 ', 1, @zero, 0, t.MaxDurability, 0, NULL
  FROM acore_world.item_template t WHERE t.entry = @want AND @do;
INSERT INTO acore_characters.character_inventory (guid, bag, slot, item)
SELECT @g, 0, @slot, @next FROM DUAL WHERE @do;

-- Trinket (the first slot, 12)
SET @slot = 12, @want = 27891, @old = NULL, @oldentry = NULL, @bank = NULL;
SELECT i.item, ii.itemEntry INTO @old, @oldentry
  FROM acore_characters.character_inventory i
  JOIN acore_characters.item_instance ii ON ii.guid = i.item
 WHERE i.guid = @g AND i.bag = 0 AND i.slot = @slot;
SET @do = (@oldentry IS NULL OR @oldentry <> @want);
WITH RECURSIVE n(x) AS (SELECT 39 UNION ALL SELECT x + 1 FROM n WHERE x < 66)
SELECT MIN(x) INTO @bank FROM n
 WHERE x NOT IN (SELECT slot FROM acore_characters.character_inventory WHERE guid = @g AND bag = 0);
SELECT IF(NOT @do OR @old IS NULL OR @bank IS NOT NULL, 'ok: trinket', (SELECT 1 UNION SELECT 2)) AS check_bank_space;
UPDATE acore_characters.character_inventory SET slot = @bank WHERE item = @old AND @do;
SET @next = @next + 1;
INSERT INTO acore_characters.item_instance
       (guid, itemEntry, owner_guid, creatorGuid, giftCreatorGuid, count, duration, charges, flags, enchantments, randomPropertyId, durability, playedTime, text)
SELECT @next, @want, @g, 0, 0, 1, 0, '0 0 0 0 0 ', 1, @zero, 0, t.MaxDurability, 0, NULL
  FROM acore_world.item_template t WHERE t.entry = @want AND @do;
INSERT INTO acore_characters.character_inventory (guid, bag, slot, item)
SELECT @g, 0, @slot, @next FROM DUAL WHERE @do;

-- ---------------------------------------------------------------------
-- Permanent enchants: replace the first token (slot 0's enchant id).
-- ---------------------------------------------------------------------
UPDATE acore_characters.item_instance ii
  JOIN acore_characters.character_inventory i ON i.item = ii.guid
   SET ii.enchantments = CONCAT('1951', SUBSTRING(ii.enchantments, LOCATE(' ', ii.enchantments)))
 WHERE i.guid = @g AND i.bag = 0 AND i.slot = 4;      -- chest: Enchant Chest - Defense

UPDATE acore_characters.item_instance ii
  JOIN acore_characters.character_inventory i ON i.item = ii.guid
   SET ii.enchantments = CONCAT('2648', SUBSTRING(ii.enchantments, LOCATE(' ', ii.enchantments)))
 WHERE i.guid = @g AND i.bag = 0 AND i.slot = 8;      -- wrists: Enchant Bracer - Major Defense

-- ---------------------------------------------------------------------
-- Verify inside the transaction. Every line must read ok.
-- ---------------------------------------------------------------------
SELECT IF(COUNT(*) = 4, 'ok: four defence pieces equipped', (SELECT 1 UNION SELECT 2)) AS check_items
  FROM acore_characters.character_inventory i
  JOIN acore_characters.item_instance ii ON ii.guid = i.item
 WHERE i.guid = @g AND i.bag = 0
   AND ((i.slot = 5 AND ii.itemEntry = 29253) OR (i.slot = 7 AND ii.itemEntry = 29254)
     OR (i.slot = 8 AND ii.itemEntry = 29252) OR (i.slot = 12 AND ii.itemEntry = 27891));

SELECT IF(COUNT(*) = 2, 'ok: both enchants set', (SELECT 1 UNION SELECT 2)) AS check_enchants
  FROM acore_characters.character_inventory i
  JOIN acore_characters.item_instance ii ON ii.guid = i.item
 WHERE i.guid = @g AND i.bag = 0
   AND ((i.slot = 4 AND ii.enchantments LIKE '1951 %') OR (i.slot = 8 AND ii.enchantments LIKE '2648 %'));

SELECT i.slot, ii.itemEntry, t.name, SUBSTRING_INDEX(ii.enchantments, ' ', 1) AS perm_enchant
  FROM acore_characters.character_inventory i
  JOIN acore_characters.item_instance ii ON ii.guid = i.item
  JOIN acore_world.item_template t ON t.entry = ii.itemEntry
 WHERE i.guid = @g AND i.bag = 0 AND (i.slot IN (4, 5, 7, 8, 12) OR i.slot BETWEEN 39 AND 66)
 ORDER BY i.slot;

COMMIT;

-- Then, still with the server stopped:
--     /opt/hprv/scripts/hprv-spec.sh Ararin --show     # expect defence 509
-- It counts enchants and gems now (defence.conf), so it is the right check.
