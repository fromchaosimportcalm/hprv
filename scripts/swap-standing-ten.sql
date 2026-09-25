-- HPRV — swap the standing ten to one-of-each-class (TODO item 1)
--
--   OUT  Ararin   prot paladin   101 -> 93 (RNDBOT92)   joins the 25
--   OUT  Tanke    resto druid    101 -> 99 (RNDBOT98)   joins the 25
--   IN   Crumm    blood DK        99 -> 101             off-tank
--   IN   Celerina destro warlock  98 -> 101             ranged
--
-- Account 101 stays at exactly 10 throughout: both leave before either
-- arrives (migrate-pool.sql SECTION 2). Old accounts come from
-- hprv_pool_migration_backup, not from memory.
--
-- BEFORE RUNNING
--   1. Log out. Then: systemctl stop hprv-worldserver
--      Characters must not be online (migrate-pool.sql, "BEFORE YOU RUN IT").
--   2. Dump all three schemas and check the tail reads "-- Dump completed":
--        mysqldump --single-transaction --databases \
--          acore_characters acore_auth acore_playerbots \
--          | gzip > /opt/hprv/backups/pre-swap-ten-$(date +%Y%m%d-%H%M%S).sql.gz
--
-- AFTER RUNNING — rule 1 is live until this is done
--   Crumm has NO playerbots_db_store row (the whole table was found empty
--   2026-09-26), so he logs in as a full taunting tank. First thing after
--   login, before any pull:
--       /w Crumm co -tank,-tank assist,+dps,+dps assist
--   then assert the row EXISTS (absence is not evidence of conversion):
--       SELECT s.value FROM acore_playerbots.playerbots_db_store s
--         JOIN acore_characters.characters c ON c.guid = s.guid
--        WHERE s.`key` = 'co' AND c.name = 'Crumm';
--   Any later init= pass (item 2) DELETES this row again —
--   PlayerbotFactory::Randomize() calls PlayerbotRepository::Reset().
--   Re-whisper after every gear pass.
--
--   Crumm and Celerina were never in Bullwark's group, so KeepAltsInGroup
--   has nothing to restore. Invite them: /invite Crumm, /invite Celerina.

-- Multi-table DELETE with aliases needs a default database (ERROR 1046
-- without it, caught in the dry run). Every table below is still fully
-- qualified; this only satisfies the alias resolver.
USE acore_characters;

START TRANSACTION;

-- Guards: a false condition raises ERROR 1242 ("Subquery returns more
-- than 1 row"), the client stops, and the open transaction rolls back on
-- disconnect. (1/0 would NOT work — in a SELECT it is NULL plus a warning.)
-- Refuse to run with anyone online.
SELECT IF(COUNT(*) = 0, 'ok: nobody online', (SELECT 1 UNION SELECT 2)) AS precheck_online
  FROM acore_characters.characters WHERE online = 1;

-- 1. The two leaving go back to the account they came from.
UPDATE acore_characters.characters c
  JOIN acore_characters.hprv_pool_migration_backup b ON b.guid = c.guid
   SET c.account = b.old_account
 WHERE c.name IN ('Ararin', 'Tanke') AND c.account = 101;

-- ...and out of the raid group. KeepAltsInGroup is own-account only, so
-- they would otherwise sit in it as offline members: 12 in a 10-man.
DELETE gm FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 WHERE c.name IN ('Ararin', 'Tanke');

-- 2. The two arriving. Their backup rows already record their home
--    accounts (98, 99), so rollback needs nothing new.
UPDATE acore_characters.characters
   SET account = 101
 WHERE name IN ('Crumm', 'Celerina');

-- Ambient bookkeeping must not exist for anything on 101 (migrate-pool.sql
-- SECTION 3). Expected to delete 0 rows — neither has any.
DELETE r FROM acore_playerbots.playerbots_random_bots r
  JOIN acore_characters.characters c ON c.guid = r.bot
 WHERE c.account = 101;

-- 3. Realm-select character counts, for every account touched.
UPDATE acore_auth.realmcharacters rc
   SET rc.numchars = (SELECT COUNT(*) FROM acore_characters.characters c
                       WHERE c.account = rc.acctid)
 WHERE rc.realmid = 1 AND rc.acctid IN (93, 98, 99, 101);

-- 4. Verify inside the transaction. Every line must read ok.
SELECT IF(COUNT(*) = 10, 'ok: 10 on account 101', (SELECT 1 UNION SELECT 2)) AS check_count
  FROM acore_characters.characters WHERE account = 101;

SELECT IF(COUNT(DISTINCT class) = 10, 'ok: one of each class', (SELECT 1 UNION SELECT 2)) AS check_classes
  FROM acore_characters.characters WHERE account = 101;

SELECT IF(COUNT(*) = 0, 'ok: all Horde', (SELECT 1 UNION SELECT 2)) AS check_faction
  FROM acore_characters.characters WHERE account = 101 AND race IN (1,3,4,7,11);

SELECT IF(COUNT(*) = 8, 'ok: 8 left in group', (SELECT 1 UNION SELECT 2)) AS check_group
  FROM acore_characters.group_member WHERE guid = 1;

SELECT name, class, level, account FROM acore_characters.characters
 WHERE account = 101 ORDER BY class;

COMMIT;

-- ROLLBACK — put all four back exactly as they were:
--   UPDATE acore_characters.characters SET account = 101 WHERE name IN ('Ararin','Tanke');
--   UPDATE acore_characters.characters c
--     JOIN acore_characters.hprv_pool_migration_backup b ON b.guid = c.guid
--      SET c.account = b.old_account
--    WHERE c.name IN ('Crumm','Celerina');
--   (group membership: re-invite Ararin and Tanke in game)
-- or restore the pre-swap dump.
