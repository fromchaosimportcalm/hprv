# Bullwark — hand-picked gear

Bullwark is **never re-rolled by `init=`** (`gear-pass.sh master` refuses).
He is the only body whose gear is chosen by hand, so it's recorded here
so it can be restored exactly.

## Snapshot, 2026-09-26 (post Tier 4 reset, pre item 2)

Read from `character_inventory` / `item_instance` on the box. **No
enchants and no gems on any piece.** Every `enchantments` field is all
zeros, and no piece has a random suffix.

| Slot | Item | Entry | ilvl |
|---|---|---|---|
| Head | Warbringer Greathelm | 29011 | 120 |
| Neck | Barbed Choker of Discipline | 28516 | 115 |
| Shoulder | Warbringer Shoulderguards | 29016 | 120 |
| Chest | Panzar'Thar Breastplate | 28597 | 115 |
| Waist | Crimson Girdle of the Indomitable | 28566 | 115 |
| Legs | Wrynn Dynasty Greaves | 28621 | 115 |
| Feet | Battlescar Boots | 28747 | 115 |
| Wrist | Vambraces of Courage | 28502 | 115 |
| Hands | Warbringer Handguards | 29017 | 120 |
| Finger 1 | Shermanar Great-Ring | 28675 | 115 |
| Finger 2 | Violet Signet of the Great Protector | 29279 | 130 |
| Trinket 1 | Brooch of the Immortal King (blue) | 32534 | 115 |
| Trinket 2 | Gnomeregan Auto-Blocker 600 | 29387 | 110 |
| Back | Drape of the Dark Reavers | 28672 | 115 |
| Main hand | King's Defender | 28749 | 115 |
| Off hand | Shield of Impenetrable Darkness | 28606 | 115 |
| Ranged | Barrel-Blade Longrifle | 30724 | 120 |

**Defence: 295 rating → 474 skill. That is 16 short of the 490
crit-immunity floor** against a level-73 boss, roughly 38 more defence
rating at 70. He is crittable until that's closed: this is the "Bullwark
by hand" step of TODO item 2. The Violet Signet (130) is the Karazhan
rep ring and sits above the 125 cap on purpose. A hand-picked piece isn't
bound by `AutoGearScoreLimit`, which only gates `autogear` (ADR `0006`).

The item 2 obvious levers are enchants and gems, because he has none.
Defence enchants on bracers, cloak and chest, plus defence gems, close 16
skill without changing a single piece.

### Restore, if anything ever wipes him

Logged in as Bullwark (`.additem` gives to the target, or to you with no target), one per item, then equip:

```
.additem 29011
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
.additem 32534
.additem 29387
.additem 28672
.additem 28749
.additem 28606
.additem 30724
```

### Also carried (bags and bank), not equipped

Gear only, highest ilvl first. The Tier 4 strip left bags and bank alone.

| Item | Entry | ilvl | Note |
|---|---|---|---|
| Illidari Runeshield | 34011 | 141 | above the Tier 4 line; shield |
| Warlord's Iron-Breastplate | 25024 | 120 | |
| Topaz-Studded Battlegrips | 30741 | 120 | |
| Tuurik Torch | 25098 | 117 | |
| Fel Ripper | 25112 | 117 | |
| Violet Signet | 29276 | 115 | lower rep tier of the equipped ring |
| The Bringer of Death | 31308 | 115 | |
| Ornate Khorium Rifle | 23748 | 115 | |
| Blinkstrike | 31332 | 100 | |
| Thunderfury, Blessed Blade of the Windseeker | 19019 | 80 | keepsake |
| Elementium Reinforced Bulwark | 19349 | 77 | |
| Claw of the Black Drake | 19365 | 75 | |
| Draconic Maul | 19358 | 70 | |
| Goblin Rocket Launcher | 23836 | 70 | engineering |
| Obsidian Edged Blade | 18822 | 68 | |
| Gnomish Poultryizer | 23835 | 68 | engineering |

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
