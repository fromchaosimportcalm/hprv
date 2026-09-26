# HPRV raid NPCs

Five NPCs for an AzerothCore + mod-playerbots server running TBC raids:

| NPC | Does |
|---|---|
| **Porter Nozdrel** | Teleports you **and your whole party or raid**, bots included, to Shattrath or any TBC raid: Karazhan, Gruul, Magtheridon, SSC, The Eye, Hyjal, Black Temple, Zul'Aman, Sunwell |
| **Almari Stonebrand** | Every class's Tier 4 set, free |
| **Veshan Coilhand** | Tier 5, free |
| **Oriel Duskmantle** | Tier 6, including the Sunwell wrist, waist and feet, free |
| **Torvek Ashforge** | The 95 raid-drop weapons, shields, off-hands and relics of the T4–T6 raids (free with the optional file) |

They spawn in **Orgrimmar** (Valley of Strength) and **Stormwind** (Trade
District). They're friendly to both factions, so either city works for
anyone.

It's plain SQL. There's no C++, no module and no rebuild, and every file
is idempotent.

## Requirements

- AzerothCore with a world DB close to the 2026 schema, meaning
  `creature_template_model` exists, and MySQL 8 (the vendors use
  `ROW_NUMBER()`). It was written against the playerbots fork, but
  nothing in it needs playerbots. `precheck.sql` checks every column it
  uses before anything is written.
- The IDs 9100000–9100099 free in `creature_template`, `creature`,
  `gossip_menu`, `npc_text` and `smart_scripts`. The precheck checks this
  too.

## Install

Take a backup of the world DB first. Then, from this folder:

```sh
WORLD=acore_world    # your world DB name
for f in 00-precheck.sql 01-teleporter-npc.sql 02-tier-vendors.sql \
         03-weapon-vendor.sql 04-stormwind-spawns.sql; do
  echo "== $f"; mysql "$WORLD" < "$f" || break
done
```

Then **restart the worldserver.** New creatures and spawns are only read
at startup, and `.reload` won't pick them up.

If the precheck fails, it prints what's wrong just above the error, and
nothing has been written. Don't run the rest.

**Optional: free weapons.** On its own, Torvek sells at stock prices.
To make his stock free:

```sh
mysql "$WORLD" < optional/weapon-vendor-free-prices.sql    # then restart
```

This is the only file that changes stock rows: `BuyPrice` on exactly 95
items that no stock vendor sells. `optional/weapon-vendor-revert-prices.sql`
puts the original prices back.

Skip `04-stormwind-spawns.sql` for Orgrimmar only.

## Use

Talk to the Porter and pick a destination. Everyone in your party or raid
**on the same map as you** comes along, at any distance. Anyone on
another map is left behind. With no group, only you go.

The vendors are ordinary vendors, and gear a class can't use shows red.
The 3.3.5 vendor window holds at most 150 items, which is why the gear
is split across four NPCs.

## Changing things

- **Move an NPC:** `.npc move` it in game, then copy the position into its
  spawn row so a re-run doesn't put it back. Spawn guids are 9100000–04
  (Orgrimmar) and 9100010–14 (Stormwind).
- **Change a stock list:** edit and re-run the file, then run
  `.reload npc_vendor`. That applies live.
- **Change the Porter's destinations:** edit and re-run, then restart.
  Each spawned NPC keeps the SmartAI copy it took when it spawned, so
  `.reload smart_scripts` alone looks like it worked but changes nothing.

## Uninstall

```sh
mysql "$WORLD" < uninstall.sql     # then restart
```

That removes everything in 9100000–9100099. If you applied the free
weapon prices, also run `optional/weapon-vendor-revert-prices.sql`.

## Where the positions came from

The z values were measured, not eyeballed. Each is the ground height from
the server's own navmesh (`mmaps`), corrected by the median offset of the
stock NPCs standing around it. Orgrimmar's row sits on a flat stretch
beside a ramp, and Stormwind's is 3 yd from the `.tele Stormwind` landing
point. The details are in the comments of `02-tier-vendors.sql` and
`04-stormwind-spawns.sql`.
