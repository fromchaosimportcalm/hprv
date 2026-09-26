# Bullwark — hand-picked gear

Bullwark is **never re-rolled by `init=`** (`gear-pass.sh master` refuses).
He is the only body whose gear is chosen by hand, so it's recorded here
so it can be restored exactly.

## Snapshot, 2026-09-26 (enchanted and gemmed)

Read from `character_inventory` / `item_instance` on the box after a
`.save`. Every enchant ID was checked against the enchanting item's spell
in `Spell.dbc`. The plan behind the enchants and gems is
`docs/tank-defence.md`.

**Defence: 439 rating (328 items + 111 enchants/gems) → 535 skill.** That
is 45 over the 490 crit-immunity floor. The Adamantine Figurine accounts
for 32 of the item rating.

| Slot | Item | Entry | ilvl | Enchant | Gems |
|---|---|---|---|---|---|
| Head | Tankatronic Goggles | 32473 | 127 | Arcanum of the Defender | Earthstorm, Talasite |
| Neck | Barbed Choker of Discipline | 28516 | 115 | | |
| Shoulder | Warbringer Shoulderguards | 29016 | 120 | Greater Inscription of the Knight | Star, Talasite |
| Chest | Panzar'Thar Breastplate | 28597 | 115 | Chest - Defense | Talasite, Star, Star |
| Waist | Crimson Girdle of the Indomitable | 28566 | 115 | | Star, Talasite |
| Legs | Wrynn Dynasty Greaves | 28621 | 115 | Nethercleft Leg Armor | Star, Talasite, Talasite |
| Feet | Battlescar Boots | 28747 | 115 | Boots - Boar's Speed | Star, Star |
| Wrist | Vambraces of Courage | 28502 | 115 | Bracer - Major Defense | Talasite |
| Hands | Warbringer Handguards | 29017 | 120 | Gloves - Threat | |
| Finger 1 | Shermanar Great-Ring | 28675 | 115 | | |
| Finger 2 | Violet Signet of the Great Protector | 29279 | 130 | | |
| Trinket 1 | Adamantine Figurine | 27891 | 112 | | |
| Trinket 2 | Brooch of the Immortal King (blue) | 32534 | 115 | | |
| Back | Drape of the Dark Reavers | 28672 | 115 | Cloak - Steelweave | |
| Main hand | King's Defender | 28749 | 115 | Weapon - Mongoose | |
| Off hand | Shield of Impenetrable Darkness | 28606 | 115 | Shield - Major Stamina | |
| Ranged | Barrel-Blade Longrifle | 30724 | 120 | | Star, Star |

Gems: Eternal Earthstorm Diamond (meta, active), Enduring Talasite ×7 in
the yellow sockets, Solid Star of Elune ×9 in the red and blue sockets.
The socket bonuses on the goggles, chest and bracers are active. The red
sockets on the shoulders, belt, legs, boots and rifle give up their
bonuses on purpose.

Enchant IDs in `item_instance.enchantments`, for auditing: 2999, 2991,
1951, 3013, 2940, 2648 (bracers and cloak), 2613, 2673, 1071. Gems:
3274, 2743 (Talasite), 2731 (Star).

The Violet Signet (130) is the Karazhan rep ring and sits above the 125
cap on purpose. A hand-picked piece isn't bound by `AutoGearScoreLimit`,
which only gates `autogear` (ADR `0006`).

`roster-status.sh` warns about a defence item in his bags: that's the
Gnomeregan Auto-Blocker, which the Figurine replaced. It's safe to ignore.

### Restore, if anything ever wipes him

Logged in as Bullwark (`.additem` gives to the target, or to you with no
target). Items, then equip:

```
.additem 32473
.additem 28516
.additem 29016
.additem 28597
.additem 28566
.additem 28621
.additem 28747
.additem 28502
.additem 29017
.additem 28675
.additem 29279
.additem 27891
.additem 32534
.additem 28672
.additem 28749
.additem 28606
.additem 30724
```

Enchants (use each on its slot), then gems as in the table above:

```
.additem 29186
.additem 35729
.additem 38999
.additem 29536
.additem 38944
.additem 38899
.additem 38885
.additem 39000
.additem 38925
.additem 38945
.additem 35501
.additem 24062 7
.additem 24033 9
```

### Also carried (bags and bank), not equipped

Gear only, highest ilvl first. The Tier 4 strip left bags and bank alone.

| Item | Entry | ilvl | Note |
|---|---|---|---|
| Illidari Runeshield | 34011 | 141 | above the Tier 4 line; shield |
| Warbringer Greathelm | 29011 | 120 | replaced by the goggles |
| Warlord's Iron-Breastplate | 25024 | 120 | |
| Topaz-Studded Battlegrips | 30741 | 120 | |
| Tuurik Torch | 25098 | 117 | |
| Fel Ripper | 25112 | 117 | |
| Violet Signet | 29276 | 115 | lower rep tier of the equipped ring |
| The Bringer of Death | 31308 | 115 | |
| Ornate Khorium Rifle | 23748 | 115 | |
| Gnomeregan Auto-Blocker 600 | 29387 | 110 | replaced by the Figurine |
| Blinkstrike | 31332 | 100 | |
| Thunderfury, Blessed Blade of the Windseeker | 19019 | 80 | keepsake |
| Elementium Reinforced Bulwark | 19349 | 77 | |
| Claw of the Black Drake | 19365 | 75 | |
| Draconic Maul | 19358 | 70 | |
| Goblin Rocket Launcher | 23836 | 70 | engineering |
| Obsidian Edged Blade | 18822 | 68 | |

### Re-snapshot

After any change to his gear, run this on the box and update this file:

```sql
SELECT ci.slot, ii.itemEntry, it.name, it.ItemLevel, TRIM(ii.enchantments)
  FROM acore_characters.characters c
  JOIN acore_characters.character_inventory ci ON ci.guid = c.guid AND ci.bag = 0 AND ci.slot < 19
  JOIN acore_characters.item_instance ii ON ii.guid = ci.item
  JOIN acore_world.item_template it ON it.entry = ii.itemEntry
 WHERE c.name = 'Bullwark' ORDER BY ci.slot;
```

Defence: `roster-status.sh` prints it under his row.
