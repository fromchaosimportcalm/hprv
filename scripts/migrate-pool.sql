-- HPRV — migrate the 40-character pool onto CLINTON's account
--
-- NOT APPLIED. Review, then run it yourself. It is a live-DB UPDATE
-- across acore_characters / acore_auth / acore_playerbots, which the
-- project brief says to confirm before doing.
--
-- ---------------------------------------------------------------------
-- WHAT THIS DOES, AND WHY IT IS THE WHOLE DESIGN
--
-- Moving these characters to account 101 flips three independent gates at
-- once. All three were read out of the module source at this pin:
--
--   1. GEARABLE.       IsAddclassBot() falls through to
--      IsAccountType(accountId, 2), which is a plain
--      SELECT on playerbots_account_type. Insert one row for account 101
--      and every character on it becomes a legal target for
--      `.playerbots bot init=`. Nothing about this is prefix-based.
--
--   2. NEVER RE-GEARED. IsRandomBot() requires the account name to match
--      the 'rndbot%' prefix (randomBotAccounts is built by enumerating
--      those names at startup). "CLINTON" never matches, so the ambient
--      random system can never re-roll these characters' gear or spec.
--      This is structural, not a setting — nothing to leave switched on.
--
--   3. AUTO-LOGIN.     BotAutologin runs
--      `SELECT name FROM characters WHERE account = <the logging-in
--      player's account>` and adds every result. Own-account only. This
--      is the reason the pool lives on 101 rather than on dedicated
--      HPRVPOOL* accounts, which would have worked for (1) and (2) alone.
--
-- ---------------------------------------------------------------------
-- BEFORE YOU RUN IT
--
--   1. Stop the world server.  systemctl stop hprv-worldserver
--      (the unit is hprv-worldserver, not hprv-world; hprv-authserver
--       can stay up, it just leaves people at realm select)
--      Characters must not be online. Moving an online character's
--      account out from under it is asking for a stale in-memory write.
--   2. Back up.  mysqldump acore_characters acore_auth acore_playerbots
--   3. Make the config changes in docs/pool.md FIRST — in particular
--      CharactersPerRealm, or the client will not show 42 characters.
--   4. Run the SMOKE TEST section alone. Start the server, log in, verify
--      the two test characters auto-login and can be geared. Only then
--      run the rest.
--
-- Rollback is in the last section.
-- ---------------------------------------------------------------------

-- =====================================================================
-- SECTION 0 — record the current state so rollback is possible
-- =====================================================================

CREATE TABLE IF NOT EXISTS acore_characters.hprv_pool_migration_backup (
    guid          INT UNSIGNED NOT NULL PRIMARY KEY,
    name          VARCHAR(12)  NOT NULL,
    old_account   INT UNSIGNED NOT NULL,
    migrated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- =====================================================================
-- SECTION 1 — SMOKE TEST (two characters only)
--
-- Run this, restart, and confirm end to end before doing the other 37.
-- Netohje is the geared prot warrior; Gerina is a level-1 draw, so
-- between them they exercise both the "already geared" and the
-- "needs a full init= pass" paths.
-- =====================================================================

INSERT INTO acore_characters.hprv_pool_migration_backup (guid, name, old_account)
SELECT guid, name, account FROM acore_characters.characters
 WHERE name IN ('Netohje','Gerina')
 ON DUPLICATE KEY UPDATE name = VALUES(name);

-- The account_type row is what makes them gearable. ON DUPLICATE so this
-- whole file stays re-runnable.
INSERT INTO acore_playerbots.playerbots_account_type (account_id, account_type, assignment_date)
VALUES (101, 2, NOW())
ON DUPLICATE KEY UPDATE account_type = 2;

UPDATE acore_characters.characters
   SET account = 101
 WHERE name IN ('Netohje','Gerina');

-- Drop their random-bot bookkeeping. These rows describe a character the
-- ambient system used to manage; it no longer does, and stale rows here
-- are how a "why is it re-randomising" bug starts.
DELETE r FROM acore_playerbots.playerbots_random_bots r
  JOIN acore_characters.characters c ON c.guid = r.bot
 WHERE c.account = 101;

-- Keep the realm character count honest (cosmetic, but it drives the
-- character-count shown at realm select).
UPDATE acore_auth.realmcharacters
   SET numchars = (SELECT COUNT(*) FROM acore_characters.characters WHERE account = 101)
 WHERE acctid = 101 AND realmid = 1;

-- VERIFY, then stop and go test:
--   SELECT name, level, account FROM acore_characters.characters WHERE account=101;
--   SELECT * FROM acore_playerbots.playerbots_account_type WHERE account_id=101;

-- =====================================================================
-- SECTION 2 — the remaining 37
--
-- Restofarian is already on 101 and is not listed. Ralda is deliberately
-- NOT here: the pool caps death knights at 2 and keeps the two converted
-- blood off-tanks (Crumm, Rechiw). He stays a pool character on his
-- rndbot account, available if you ever want him back.
-- =====================================================================

INSERT INTO acore_characters.hprv_pool_migration_backup (guid, name, old_account)
SELECT guid, name, account FROM acore_characters.characters
 WHERE name IN (
    'Ararin','Nathos','Zaene','Daedana','Delatasia',
    'Tanke','Mutlie','Tengwe','Caugotsa',
    'Krast','Irntifumm','Sehjece','Fimur','Cirtiglaz',
    'Dehme','Olidina','Dijito','Maroman',
    'Grahlukk','Lonhwa',
    'Izri','Lomul','Vestanza','Eriona',
    'Celerina','Grohtarty','Alais','Bemarlarin',
    'Ilyna','Fehmos','Drusun','Gelanlan',
    'Anmine','Muhnun','Tyrnan',
    'Crumm','Rechiw'
 )
 ON DUPLICATE KEY UPDATE name = VALUES(name);

UPDATE acore_characters.characters
   SET account = 101
 WHERE name IN (
    'Ararin','Nathos','Zaene','Daedana','Delatasia',
    'Tanke','Mutlie','Tengwe','Caugotsa',
    'Krast','Irntifumm','Sehjece','Fimur','Cirtiglaz',
    'Dehme','Olidina','Dijito','Maroman',
    'Grahlukk','Lonhwa',
    'Izri','Lomul','Vestanza','Eriona',
    'Celerina','Grohtarty','Alais','Bemarlarin',
    'Ilyna','Fehmos','Drusun','Gelanlan',
    'Anmine','Muhnun','Tyrnan',
    'Crumm','Rechiw'
 );

DELETE r FROM acore_playerbots.playerbots_random_bots r
  JOIN acore_characters.characters c ON c.guid = r.bot
 WHERE c.account = 101;

UPDATE acore_auth.realmcharacters
   SET numchars = (SELECT COUNT(*) FROM acore_characters.characters WHERE account = 101)
 WHERE acctid = 101 AND realmid = 1;

-- =====================================================================
-- SECTION 3 — verification. All of these should hold afterwards.
-- =====================================================================

-- Expect 42: Bullwark + Restofarian + 40 pool characters.
-- SELECT COUNT(*) FROM acore_characters.characters WHERE account = 101;

-- Expect exactly one row, account_type = 2.
-- SELECT * FROM acore_playerbots.playerbots_account_type WHERE account_id = 101;

-- Expect 0. Any row here is a character the ambient system still thinks
-- it owns.
-- SELECT COUNT(*) FROM acore_playerbots.playerbots_random_bots r
--   JOIN acore_characters.characters c ON c.guid = r.bot WHERE c.account = 101;

-- Expect 0. Every pool character must be Horde to group with Bullwark
-- (Tauren, race 6). Alliance races are 1,3,4,7,11.
-- SELECT name, race FROM acore_characters.characters
--  WHERE account = 101 AND race IN (1,3,4,7,11);

-- Expect the 10 level-1 draws; everything else should be 70.
-- SELECT name, level FROM acore_characters.characters
--  WHERE account = 101 AND level < 70 ORDER BY level;

-- =====================================================================
-- SECTION 4 — ROLLBACK
--
-- Puts every migrated character back on the account it came from. Safe to
-- run at any point; it only touches rows the backup table knows about.
-- =====================================================================

-- UPDATE acore_characters.characters c
--   JOIN acore_characters.hprv_pool_migration_backup b ON b.guid = c.guid
--    SET c.account = b.old_account;
--
-- DELETE FROM acore_playerbots.playerbots_account_type WHERE account_id = 101;
--
-- UPDATE acore_auth.realmcharacters
--    SET numchars = (SELECT COUNT(*) FROM acore_characters.characters WHERE account = 101)
--  WHERE acctid = 101 AND realmid = 1;
--
-- Note: rollback does NOT restore playerbots_random_bots rows. Those are
-- ambient-system bookkeeping and the system rebuilds them on its own for
-- any character it still owns. Nothing is lost that matters.
