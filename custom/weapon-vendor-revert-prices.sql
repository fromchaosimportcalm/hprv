-- HPRV — restore stock BuyPrice on the weapon vendor's items
--
-- Undoes the one stock change weapon-vendor.sql makes. Values read off
-- item_template on 2026-09-25, before it was applied. Needs a
-- worldserver restart to take effect. Leaves the vendor itself in
-- place; it will then charge these prices.

UPDATE `item_template` SET `BuyPrice` =  622283 WHERE `entry` =  28767;  -- The Decapitator
UPDATE `item_template` SET `BuyPrice` =  727636 WHERE `entry` =  39769;  -- Arcanite Ripper
UPDATE `item_template` SET `BuyPrice` =  816300 WHERE `entry` =  28773;  -- Gorehowl
UPDATE `item_template` SET `BuyPrice` =  819068 WHERE `entry` =  28794;  -- Axe of the Gronn Lords
UPDATE `item_template` SET `BuyPrice` =  488023 WHERE `entry` =  28772;  -- Sunfury Bow of the Phoenix
UPDATE `item_template` SET `BuyPrice` =  578941 WHERE `entry` =  28522;  -- Shard of the Virtuous
UPDATE `item_template` SET `BuyPrice` =  583164 WHERE `entry` =  28657;  -- Fool's Bane
UPDATE `item_template` SET `BuyPrice` =  648357 WHERE `entry` =  28771;  -- Light's Justice
UPDATE `item_template` SET `BuyPrice` =  757286 WHERE `entry` =  28800;  -- Hammer of the Naaru
UPDATE `item_template` SET `BuyPrice` =  819147 WHERE `entry` =  28774;  -- Glaive of the Pit
UPDATE `item_template` SET `BuyPrice` =  581170 WHERE `entry` =  28729;  -- Spiteblade
UPDATE `item_template` SET `BuyPrice` =  581111 WHERE `entry` =  28749;  -- King's Defender
UPDATE `item_template` SET `BuyPrice` =  610512 WHERE `entry` =  28802;  -- Bloodmaw Magus-Blade
UPDATE `item_template` SET `BuyPrice` =  748090 WHERE `entry` =  28604;  -- Nightstaff of the Everliving
UPDATE `item_template` SET `BuyPrice` =  718325 WHERE `entry` =  28633;  -- Staff of Infinite Mysteries
UPDATE `item_template` SET `BuyPrice` =  751096 WHERE `entry` =  28658;  -- Terestian's Stranglestaff
UPDATE `item_template` SET `BuyPrice` =  763219 WHERE `entry` =  28782;  -- Crystalheart Pulse-Staff
UPDATE `item_template` SET `BuyPrice` =  583281 WHERE `entry` =  28524;  -- Emerald Ripper
UPDATE `item_template` SET `BuyPrice` =  624625 WHERE `entry` =  28768;  -- Malchazeen
UPDATE `item_template` SET `BuyPrice` =  629244 WHERE `entry` =  28770;  -- Nathrezim Mindblade
UPDATE `item_template` SET `BuyPrice` =  146756 WHERE `entry` =  28659;  -- Xavian Stiletto
UPDATE `item_template` SET `BuyPrice` =  146756 WHERE `entry` =  28826;  -- Shuriken of Negation
UPDATE `item_template` SET `BuyPrice` =  430863 WHERE `entry` =  28673;  -- Tirisfal Wand of Ascendancy
UPDATE `item_template` SET `BuyPrice` =  459687 WHERE `entry` =  28783;  -- Eredar Wand of Obliteration
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  28525;  -- Signet of Unshakable Faith
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  28603;  -- Talisman of Nightbane
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  28728;  -- Aran's Soothing Sapphire
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  28734;  -- Jewel of Infinite Possibilities
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  28781;  -- Karaborian Talisman
UPDATE `item_template` SET `BuyPrice` =  385800 WHERE `entry` =  28606;  -- Shield of Impenetrable Darkness
UPDATE `item_template` SET `BuyPrice` =  365079 WHERE `entry` =  28611;  -- Dragonheart Flameshield
UPDATE `item_template` SET `BuyPrice` =  378818 WHERE `entry` =  28754;  -- Triptych Shield of the Ancients
UPDATE `item_template` SET `BuyPrice` =  405875 WHERE `entry` =  28825;  -- Aldori Legacy Defender
UPDATE `item_template` SET `BuyPrice` =  387811 WHERE `entry` =  29458;  -- Aegis of the Vindicator
UPDATE `item_template` SET `BuyPrice` =  182181 WHERE `entry` =  28568;  -- Idol of the Avian Heart
UPDATE `item_template` SET `BuyPrice` =  174333 WHERE `entry` =  28523;  -- Totem of Healing Rains
UPDATE `item_template` SET `BuyPrice` =  698441 WHERE `entry` =  29924;  -- Netherbane
UPDATE `item_template` SET `BuyPrice` =  539425 WHERE `entry` =  30105;  -- Serpent Spine Longbow
UPDATE `item_template` SET `BuyPrice` =  495803 WHERE `entry` =  29949;  -- Arcanite Steam-Pistol
UPDATE `item_template` SET `BuyPrice` =  729627 WHERE `entry` =  29996;  -- Rod of the Sun King
UPDATE `item_template` SET `BuyPrice` =  727011 WHERE `entry` =  30108;  -- Lightfathom Scepter
UPDATE `item_template` SET `BuyPrice` =  873389 WHERE `entry` =  30090;  -- World Breaker
UPDATE `item_template` SET `BuyPrice` =  661003 WHERE `entry` =  30082;  -- Talon of Azshara
UPDATE `item_template` SET `BuyPrice` =  643599 WHERE `entry` =  30095;  -- Fang of the Leviathan
UPDATE `item_template` SET `BuyPrice` =  902312 WHERE `entry` =  29993;  -- Twinblade of the Phoenix
UPDATE `item_template` SET `BuyPrice` =  801379 WHERE `entry` =  29981;  -- Ethereum Life-Staff
UPDATE `item_template` SET `BuyPrice` =  801126 WHERE `entry` =  30021;  -- Wildfury Greatstaff
UPDATE `item_template` SET `BuyPrice` =  862632 WHERE `entry` =  29988;  -- The Nexus Key
UPDATE `item_template` SET `BuyPrice` =  658642 WHERE `entry` =  29948;  -- Claw of the Phoenix
UPDATE `item_template` SET `BuyPrice` =  671256 WHERE `entry` =  32944;  -- Talon of the Phoenix
UPDATE `item_template` SET `BuyPrice` =  643667 WHERE `entry` =  29962;  -- Heartrazor
UPDATE `item_template` SET `BuyPrice` =  695266 WHERE `entry` =  30103;  -- Fang of Vashj
UPDATE `item_template` SET `BuyPrice` =  145472 WHERE `entry` =  30025;  -- Serpentshrine Shuriken
UPDATE `item_template` SET `BuyPrice` =  482699 WHERE `entry` =  29982;  -- Wand of the Forgotten Star
UPDATE `item_template` SET `BuyPrice` =  492008 WHERE `entry` =  30080;  -- Luminescent Rod of the Naaru
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  29923;  -- Talisman of the Sun King
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  30049;  -- Fathomstone
UPDATE `item_template` SET `BuyPrice` =  196587 WHERE `entry` =  30051;  -- Idol of the Crescent Goddess
UPDATE `item_template` SET `BuyPrice` =  185780 WHERE `entry` =  30023;  -- Totem of the Maelstrom
UPDATE `item_template` SET `BuyPrice` =  729697 WHERE `entry` =  32236;  -- Rising Tide
UPDATE `item_template` SET `BuyPrice` =  724395 WHERE `entry` =  32254;  -- The Brutalizer
UPDATE `item_template` SET `BuyPrice` =  908852 WHERE `entry` =  32348;  -- Soul Cleaver
UPDATE `item_template` SET `BuyPrice` =  538963 WHERE `entry` =  30906;  -- Bristleblitz Striker
UPDATE `item_template` SET `BuyPrice` =  541167 WHERE `entry` =  32336;  -- Black Bow of the Betrayer
UPDATE `item_template` SET `BuyPrice` =  539531 WHERE `entry` =  32325;  -- Rifle of the Stoic Guardian
UPDATE `item_template` SET `BuyPrice` =  693145 WHERE `entry` =  32262;  -- Syphon of the Nathrezim
UPDATE `item_template` SET `BuyPrice` =  700922 WHERE `entry` =  32943;  -- Swiftsteel Bludgeon
UPDATE `item_template` SET `BuyPrice` =  674339 WHERE `entry` =  34009;  -- Hammer of Judgement
UPDATE `item_template` SET `BuyPrice` =  716358 WHERE `entry` =  32500;  -- Crystal Spire of Karabor
UPDATE `item_template` SET `BuyPrice` =  886051 WHERE `entry` =  32248;  -- Halberd of Desolation
UPDATE `item_template` SET `BuyPrice` =  729627 WHERE `entry` =  32369;  -- Blade of Savagery
UPDATE `item_template` SET `BuyPrice` =  749656 WHERE `entry` =  30910;  -- Tempest of Chaos
UPDATE `item_template` SET `BuyPrice` = 1215564 WHERE `entry` =  32837;  -- Warglaive of Azzinoth
UPDATE `item_template` SET `BuyPrice` = 1219873 WHERE `entry` =  32838;  -- Warglaive of Azzinoth
UPDATE `item_template` SET `BuyPrice` =  978692 WHERE `entry` =  30902;  -- Cataclysm's Edge
UPDATE `item_template` SET `BuyPrice` =  895861 WHERE `entry` =  32344;  -- Staff of Immaculate Recovery
UPDATE `item_template` SET `BuyPrice` =  930195 WHERE `entry` =  30908;  -- Apostle of Argus
UPDATE `item_template` SET `BuyPrice` =  919743 WHERE `entry` =  32374;  -- Zhar'doom, Greatstaff of the Devourer
UPDATE `item_template` SET `BuyPrice` =  706154 WHERE `entry` =  32945;  -- Fist of Molten Fury
UPDATE `item_template` SET `BuyPrice` =  708699 WHERE `entry` =  32946;  -- Claw of Molten Fury
UPDATE `item_template` SET `BuyPrice` =  732313 WHERE `entry` =  32237;  -- The Maelstrom's Fury
UPDATE `item_template` SET `BuyPrice` =  711315 WHERE `entry` =  32269;  -- Messenger of Fate
UPDATE `item_template` SET `BuyPrice` =  746944 WHERE `entry` =  32471;  -- Shard of Azzinoth
UPDATE `item_template` SET `BuyPrice` =  145472 WHERE `entry` =  32326;  -- Twisted Blades of Zarak
UPDATE `item_template` SET `BuyPrice` =  541334 WHERE `entry` =  32253;  -- Legionkiller
UPDATE `item_template` SET `BuyPrice` =  535554 WHERE `entry` =  32343;  -- Wand of Prismatic Focus
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  32361;  -- Blind-Seers Icon
UPDATE `item_template` SET `BuyPrice` = 1015299 WHERE `entry` =  30911;  -- Scepter of Purification
UPDATE `item_template` SET `BuyPrice` =  465287 WHERE `entry` =  32255;  -- Felstone Bulwark
UPDATE `item_template` SET `BuyPrice` =  431577 WHERE `entry` =  34011;  -- Illidari Runeshield
UPDATE `item_template` SET `BuyPrice` =  477996 WHERE `entry` =  30909;  -- Antonidas's Aegis of Rapt Concentration
UPDATE `item_template` SET `BuyPrice` =  472692 WHERE `entry` =  32375;  -- Bulwark of Azzinoth
UPDATE `item_template` SET `BuyPrice` =  218103 WHERE `entry` =  32368;  -- Tome of the Lightbringer
UPDATE `item_template` SET `BuyPrice` =  219651 WHERE `entry` =  32257;  -- Idol of the White Stag
UPDATE `item_template` SET `BuyPrice` =  219715 WHERE `entry` =  32330;  -- Totem of Ancestral Guidance
