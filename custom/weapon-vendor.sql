-- HPRV — raid weapon vendor (SQL only)
--
-- A fourth vendor beside the tier vendors in Orgrimmar, selling the
-- raid-drop weapons, shields, held off-hands and relics (idols, totems,
-- librams) of the Tier 4 / 5 / 6 raids, free.
--
-- ---------------------------------------------------------------------
-- WHICH ITEMS
--
-- Every epic weapon / shield / off-hand / relic of ilvl >= 115 that the
-- stock loot tables drop in:
--   T4  Karazhan, Gruul's Lair, Magtheridon's Lair   (36 items)
--   T5  Serpentshrine Cavern, Tempest Keep           (23 items)
--   T6  Mount Hyjal, Black Temple                    (36 items)
-- 95 in all, under the 150-item vendor-window cap, so one NPC holds all
-- three tiers. Derived 2026-09-25 by walking creature_loot_template and
-- gameobject_loot_template (following reference_loot_template) for
-- every spawn on those maps; the list is written out below rather than
-- queried at apply time so it is reviewable and stable. Zul'Aman and
-- Sunwell are deliberately out: neither is a tier raid.
--
-- PRICE — NOT IN THIS FILE
--
-- Unlike the tier pieces, these carry a gold BuyPrice, and a vendor
-- charges item_template.BuyPrice. On its own this file sells them at
-- stock prices. Making them free is the one change to stock rows in
-- this set, so it has its own file: weapon-vendor-free-prices.sql
-- (applied on HPRV), undone by weapon-vendor-revert-prices.sql.
--
-- IDS / RESTART
--
-- Entry and spawn guid 9100004. New entry = one worldserver restart.
-- Afterwards, list changes are live via `.reload npc_vendor`. Price
-- changes are not: there is no `.reload item_template` at this pin
-- (checked in the command table), so a BuyPrice edit takes a restart.
-- Idempotent.
-- ---------------------------------------------------------------------

SET @NPC := 9100004;

DELETE FROM `creature_template`       WHERE `entry`      = @NPC;
DELETE FROM `creature_template_model` WHERE `CreatureID` = @NPC;

INSERT INTO `creature_template`
  (`entry`, `name`, `subname`, `minlevel`, `maxlevel`, `exp`,
   `faction`, `npcflag`, `unit_class`, `unit_flags`, `type`, `HealthModifier`, `VerifiedBuild`)
VALUES
  (@NPC, 'Torvek Ashforge', 'Raid Weapons', 80, 80, 2, 35, 128, 1, 2, 7, 1, 0);

INSERT INTO `creature_template_model`
  (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`)
VALUES
  (@NPC, 0, 24730, 1, 1, 0);   -- Anwehu, Weapons & Armorsmith (Shattrath)

-- ---------------------------------------------------------------------
-- Stock list, grouped by tier, then weapon type.
-- ---------------------------------------------------------------------

DELETE FROM `npc_vendor` WHERE `entry` = @NPC;

INSERT INTO `npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`, `VerifiedBuild`)
VALUES
  -- Tier 4
  (@NPC,   1,  28767, 0, 0, 0, 0),   -- ilvl 125  The Decapitator  (Karazhan)
  (@NPC,   2,  39769, 0, 0, 0, 0),   -- ilvl 115  Arcanite Ripper  (Karazhan)
  (@NPC,   3,  28773, 0, 0, 0, 0),   -- ilvl 125  Gorehowl  (Karazhan)
  (@NPC,   4,  28794, 0, 0, 0, 0),   -- ilvl 125  Axe of the Gronn Lords  (Gruul's Lair)
  (@NPC,   5,  28772, 0, 0, 0, 0),   -- ilvl 125  Sunfury Bow of the Phoenix  (Karazhan)
  (@NPC,   6,  28522, 0, 0, 0, 0),   -- ilvl 115  Shard of the Virtuous  (Karazhan)
  (@NPC,   7,  28657, 0, 0, 0, 0),   -- ilvl 115  Fool's Bane  (Karazhan)
  (@NPC,   8,  28771, 0, 0, 0, 0),   -- ilvl 125  Light's Justice  (Karazhan)
  (@NPC,   9,  28800, 0, 0, 0, 0),   -- ilvl 125  Hammer of the Naaru  (Gruul's Lair)
  (@NPC,  10,  28774, 0, 0, 0, 0),   -- ilvl 125  Glaive of the Pit  (Magtheridon's Lair)
  (@NPC,  11,  28729, 0, 0, 0, 0),   -- ilvl 115  Spiteblade  (Karazhan)
  (@NPC,  12,  28749, 0, 0, 0, 0),   -- ilvl 115  King's Defender  (Karazhan)
  (@NPC,  13,  28802, 0, 0, 0, 0),   -- ilvl 125  Bloodmaw Magus-Blade  (Gruul's Lair)
  (@NPC,  14,  28604, 0, 0, 0, 0),   -- ilvl 115  Nightstaff of the Everliving  (Karazhan)
  (@NPC,  15,  28633, 0, 0, 0, 0),   -- ilvl 115  Staff of Infinite Mysteries  (Karazhan)
  (@NPC,  16,  28658, 0, 0, 0, 0),   -- ilvl 115  Terestian's Stranglestaff  (Karazhan)
  (@NPC,  17,  28782, 0, 0, 0, 0),   -- ilvl 125  Crystalheart Pulse-Staff  (Magtheridon's Lair)
  (@NPC,  18,  28524, 0, 0, 0, 0),   -- ilvl 115  Emerald Ripper  (Karazhan)
  (@NPC,  19,  28768, 0, 0, 0, 0),   -- ilvl 125  Malchazeen  (Karazhan)
  (@NPC,  20,  28770, 0, 0, 0, 0),   -- ilvl 125  Nathrezim Mindblade  (Karazhan)
  (@NPC,  21,  28659, 0, 0, 0, 0),   -- ilvl 115  Xavian Stiletto  (Karazhan)
  (@NPC,  22,  28826, 0, 0, 0, 0),   -- ilvl 125  Shuriken of Negation  (Gruul's Lair)
  (@NPC,  23,  28673, 0, 0, 0, 0),   -- ilvl 115  Tirisfal Wand of Ascendancy  (Karazhan)
  (@NPC,  24,  28783, 0, 0, 0, 0),   -- ilvl 125  Eredar Wand of Obliteration  (Magtheridon's Lair)
  (@NPC,  25,  28525, 0, 0, 0, 0),   -- ilvl 115  Signet of Unshakable Faith  (Karazhan)
  (@NPC,  26,  28603, 0, 0, 0, 0),   -- ilvl 115  Talisman of Nightbane  (Karazhan)
  (@NPC,  27,  28728, 0, 0, 0, 0),   -- ilvl 115  Aran's Soothing Sapphire  (Karazhan)
  (@NPC,  28,  28734, 0, 0, 0, 0),   -- ilvl 115  Jewel of Infinite Possibilities  (Karazhan)
  (@NPC,  29,  28781, 0, 0, 0, 0),   -- ilvl 125  Karaborian Talisman  (Magtheridon's Lair)
  (@NPC,  30,  28606, 0, 0, 0, 0),   -- ilvl 115  Shield of Impenetrable Darkness  (Karazhan)
  (@NPC,  31,  28611, 0, 0, 0, 0),   -- ilvl 115  Dragonheart Flameshield  (Karazhan)
  (@NPC,  32,  28754, 0, 0, 0, 0),   -- ilvl 115  Triptych Shield of the Ancients  (Karazhan)
  (@NPC,  33,  28825, 0, 0, 0, 0),   -- ilvl 125  Aldori Legacy Defender  (Gruul's Lair)
  (@NPC,  34,  29458, 0, 0, 0, 0),   -- ilvl 125  Aegis of the Vindicator  (Magtheridon's Lair)
  (@NPC,  35,  28568, 0, 0, 0, 0),   -- ilvl 115  Idol of the Avian Heart  (Karazhan)
  (@NPC,  36,  28523, 0, 0, 0, 0),   -- ilvl 115  Totem of Healing Rains  (Karazhan)
  -- Tier 5
  (@NPC,  37,  29924, 0, 0, 0, 0),   -- ilvl 134  Netherbane  (Tempest Keep)
  (@NPC,  38,  30105, 0, 0, 0, 0),   -- ilvl 141  Serpent Spine Longbow  (SSC)
  (@NPC,  39,  29949, 0, 0, 0, 0),   -- ilvl 134  Arcanite Steam-Pistol  (Tempest Keep)
  (@NPC,  40,  29996, 0, 0, 0, 0),   -- ilvl 141  Rod of the Sun King  (Tempest Keep)
  (@NPC,  41,  30108, 0, 0, 0, 0),   -- ilvl 141  Lightfathom Scepter  (SSC)
  (@NPC,  42,  30090, 0, 0, 0, 0),   -- ilvl 134  World Breaker  (SSC)
  (@NPC,  43,  30082, 0, 0, 0, 0),   -- ilvl 134  Talon of Azshara  (SSC)
  (@NPC,  44,  30095, 0, 0, 0, 0),   -- ilvl 134  Fang of the Leviathan  (SSC)
  (@NPC,  45,  29993, 0, 0, 0, 0),   -- ilvl 141  Twinblade of the Phoenix  (Tempest Keep)
  (@NPC,  46,  29981, 0, 0, 0, 0),   -- ilvl 134  Ethereum Life-Staff  (Tempest Keep)
  (@NPC,  47,  30021, 0, 0, 0, 0),   -- ilvl 134  Wildfury Greatstaff  (SSC)
  (@NPC,  48,  29988, 0, 0, 0, 0),   -- ilvl 141  The Nexus Key  (Tempest Keep)
  (@NPC,  49,  29948, 0, 0, 0, 0),   -- ilvl 134  Claw of the Phoenix  (Tempest Keep)
  (@NPC,  50,  32944, 0, 0, 0, 0),   -- ilvl 134  Talon of the Phoenix  (Tempest Keep)
  (@NPC,  51,  29962, 0, 0, 0, 0),   -- ilvl 134  Heartrazor  (Tempest Keep)
  (@NPC,  52,  30103, 0, 0, 0, 0),   -- ilvl 141  Fang of Vashj  (SSC)
  (@NPC,  53,  30025, 0, 0, 0, 0),   -- ilvl 134  Serpentshrine Shuriken  (SSC)
  (@NPC,  54,  29982, 0, 0, 0, 0),   -- ilvl 134  Wand of the Forgotten Star  (Tempest Keep)
  (@NPC,  55,  30080, 0, 0, 0, 0),   -- ilvl 134  Luminescent Rod of the Naaru  (SSC)
  (@NPC,  56,  29923, 0, 0, 0, 0),   -- ilvl 128  Talisman of the Sun King  (Tempest Keep)
  (@NPC,  57,  30049, 0, 0, 0, 0),   -- ilvl 128  Fathomstone  (SSC)
  (@NPC,  58,  30051, 0, 0, 0, 0),   -- ilvl 128  Idol of the Crescent Goddess  (SSC)
  (@NPC,  59,  30023, 0, 0, 0, 0),   -- ilvl 128  Totem of the Maelstrom  (SSC)
  -- Tier 6
  (@NPC,  60,  32236, 0, 0, 0, 0),   -- ilvl 141  Rising Tide  (Black Temple)
  (@NPC,  61,  32254, 0, 0, 0, 0),   -- ilvl 141  The Brutalizer  (Black Temple)
  (@NPC,  62,  32348, 0, 0, 0, 0),   -- ilvl 141  Soul Cleaver  (Black Temple)
  (@NPC,  63,  30906, 0, 0, 0, 0),   -- ilvl 151  Bristleblitz Striker  (Hyjal)
  (@NPC,  64,  32336, 0, 0, 0, 0),   -- ilvl 151  Black Bow of the Betrayer  (Black Temple)
  (@NPC,  65,  32325, 0, 0, 0, 0),   -- ilvl 141  Rifle of the Stoic Guardian  (Black Temple)
  (@NPC,  66,  32262, 0, 0, 0, 0),   -- ilvl 141  Syphon of the Nathrezim  (Black Temple)
  (@NPC,  67,  32943, 0, 0, 0, 0),   -- ilvl 141  Swiftsteel Bludgeon  (Black Temple)
  (@NPC,  68,  34009, 0, 0, 0, 0),   -- ilvl 141  Hammer of Judgement  (Hyjal)
  (@NPC,  69,  32500, 0, 0, 0, 0),   -- ilvl 151  Crystal Spire of Karabor  (Black Temple)
  (@NPC,  70,  32248, 0, 0, 0, 0),   -- ilvl 141  Halberd of Desolation  (Black Temple)
  (@NPC,  71,  32369, 0, 0, 0, 0),   -- ilvl 141  Blade of Savagery  (Black Temple)
  (@NPC,  72,  30910, 0, 0, 0, 0),   -- ilvl 151  Tempest of Chaos  (Hyjal)
  (@NPC,  73,  32837, 0, 0, 0, 0),   -- ilvl 156  Warglaive of Azzinoth  (Black Temple)
  (@NPC,  74,  32838, 0, 0, 0, 0),   -- ilvl 156  Warglaive of Azzinoth  (Black Temple)
  (@NPC,  75,  30902, 0, 0, 0, 0),   -- ilvl 151  Cataclysm's Edge  (Hyjal)
  (@NPC,  76,  32344, 0, 0, 0, 0),   -- ilvl 141  Staff of Immaculate Recovery  (Black Temple)
  (@NPC,  77,  30908, 0, 0, 0, 0),   -- ilvl 151  Apostle of Argus  (Hyjal)
  (@NPC,  78,  32374, 0, 0, 0, 0),   -- ilvl 151  Zhar'doom, Greatstaff of the Devourer  (Black Temple)
  (@NPC,  79,  32945, 0, 0, 0, 0),   -- ilvl 141  Fist of Molten Fury  (Hyjal)
  (@NPC,  80,  32946, 0, 0, 0, 0),   -- ilvl 141  Claw of Molten Fury  (Hyjal)
  (@NPC,  81,  32237, 0, 0, 0, 0),   -- ilvl 141  The Maelstrom's Fury  (Black Temple)
  (@NPC,  82,  32269, 0, 0, 0, 0),   -- ilvl 141  Messenger of Fate  (Black Temple)
  (@NPC,  83,  32471, 0, 0, 0, 0),   -- ilvl 151  Shard of Azzinoth  (Black Temple)
  (@NPC,  84,  32326, 0, 0, 0, 0),   -- ilvl 141  Twisted Blades of Zarak  (Black Temple)
  (@NPC,  85,  32253, 0, 0, 0, 0),   -- ilvl 141  Legionkiller  (Black Temple)
  (@NPC,  86,  32343, 0, 0, 0, 0),   -- ilvl 141  Wand of Prismatic Focus  (Black Temple)
  (@NPC,  87,  32361, 0, 0, 0, 0),   -- ilvl 141  Blind-Seers Icon  (Black Temple)
  (@NPC,  88,  30911, 0, 0, 0, 0),   -- ilvl 151  Scepter of Purification  (Hyjal)
  (@NPC,  89,  32255, 0, 0, 0, 0),   -- ilvl 141  Felstone Bulwark  (Black Temple)
  (@NPC,  90,  34011, 0, 0, 0, 0),   -- ilvl 141  Illidari Runeshield  (Black Temple)
  (@NPC,  91,  30909, 0, 0, 0, 0),   -- ilvl 151  Antonidas's Aegis of Rapt Concentration  (Hyjal)
  (@NPC,  92,  32375, 0, 0, 0, 0),   -- ilvl 151  Bulwark of Azzinoth  (Black Temple)
  (@NPC,  93,  32368, 0, 0, 0, 0),   -- ilvl 141  Tome of the Lightbringer  (Black Temple)
  (@NPC,  94,  32257, 0, 0, 0, 0),   -- ilvl 141  Idol of the White Stag  (Black Temple)
  (@NPC,  95,  32330, 0, 0, 0, 0);    -- ilvl 141  Totem of Ancestral Guidance  (Black Temple)

-- ---------------------------------------------------------------------
-- SPAWN — north end of the vendor row, south-west of the Porter. The
-- row and how its z values were measured: tier-vendors.sql.
-- ---------------------------------------------------------------------

DELETE FROM `creature` WHERE `guid` = @NPC OR (`id` = @NPC AND `guid` NOT BETWEEN 9100000 AND 9100099);

INSERT INTO `creature`
  (`guid`, `id`, `map`, `zoneId`, `areaId`, `spawnMask`, `phaseMask`, `equipment_id`,
   `position_x`, `position_y`, `position_z`, `orientation`,
   `spawntimesecs`, `wander_distance`, `currentwaypoint`, `curhealth`, `curmana`,
   `MovementType`, `npcflag`, `unit_flags`, `dynamicflags`, `ScriptName`, `CreateObject`, `Comment`)
VALUES
  (@NPC, @NPC, 1, 0, 0, 1, 1, 0, 1634.5, -4406.5, 16.41, 3.06538, 300, 0, 0, 12600, 0, 0, 0, 0, 0, '', 0, 'HPRV weapon vendor - Orgrimmar');
