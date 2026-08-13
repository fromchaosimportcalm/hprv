-- HPRV — restore Ararin to crit-immunity
--
-- RUN WITH THE CHARACTER OFFLINE. `.playerbots bot remove Ararin` first,
-- or the in-memory copy overwrites this on the next save and it will look
-- like the change silently did nothing.
--
-- ---------------------------------------------------------------------
-- THE PROBLEM, AND WHY IT RECURS
--
-- 490 defence skill is crit-immunity against a level 73 boss.
--   skill = 350 (base at 70) + floor(defence_rating / 2.37)
-- so 490 needs 332 defence rating off equipped gear.
--
-- StatsWeightCalculator scores raw stats and has no concept of defence
-- skill or its cap, so every automated pass fills trinkets, neck and
-- shield with zero-defence pieces. Measured 2026-08-13: Ararin had
-- 300 rating (476 skill) equipped while carrying a 32-rating trinket in
-- his BAGS. He off-tanked Black Temple crittable.
--
-- This is not fixable by configuration and it comes back after any
-- init= pass. Re-run this file whenever that happens.
--
-- ---------------------------------------------------------------------
-- THE SWAP
--
--   trinket slot 12:  Argussian Compass (0 def)  ->  Brooch of the
--                     Immortal King (32 def, already in his bags)
--
--   The displaced compass goes to the BANK, not a bag. This matters:
--   bots re-equip from bags on their own scoring, which ignores defence,
--   so a competing item left in a bag will simply come back. Parking it
--   in the bank is the fix that holds.
--
--   300 - 0 + 32 = 332 rating -> 490 skill. Exactly the floor.
--
-- For margin, follow up with the two .additem lines at the bottom.
-- ---------------------------------------------------------------------

-- Verify he is offline. This MUST return 0 before you continue.
SELECT online AS must_be_zero
  FROM acore_characters.characters WHERE name = 'Ararin';

-- Park the zero-defence trinket in the first free bank slot (39-66).
UPDATE acore_characters.character_inventory i
  JOIN acore_characters.characters c ON c.guid = i.guid
   SET i.bag = 0, i.slot = 41
 WHERE c.name = 'Ararin' AND i.item = 24503;      -- Argussian Compass

-- Equip the defence trinket in the slot it just vacated.
UPDATE acore_characters.character_inventory i
  JOIN acore_characters.characters c ON c.guid = i.guid
   SET i.bag = 0, i.slot = 12
 WHERE c.name = 'Ararin' AND i.item = 22610;      -- Brooch of the Immortal King

-- ---------------------------------------------------------------------
-- VERIFY — expect 332 rating / 490 skill.
-- ---------------------------------------------------------------------
SELECT SUM(
    CASE WHEN t.stat_type1=12  THEN t.stat_value1  ELSE 0 END +
    CASE WHEN t.stat_type2=12  THEN t.stat_value2  ELSE 0 END +
    CASE WHEN t.stat_type3=12  THEN t.stat_value3  ELSE 0 END +
    CASE WHEN t.stat_type4=12  THEN t.stat_value4  ELSE 0 END +
    CASE WHEN t.stat_type5=12  THEN t.stat_value5  ELSE 0 END +
    CASE WHEN t.stat_type6=12  THEN t.stat_value6  ELSE 0 END +
    CASE WHEN t.stat_type7=12  THEN t.stat_value7  ELSE 0 END +
    CASE WHEN t.stat_type8=12  THEN t.stat_value8  ELSE 0 END +
    CASE WHEN t.stat_type9=12  THEN t.stat_value9  ELSE 0 END +
    CASE WHEN t.stat_type10=12 THEN t.stat_value10 ELSE 0 END) AS defence_rating,
  350 + FLOOR(SUM(
    CASE WHEN t.stat_type1=12  THEN t.stat_value1  ELSE 0 END +
    CASE WHEN t.stat_type2=12  THEN t.stat_value2  ELSE 0 END +
    CASE WHEN t.stat_type3=12  THEN t.stat_value3  ELSE 0 END +
    CASE WHEN t.stat_type4=12  THEN t.stat_value4  ELSE 0 END +
    CASE WHEN t.stat_type5=12  THEN t.stat_value5  ELSE 0 END +
    CASE WHEN t.stat_type6=12  THEN t.stat_value6  ELSE 0 END +
    CASE WHEN t.stat_type7=12  THEN t.stat_value7  ELSE 0 END +
    CASE WHEN t.stat_type8=12  THEN t.stat_value8  ELSE 0 END +
    CASE WHEN t.stat_type9=12  THEN t.stat_value9  ELSE 0 END +
    CASE WHEN t.stat_type10=12 THEN t.stat_value10 ELSE 0 END) / 2.37) AS defence_skill
FROM acore_characters.character_inventory i
JOIN acore_characters.item_instance ii ON ii.guid = i.item
JOIN acore_world.item_template t ON t.entry = ii.itemEntry
JOIN acore_characters.characters c ON c.guid = i.guid
WHERE c.name = 'Ararin' AND i.bag = 0 AND i.slot < 19;

-- ---------------------------------------------------------------------
-- MARGIN — in game, after re-adding him. Target Ararin, then:
--
--     .additem 32268      -- Myrmidon's Treads      ilvl 141, +30 def
--     .additem 32279      -- The Seeker's Wristguards ilvl 141, +21 def
--
-- He currently wears ilvl 115 boots and bracers carrying ZERO defence, so
-- these are large raw-stat upgrades as well as defence ones — which is
-- why he should auto-equip them despite the calculator ignoring defence.
-- That is the trick: beat the scorer on its own terms rather than fight
-- it. If he does not take them within a minute, place them by hand with
-- the same UPDATE pattern above (boots = slot 7, bracers = slot 8).
--
-- With all three: 383 rating -> 511 skill, a 21-point margin over the
-- floor instead of landing exactly on it.
--
-- Then `.save` before trusting roster-status.sh or hprv-spec.sh --show;
-- both read last-saved state.
-- ---------------------------------------------------------------------
