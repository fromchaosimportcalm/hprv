# BC-feel tuning

The ongoing hobby, and the direction with the most room left in it.

## There is exactly one lever, and it is SQL

**Restore TBC raid boss HP to 2.4.3 values** — revert the global 30% HP
nerf that patch 3.0.2 applied — as idempotent, per-raid `UPDATE`s against
`acore_world.creature_template`, kept in version control here.

The bot strategies were tested against 2.4.3-restored tuning, so this is
supported, not a hack.

Rules for files in this directory:

- **Idempotent and re-runnable.** Compute from a recorded baseline, never
  from the current value — running it twice must not compound.
- **Never applied automatically.** These are `UPDATE`s against a live
  world DB. Review, then run by hand.
- **Record the baseline in the file.** `entry`, `unit_class` base HP at
  level, `HealthModifier`, and the effective HP it produces. Without that
  the script cannot be reasoned about later.
- **One direction only.** A file that lowers HP and a file that raises it
  will fight over the same column.

## There is no bot damage or healing multiplier

This is worth stating plainly, because the project planned around it for
some time under the name "IP nerfs", and it does not exist.

Verified 2026-08-13 at the current pin: the entire 102 KB
`playerbots.conf` matches `multiplier|nerf` on **two lines**, one of
which is `AiPlayerbot.RandomChangeMultiplier` — unrelated, it governs
random-bot churn.

```bash
grep -inE 'multiplier|nerf' /mnt/hprv/server/etc/modules/playerbots.conf
```

If bot competence ever needs lowering, the available routes are a module
patch or a deliberate gear-tier drop (`AiPlayerbot.AutoGearScoreLimit`).
Neither is a config edit, and both are ADR-worthy.

**Re-check this if the pin is ever advanced.** It is a statement about
one commit, not about the module forever.

## Order of operations

1. **Boss HP restoration first, and probably only.** It is the lever that
   makes fights bite without touching the raid's own margin, and it is
   the one that is authentically 2.4.3 rather than a handicap.
2. Only if content still trivialises after that, consider the gear tier.

Start conservative and one raid at a time. The point is a raid that
occasionally wipes because a bot stood in fire — not an unkillable one.

**Start in Karazhan. Black Temple is off-limits until it is cleared.**
Measured 2026-08-15: the Illidari Council's shared pool is ~4.89M
(controller entry 23426, level 70 class 1, `HealthModifier = 700`,
`basehp1 = 6986`) and its 15-minute berserk demands ~5,430 raid DPS. At
`AutoGearScoreLimit = 141` the raid produces ~4,130 — 30% short of the
**already-nerfed** number this directory exists to undo. Restoring 2.4.3
HP there would push the pool toward ~7M on a fight that cannot be
finished today.

This is what rule 2 of this file is for in practice: an enrage-timer
failure is the signal that a tier is not yet cleared, and tuning an
uncleared tier measures gear, not 2.4.3 feel. See ADR `0005`.

Each meaningful tuning decision → an ADR in `decisions/`, recording the
percentage used and what it felt like.
