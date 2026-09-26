-- HPRV — make the weapon vendor's stock free (optional)
--
-- The one change in this set to STOCK rows: BuyPrice = 0 on exactly the
-- 95 items weapon-vendor.sql lists. No stock vendor sells any of them,
-- so nothing else changes in game. SellPrice, a separate column, is left
-- alone. Split out of weapon-vendor.sql on 2026-09-26 so a server can
-- take the vendor without the price change.
--
-- Needs a worldserver restart: there is no `.reload item_template` at
-- this pin. Undo with weapon-vendor-revert-prices.sql. Idempotent.
-- ---------------------------------------------------------------------

UPDATE `item_template` SET `BuyPrice` = 0 WHERE `entry` IN (
  28767, 39769, 28773, 28794, 28772, 28522, 28657, 28771, 28800, 28774,
  28729, 28749, 28802, 28604, 28633, 28658, 28782, 28524, 28768, 28770,
  28659, 28826, 28673, 28783, 28525, 28603, 28728, 28734, 28781, 28606,
  28611, 28754, 28825, 29458, 28568, 28523, 29924, 30105, 29949, 29996,
  30108, 30090, 30082, 30095, 29993, 29981, 30021, 29988, 29948, 32944,
  29962, 30103, 30025, 29982, 30080, 29923, 30049, 30051, 30023, 32236,
  32254, 32348, 30906, 32336, 32325, 32262, 32943, 34009, 32500, 32248,
  32369, 30910, 32837, 32838, 30902, 32344, 30908, 32374, 32945, 32946,
  32237, 32269, 32471, 32326, 32253, 32343, 32361, 30911, 32255, 34011,
  30909, 32375, 32368, 32257, 32330);
