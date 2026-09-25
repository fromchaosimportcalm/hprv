# Custom NPCs

Four NPCs added 2026-09-25, all SQL-only (no C++, no rebuild), all
standing together in **Orgrimmar, Valley of Strength**. Source is
`custom/`, applied by hand with `mysql acore_world < custom/<file>.sql`
on the box. Every file is idempotent.

| Entry | NPC | What it does | File |
|---|---|---|---|
| 9100000 | **Porter Nozdrel** | Teleports you **and your whole party/raid** to Shattrath, Karazhan, Zul'Aman, Gruul's Lair, Magtheridon's Lair or Black Temple | `teleporter-npc.sql` |
| 9100001 | **Almari Stonebrand** | Tier 4 set pieces, every class, free (85) | `tier-vendors.sql` |
| 9100002 | **Veshan Coilhand** | Tier 5 set pieces, free (85) | `tier-vendors.sql` |
| 9100003 | **Oriel Duskmantle** | Tier 6 set pieces incl. Sunwell wrist/waist/feet, free (136) | `tier-vendors.sql` |
| 9100004 | **Torvek Ashforge** | T4/T5/T6 raid-drop weapons, shields, off-hands, relics, free (95) | `weapon-vendor.sql` |

## The ID range

**9100000–9100099 is ours**, in every table: `creature_template`,
`creature` (spawn guid = entry), `gossip_menu`, `npc_text`,
`smart_scripts`, `npc_vendor`. It was empty on 2026-09-25; the highest
stock creature entry is 3,460,603. Each file's `DELETE`s are scoped to
its own IDs, so re-running only ever replaces its own rows. Take the
next free number for anything new.

## What needs a restart — and the trap

| Change | Takes effect |
|---|---|
| New NPC (`creature_template`, model, `npc_text`, spawn) | Restart only. `.reload creature_template` refreshes entries already loaded, never new ones |
| Gossip menu text/options | Live: `.reload gossip_menu_option` |
| Vendor stock list | Live: `.reload npc_vendor` |
| Item price (`item_template.BuyPrice`) | Restart — no `.reload item_template` at this pin |
| **SmartAI (`smart_scripts`)** | **Only once the NPC respawns** |

**`.reload smart_scripts` does not reach an NPC that is already
spawned.** It refreshes the store, but each creature copies its script
at AI init (`SmartScript::GetScript`) and keeps that copy. It reports
success and changes nothing about the live NPC. Found the hard way: the
Porter kept teleporting only the clicker after her target was switched
to the whole party. Restart, or `.npc delete` her and let the restart
bring her back.

## Porter details

- The party teleport uses SmartAI target 16, `INVOKER_PARTY`: every group
  member **on the same map as you**, at any distance. Bots are real
  `Player`s, so they come too. Anyone on another map is left behind —
  summon them first. With no group it moves just you.
- Coordinates are the stock `game_tele` rows (the `.tele` names).

## Vendor details

- **One vendor per tier because the 3.3.5 vendor window caps at 150
  items** (`MAX_VENDOR_ITEMS`, `Creature.h`); anything past it is dropped
  silently.
- **Tier pieces are free without any price change.** Every T4–T6 set
  piece already has `BuyPrice = 0` in the stock DB — they were only ever
  token rewards.
- **Weapons needed one stock change.** They carry gold prices, so
  `weapon-vendor.sql` sets `BuyPrice = 0` on exactly its 95 items (no
  stock vendor sells any of them). `weapon-vendor-revert-prices.sql`
  restores the originals.
- The weapon list is written out explicitly, derived by walking the
  creature and gameobject loot tables (through `reference_loot_template`)
  for every spawn in Karazhan, Gruul, Mag, SSC, TK, Hyjal and BT. ZA and
  Sunwell are deliberately out.

## Stripping gear back down a tier

`scripts/strip-gear-above-ilvl.sql` deletes equipped items above an item
level across the roster — the tool behind ADR `0006`. It skips anyone
online (they would write their items back on logout), so it is safe with
the server running for everyone else, and it rebuilds
`characters.equipmentCache` so the character-select screen stops showing
the deleted gear. **Take a `mysqldump` first**; backups from the
2026-09-25 run are in `/opt/hprv/backups/` on the box.
