# Raid layout — the ten and the 25

The standard party layout for both raid sizes. The ten fill groups 1–2
on their own, so a 10-man night and a 25-man night use **the same raid**:
the 15 simply sit in groups 3–5, offline, on 10-man nights.

## The layout

| Group | Members | Why |
|---|---|---|
| **1** | Bullwark, Crumm, Anmine, Krast, Nathos | Tank + melee in Krast's totems, tank healer beside the tank |
| **2** | Celerina, Dijito, Izri, Ilyna, Restofarian | Casters + hunter. In the 25, this is the one group without a shaman |
| 3 | Ararin, Gerina, Muhnun, Zaene, Fimur | Melee in enhancement totems (Windfury, Strength of Earth) |
| 4 | Sehjece, Lomul, Vestanza, Grohtarty, Tengwe | Casters in elemental totems (Totem of Wrath, Wrath of Air) |
| 5 | Tanke, Irntifumm, Olidina, Dehme, Fehmos | Healers in resto totems and Mana Tide |

Groups 1–2 are the 10-man. Groups 1–5 are the 25.

**Why it matters less than in real TBC.** At 3.3.5a most party buffs are
raid-wide, including Bloodlust/Heroism, Battle Shout, auras, Leader of the
Pack, Moonkin aura and Ferocious Inspiration. What is still party-scoped is
**shaman totems** and **party heals** (Prayer of Healing). So the layout is
really "which party gets which shaman's totems". Which totems a bot shaman
actually drops is its own AI's choice. It hasn't been checked.

## It persists: set it once

`group_member.subgroup` is stored server-side, and nothing in the module
moves a bot between groups:

- **A bot logging out stays in the raid.** `BotLogoutGroupCleanupOperation`
  (`PlayerbotOperations.h:417`) only saves the bot's strategies. It never
  leaves the group.
- **A bot logging in keeps its raid** as long as its master (you) is in it
  (`PlayerbotMgr.cpp`, `OnBotLogin`). The ten auto-login into their groups,
  and a summoned bot rejoins in the group it left.
- **Offline members don't block a 10-man.** The instance cap counts players
  actually inside the map (`Map.cpp:1956`), not the raid roster.

Read from the source at the pin, 2026-09-26. The 25-man layout was
dry-run against the live DB and rolled back. It hasn't yet been watched
surviving a restart. Run the audit below the first night after one.

**What scrambles it:** disbanding the raid, removing a member (a kick,
or a bot told to `leave`), converting to a party, or you leaving the raid.
A re-invited character lands in the first group with space.

## Audit

```sql
SELECT gm.subgroup + 1 AS `group`, GROUP_CONCAT(c.name ORDER BY c.name) AS members
  FROM acore_characters.group_member gm
  JOIN acore_characters.characters c ON c.guid = gm.memberGuid
 WHERE gm.guid = (SELECT gm2.guid FROM acore_characters.group_member gm2
                    JOIN acore_characters.characters c2 ON c2.guid = gm2.memberGuid
                   WHERE c2.name = 'Bullwark')
 GROUP BY gm.subgroup ORDER BY gm.subgroup;
```

Compare with the table above. While you're there, check `memberFlags`
too (`CLAUDE.md` rule 6). All zero is the correct state.

## Restoring it

- **In game (the quick way):** open the raid pane and drag. You're the
  leader, so the swaps take effect immediately and persist.
- **By script (the exact way):** `scripts/raid-layout.sql`, **with the
  server stopped**. It moves only characters already in the raid, and its
  checks roll it back unless all 25 are present, no group holds more than
  5, and the ten fill groups 1–2 by themselves. Invite anyone missing first.

If the roster changes (a bench swap), update this table and the `CASE`
in `raid-layout.sql` together.
