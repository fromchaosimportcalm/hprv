# Tank defence — closing Bullwark and Ararin to 490

490 defence skill makes a level-70 tank crit-immune to a level-73 boss
(5.6% crit to remove, 0.04% per point above 350). At the scripts'
conversion, skill = 350 + floor(rating / 2.37), so **490 needs 332
defence rating**. The game's own divisor at 70 is 2.3654, so the scripts
are slightly conservative.

Every number here was read on the box on 2026-09-26. Enchant and gem
values come from `SpellItemEnchantment.dbc` and `GemProperties.dbc` in
`/mnt/hprv/data/dbc`, not from memory.

**Tier rule:** TBC-era sources only, matching the Tier 4 reset
(ADR `0006`). Rare gems, not the Fire Opal and Lionseye epics (T5–T6
patterns), and no WotLK enchants (Titanweave, Stalwart Protector,
Pinnacle, Inscription of Kings, Shield/Chest Greater Defense).

## Counting enchants and gems (fixed 2026-09-26)

`roster-status.sh` and `hprv-spec.sh --show` used to sum defence from
`item_template` only. Enchants and gems live in `item_instance.enchantments`,
and neither script read them, so **Ararin showed 442 when he was really
455** (his `init=` pass had given him Arcanum of the Defender and Greater
Inscription of the Knight). Both scripts now share `scripts/defence.conf`,
which also reads every enchant slot against a table generated from the
DBC. They print it split, e.g. `251 rating (220 items + 31 enchants/gems)`.
Like any DB read, it shows last-saved state, so `.save` first.

## Bullwark: 474 → 521, enchants and gems only, no gear change

> **Done 2026-09-26, and he ended at 535, not 521.** Everything below is
> applied and verified from the DB, and the gem layout matches the table
> exactly. The extra 14 skill is the Adamantine Figurine (+32 rating),
> which replaced the Goblin Rocket Launcher in a trinket slot. He also
> took the five non-defence enchants: Gloves - Threat, Weapon - Mongoose,
> Nethercleft Leg Armor, Shield - Major Stamina and Boots - Boar's Speed.
> Threat comes first because the bots' `+threat` cap scales raid DPS
> against his threat (rule 3). His current gear, and the restore lines,
> are in `docs/bullwark-gear.md`.

This was the plan as written, before any of it was applied: he was at
**296 rating** from items. His gear had moved on from the old snapshot:
Tankatronic Goggles on the head, and the Goblin Rocket Launcher and the
Brooch in the trinket slots. He had no enchants and no gems anywhere.

### Enchants: 71 rating, enough on their own (→ 504)

| Slot | Enchant | Item | Defence | Also |
|---|---|---|---|---|
| Head | Arcanum of the Defender | 29186 | +16 | +17 dodge. Needs Keepers of Time revered: he's exalted |
| Shoulders | Greater Inscription of the Knight | 35729 | +15 | +10 dodge. The no-reputation version |
| Chest | Enchant Chest - Defense | 38999 (scroll) | +16 | |
| Back | Enchant Cloak - Steelweave | 39000 (scroll) | +12 | |
| Wrists | Enchant Bracer - Major Defense | 38899 (scroll) | +12 | |

296 + 71 = **367 → 504**. That is 14 over the floor before a single gem.

### Gems: spend them on stamina, keep a margin (→ 521)

Once the enchants have him capped, gems are for effective health, not
more defence:

| Socket colour | Gem | Item | Gives |
|---|---|---|---|
| Meta (goggles) | Eternal Earthstorm Diamond | 35501 | +12 def, +5% block value |
| Yellow (×7) | Enduring Talasite | 24062 | +4 def, +6 sta each |
| Red and blue (×9) | Solid Star of Elune | 24033 | +12 sta each |

- **The meta activates.** Its condition, read from the DBC, is at least
  2 blue gems and at least 1 yellow. Talasite is green, so it counts as
  both colours, and the Solid Stars are blue.
- **Socket bonuses that land:** goggles +6 sta, chest +4 block, bracers
  +2 dodge. The five items with red sockets (shoulders, belt, legs, boots,
  rifle) give up their bonus. No rare TBC red gem carries defence or
  stamina, and the best of those bonuses is only +6 sta.
- Gems add 12 + 28 = 40 defence: 407 → **521**, plus about 150 stamina.

### Doing it

He's you, so all of it can be done in game. Target yourself:

```
.additem 29186
.additem 35729
.additem 38999
.additem 39000
.additem 38899
.additem 35501
.additem 24062 7
.additem 24033 9
```

Use each enchant item on its slot. Then right-click each socketed piece
to open the socket window and drag the gems in, as in the table.

## Ararin: 455 → 509, which needs gear

He's at **251 rating**: 220 from items and 31 from the enchants `init=`
gave him. Enchants and gems can't close 81 rating on him, because **five
of his slots hold pure-DPS pieces with zero defence**. The `init=` pass
scores raw stats and knows nothing about defence. Swap four of them:

| Slot | Now (0 def) | Replace with | Entry | Def | Sta |
|---|---|---|---|---|---|
| Waist | Lurker's Girdle | Girdle of Valorous Deeds | 29253 | 24 | 37 |
| Feet | Glider's Sabatons | Boots of the Righteous Path | 29254 | 23 | 34 |
| Wrists | Ravager's Bracers | Bracers of Dignity | 29252 | 21 | 30 |
| Trinket | Darkmoon Card: Madness | Adamantine Figurine | 27891 | 32 | — |

All four are ilvl 110–112 badge or crafted TBC items. None needs a
profession to equip (Figurine - Dawnstone Crab was ruled out, since it
needs Jewelcrafting 370). 251 + 100 = **351 → 498**.

Then two enchants for margin:

| Slot | Now | Replace with | Def |
|---|---|---|---|
| Chest | +150 health | Enchant Chest - Defense | +16 |
| Wrists (the new bracers) | none | Enchant Bracer - Major Defense | +12 |

351 + 28 = **379 → 509**. His current gems (+15 stamina in every
socket) stay.

### Doing it: `scripts/fix-tank-defence.sql`, with the server stopped

He's a bot, so it can't be done by hand the way Bullwark's can.
Equipping by whisper is fragile: bots re-equip from their bags by their
own scoring, which ignores defence, so the displaced DPS pieces would
come straight back. The script writes the new items straight into the
equip slots, parks the displaced ones in the **bank** (which that scan
can't see), and sets both enchants. It checks every step inside one
transaction, and a slot that already holds the right item is skipped, so
it's safe to re-run.

Dry-run against the live DB on 2026-09-26, then rolled back: every check
passed, and the in-transaction count read **320 items + 59 enchants = 379
→ 509**, as planned. **Applied for real on 2026-09-26** in the item 2
restart. `hprv-spec.sh Ararin --show` reads 509, and the four displaced
pieces are in his bank.

**Any future `init=` pass on Ararin undoes all of this.** Re-run the fix
after every one, exactly as the rule-1 conversion is redone.
