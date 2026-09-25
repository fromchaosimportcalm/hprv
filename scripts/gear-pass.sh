#!/usr/bin/env bash
#
# HPRV — deterministic spec-and-gear passes.
#
# WHAT PROBLEM THIS SOLVES
#
# `.playerbots bot init=<quality>` does not let you ask for a spec. It
# runs PlayerbotFactory::Randomize(false), which:
#
#   1. calls InitTalentsTree(), picking a spec AT RANDOM, weighted by
#      AiPlayerbot.RandomClassSpecProb.<class>.<spec>; then
#   2. calls InitEquipment(), which builds a StatsWeightCalculator whose
#      constructor's first act is `tab = AiFactory::GetPlayerSpecTab()`.
#
# So gear is downstream of the spec roll. You cannot fix it afterwards:
# `talents spec <name>` calls InitTalentsBySpecNo() + InitGlyphs() and
# never re-runs InitEquipment, so respeccing a geared bot leaves it
# wearing gear chosen for a spec it no longer has. Silent, and it reads
# as "the bots are weak" months later.
#
# The only lever is the roll itself. This script forces
# RandomClassSpecProb to 100% of the wanted spec for each class in a
# pass, so `init=` becomes deterministic, then restores the stock
# distribution afterwards.
#
# THE OTHER HALF: EquipAndSpecPersistence
#
# Randomize() only calls resetTalents() and ClearAllItems() when
# EquipAndSpecPersistence is 0 (or the character is below
# EquipAndSpecPersistenceLevel). Shipped as 1 / level 1, so at level 70
# neither ever fires — `init=` cannot undo an existing talent build. That
# is correct for the roster (gear and specs survive relogs, so gearing is
# a one-time cost) but it means a character whose talents were set by
# something else — notably the GM command `.learn all my talents`, which
# fills all three trees — can never be re-specced by `init=`, and its
# gear will keep tracking whichever tree happens to hold the most points.
#
# So a pass turns persistence OFF for the duration and back ON at the
# end. `restore` is not optional cleanup; leaving persistence at 0 means
# every bot re-rolls its spec and gear on login.
#
# Multiple passes are needed because the roster wants two shamans and two
# mages on different specs, and two paladins and two warriors split across
# tank and non-tank specs — one probability table cannot express any of
# that at once. Each pass is the largest set of classes whose wanted specs
# happen not to collide, which is why the roster's shape decides how the
# passes are split rather than the other way round.
#
# Usage (inside the LXC; root or acore):
#   /opt/hprv/scripts/gear-pass.sh master    # the human, per roster.conf MASTER_*
#                                            #   REFUSES by default since ADR 0014 —
#                                            #   Bullwark is already built and holds
#                                            #   the only hand-verified defence set
#   /opt/hprv/scripts/gear-pass.sh tank      # BOT_01 paladin -> prot (off-tank)
#   /opt/hprv/scripts/gear-pass.sh offtank   # BOT_09 warrior -> prot   (DORMANT)
#   /opt/hprv/scripts/gear-pass.sh a         # shaman/mage/hunter/priest/rogue
#   /opt/hprv/scripts/gear-pass.sh b         # 2nd shaman, 2nd mage     (DORMANT)
#   /opt/hprv/scripts/gear-pass.sh c         # enh shaman, resto druid, destro lock
#   /opt/hprv/scripts/gear-pass.sh restore   # stock probabilities, persistence back on
#   /opt/hprv/scripts/gear-pass.sh show      # what is set right now
#   /opt/hprv/scripts/gear-pass.sh tier kara # set the progression cap for a raid tier
#
# Passes are split by SPEC COLLISION, not by convenience: one
# RandomClassSpecProb table cannot say "resto for that shaman,
# enhancement for this one" at the same time. The roster holds two
# shamans on different specs, two mages on different specs and two
# paladins on different specs, so the roster's shape decides the split
# rather than the other way round. Two passes are currently DORMANT
# (`offtank`, `b`) because ADR 0014 benched every bot they geared; they
# are kept intact because un-benching is meant to be one line.
#
# Passes a/b take an optional gearscore: `gear-pass.sh a 183` prints
# `init=183` instead of `init=epic`, capping the gear it hands out.
#
# GEARSCORE MATHS. `init=<gs>` caps items at gs, where an item scores
# ItemLevel * a quality multiplier (PlayerbotAI::GetItemScoreMultiplier:
# poor 1.0, normal 1.1, uncommon 1.21, rare 1.331, epic 1.4641,
# legendary 1.61051 — each step is 1.1x). So for an EPIC of item level L
# to pass, gs must be at least L * 1.4641. `tier` does that arithmetic
# from the TBC phase table in playerbots.conf and prints the number.
#
# It edits config ONLY. It cannot run the in-game half — `.playerbots
# bot` is registered Console::No, so it must be typed by a logged-in
# character. Each pass prints exactly what to type.
#
# BOTH reload commands are required, in order. `.playerbots bot reload`
# calls PlayerbotAIConfig::Initialize(), which reads via
# sConfigMgr->GetOption() — i.e. from values ConfigMgr has held in memory
# since worldserver startup. On its own it re-applies stale values and
# your edits here do nothing. `.reload config` calls
# sWorld->LoadConfigSettings(true) -> sConfigMgr->Reload() ->
# LoadModulesConfigs(), which is what actually re-reads the file. The
# pair still avoids the ~6-minute restart.
#
set -euo pipefail

CONF="${HPRV_PB_CONF:-/mnt/hprv/server/etc/modules/playerbots.conf}"
DIST="${HPRV_PB_DIST:-/mnt/hprv/server/etc/modules/playerbots.conf.dist}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROSTER="${HPRV_ROSTER:-${SCRIPT_DIR}/roster.conf}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -w "$CONF" ]] || die "cannot write $CONF (run as root or acore)"
[[ -r "$DIST" ]] || die "cannot read $DIST — needed to restore stock values"

# class id -> name, for the messages
declare -A CLASS_NAME=( [1]=warrior [2]=paladin [3]=hunter [4]=rogue [5]=priest
                        [6]=dk [7]=shaman [8]=mage [9]=warlock [11]=druid )

# Spec indices are positional within AiPlayerbot.PremadeSpecName.<class>.*
# Dump them with:
#   grep -E '^AiPlayerbot\.PremadeSpecName\.' "$CONF"
# MAX_SPECNO is 7; classes with fewer just have no matching key.
MAX_SPEC=6

backup_once() {
    local stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONF" "${CONF}.${stamp}.bak"
    printf 'backed up -> %s\n' "${CONF}.${stamp}.bak"
}

set_key() {  # set_key <key> <value>
    local key="$1" val="$2"
    if grep -qE "^${key//./\\.} *=" "$CONF"; then
        sed -i "s|^${key//./\\.} *=.*|${key} = ${val}|" "$CONF"
    else
        printf '%s = %s\n' "$key" "$val" >> "$CONF"
    fi
}

get_key() {  # get_key <file> <key>
    grep -E "^${1//./\\.} *=" "$2" 2>/dev/null | head -1 | sed 's/.*= *//' || true
}

# force_spec <classId> <specIndex> — 100% that spec, 0% everything else
force_spec() {
    local cls="$1" want="$2" i
    for ((i=0; i<=MAX_SPEC; i++)); do
        local key="AiPlayerbot.RandomClassSpecProb.${cls}.${i}"
        grep -qE "^${key//./\\.} *=" "$CONF" || continue
        if [[ "$i" == "$want" ]]; then set_key "$key" 100; else set_key "$key" 0; fi
    done
    printf '  %-8s -> spec index %s (%s)\n' "${CLASS_NAME[$cls]}" "$want" \
        "$(get_key "AiPlayerbot.PremadeSpecName.${cls}.${want}" "$CONF")"
}

# class_id <class name> -> numeric class id, empty if unknown. The inverse
# of CLASS_NAME, so roster.conf can say "druid" instead of 11.
class_id() {
    local want="${1,,}" k
    for k in "${!CLASS_NAME[@]}"; do
        [[ "${CLASS_NAME[$k]}" == "$want" ]] && { printf '%s' "$k"; return 0; }
    done
    return 1
}

# spec_index <classId> <spec name> -> positional index within
# PremadeSpecName.<class>.*, empty if no exact match. Looking it up beats
# hardcoding, because the indices differ per class and are only
# discoverable from the conf — druid resto is 2, paladin prot is 1,
# warrior prot is 2.
spec_index() {
    local cls="$1" want="$2" i
    for ((i=0; i<=MAX_SPEC; i++)); do
        if [[ "$(get_key "AiPlayerbot.PremadeSpecName.${cls}.${i}" "$CONF")" == "$want" ]]; then
            printf '%s' "$i"; return 0
        fi
    done
    return 1
}

roster_name() {  # roster_name <slot>  -> name or empty
    [[ -r "$ROSTER" ]] || return 0
    # shellcheck disable=SC1090
    ( . "$ROSTER"; eval "printf '%s' \"\${BOT_${1}_NAME:-}\"" )
}

roster_field() {  # roster_field <slot> <FIELD>  -> value or empty
    [[ -r "$ROSTER" ]] || return 0
    # shellcheck disable=SC1090
    ( . "$ROSTER"; eval "printf '%s' \"\${BOT_${1}_${2}:-}\"" )
}

# resolve_slot <slot> -> "<classId> <specIndex>", or dies.
#
# Looks both up from roster.conf rather than hardcoding indices, so a
# pass follows the file when a slot changes class instead of silently
# gearing the new body for the old slot's spec. Dies loudly on an unknown
# class or an unrecognised spec name — a wrong string in roster.conf must
# never degrade into a random roll, which is the exact failure mode this
# whole script exists to remove (ADR 0007).
resolve_slot() {
    local slot="$1" cls spec cid sidx
    cls="$(roster_field "$slot" CLASS)"
    spec="$(roster_field "$slot" SPEC)"
    [[ -n "$cls" && -n "$spec" ]] || die "roster.conf BOT_${slot} has no CLASS/SPEC"
    cid="$(class_id "$cls")" || die "BOT_${slot}: unknown class '$cls'"
    sidx="$(spec_index "$cid" "$spec")" || die \
        "BOT_${slot}: '$spec' is not a PremadeSpecName for $cls — dump them with:
  grep -E '^AiPlayerbot\.PremadeSpecName\.${cid}\.' $CONF"
    printf '%s %s' "$cid" "$sidx"
}

# force_slots <slot>... — resolve EVERY slot before writing ANY of them.
#
# The two steps are separate on purpose. force_spec edits the config in
# place, so resolving lazily would let a typo in the last slot abort a
# pass that had already rewritten the probability table for the first two
# — recoverable via `restore` and the backup, but a confusing state to
# land in mid-gearing. Validate first, then commit.
force_slots() {
    local slot resolved=()
    for slot in "$@"; do resolved+=( "$(resolve_slot "$slot")" ); done
    local i=0
    for slot in "$@"; do
        # shellcheck disable=SC2086
        force_spec ${resolved[$i]}
        i=$((i+1))
    done
}

join_names() {  # join_names <slot> <slot> ... -> comma list of non-empty names
    local out="" n
    for s in "$@"; do
        n="$(roster_name "$s")"
        [[ -n "$n" ]] && out="${out:+$out,}$n"
    done
    printf '%s' "$out"
}

banner() { printf '\n=== %s ===\n' "$1"; }

# TBC phase item-level caps, quoted from the AutoGearScoreLimit comment
# block in playerbots.conf. These are the ceiling for each raid tier.
tier_ilvl() {
    case "$1" in
        kara|t4|p1) echo 125 ;;   # Karazhan, Gruul, Magtheridon
        p2|ssc|tk|za) echo 141 ;; # SSC, Tempest Keep, Zul'Aman
        p3|hyjal|bt) echo 156 ;;  # Hyjal, Black Temple
        p4|swp|sunwell) echo 164 ;;
        *) echo "" ;;
    esac
}

# epic multiplier is 1.4641; round to nearest integer
gs_for_ilvl() { awk -v l="$1" 'BEGIN{printf "%d", int(l*1.4641 + 0.5)}'; }

# init_cmd <gearscore-or-empty> -> "init=epic" or "init=<gs>"
init_cmd() { [[ -n "${1:-}" ]] && printf 'init=%s' "$1" || printf 'init=epic'; }

# The slot passes below were written against the archive-era roster.conf
# slot order (BOT_01 = prot paladin, BOT_09 = Netohje, ...). roster.conf
# was rebuilt 2026-09-26 (TODO item 1), so every slot index now names a
# different character. Running them would force the wrong spec onto the
# wrong body. TODO item 2 replaces them. Until then they refuse.
case "${1:-}" in
    tank|offtank|a|b|c)
        [[ "${HPRV_ALLOW_STALE_SLOTS:-0}" == "1" ]] || die "pass '${1}' uses pre-2026-09-26 slot numbers that no longer match roster.conf — see TODO.md item 2 (override: HPRV_ALLOW_STALE_SLOTS=1)" ;;
esac

case "${1:-}" in

master)
    # Driven by MASTER_CLASS / MASTER_SPEC in roster.conf rather than
    # hardcoded, because the human's class has not been fixed for the life
    # of the project — 0010 moved the tank to a bot and the master became a
    # resto druid, then 0014 reversed both. Defaults to warrior / prot pve.
    #
    # GUARD ADDED 2026-08-12 (ADR 0014). This pass ends in `initself=`,
    # which clears the character's bags, spells, skills, talents and quests
    # before re-rolling. On a fresh character that is the point; on Bullwark
    # it destroys the only hand-verified defence itemization in the raid —
    # ADR 0008's four-item list was computed against him and he is the body
    # the whole raid's survival now rests on. Nothing else in this script
    # is destructive to an already-built character, so this is the one pass
    # that asks first.
    if [[ -z "${HPRV_ALLOW_MASTER_REROLL:-}" ]]; then
        M_NAME_CHK="$( . "$ROSTER" 2>/dev/null; printf '%s' "${MASTER_NAME:-}" )"
        cat >&2 <<EOF
refusing to re-roll the master${M_NAME_CHK:+ ($M_NAME_CHK)}.

This pass prints an \`initself=\` line, which WIPES bags, spells, skills,
talents and quests. Since ADR 0014 the master is the raid's main tank and
carries hand-picked defence gear that \`initself=\` would destroy — and
that gear is not reproducible from any script.

Run it only on a character you intend to rebuild from nothing:

  HPRV_ALLOW_MASTER_REROLL=1 gear-pass.sh master [gearscore]

If you only want to CHECK the tank's defence, you want:

  roster-status.sh          # .save in game first — it reads last-saved state
EOF
        exit 1
    fi
    backup_once
    M_CLASS="$( . "$ROSTER" 2>/dev/null; printf '%s' "${MASTER_CLASS:-warrior}" )"
    M_SPEC="$(  . "$ROSTER" 2>/dev/null; printf '%s' "${MASTER_SPEC:-prot pve}" )"
    M_NAME="$(  . "$ROSTER" 2>/dev/null; printf '%s' "${MASTER_NAME:-the master}" )"
    M_CID="$(class_id "$M_CLASS")" || die "unknown MASTER_CLASS '$M_CLASS' in $ROSTER"
    M_SIDX="$(spec_index "$M_CID" "$M_SPEC")" || die \
        "MASTER_SPEC '$M_SPEC' is not a PremadeSpecName for $M_CLASS — dump them with:
  grep -E '^AiPlayerbot\.PremadeSpecName\.${M_CID}\.' $CONF"
    banner "pass: master (${M_NAME} -> ${M_CLASS} ${M_SPEC})"
    force_spec "$M_CID" "$M_SIDX"
    set_key AiPlayerbot.EquipAndSpecPersistence 0
    printf '  EquipAndSpecPersistence -> 0 (so initself actually resets talents and items)\n'
    GS="${2:-}"
    SELF="initself=epic"
    [[ -n "$GS" ]] && SELF="initself=${GS}"
    cat <<EOF

Now, in game as ${M_NAME}:

  .reload config                     <- re-reads playerbots.conf FROM DISK
  .playerbots bot reload             <- re-applies it into PlayerbotAIConfig
  .reset talents                     <- clears any stray talent fill
  .playerbots bot ${SELF}
                                     <- full reset: talents, spells, skills,
                                        quests and bags are wiped, then rebuilt
                                        as ${M_SPEC} with matching gear
  .reset talents                     <- refund the 61 points; the gear STAYS

You now have ${M_SPEC} gear and an empty talent tree to spend by hand,
which is the point. Gear is only ever chosen by init=/initself; changing
talents afterwards never strips it.

initself= wipes QUESTS as well as bags. Attunements are re-granted by the
factory's InitAttunementQuests(), but if you are mid-lockout check you
still hold what the raid door wants before you rely on it.
EOF
    # The defence floor only applies if the master is actually tanking.
    # Since decisions/0010 the main tank is a bot, so for a resto druid
    # master this whole section is noise.
    if [[ -n "$GS" ]] && [[ "$M_SPEC" == prot* || "$M_SPEC" == bear* ]]; then
        cat <<'EOF'

TANK FLOOR — CHECK THIS AFTER RE-ROLLING.

A tank is the one raid member that cannot simply be scaled down. At
level 70 a raid boss is level 73, and avoiding crits from it requires
490 defence skill. Base defence at 70 is 350, so you need 140 skill from
gear, and at level 70 it takes ~2.37 defence rating per point of skill —
about 332 defence rating. Below that the boss crits and crushes you and
no amount of healing holds it together.

Threat is the easier half: at this tier it comes from the prot tree,
Defiance and Shield Slam, not from item level.

Verify with roster-status.sh, which reports the tank's defence and warns
if the re-roll dropped you under the cap. Run `.save` first — that report
reads last-saved state, so hand-equipped items are invisible until then.

IF IT WENT UNDER, HAND-PICK THE DEFENCE PIECES. Do not step up a tier
(ADR 0008). InitEquipment scores raw stats through StatsWeightCalculator,
which knows nothing about defence skill or its cap, so it fills trinkets,
neck and shield with zero-defence items. The budget is not the problem:
at item level 133 the best available pieces total ~516 defence rating
against the 332 needed. Tier-stepping scales the wrong variable —
projected out, even Sunwell-tier gear still lands under 490.

  .additem 30629    # Scarab of Displacement           trinket  +42
  .additem 32534    # Brooch of the Immortal King      trinket  +32
  .additem 30099    # Frayed Tether of the Drowned     neck     +24
  .additem 27887    # Platinum Shield of the Valorous  shield   +24

Equip, then .save. Guardian's Alchemist Stone (+54) and Figurine -
Empyrean Tortoise (+42) score better and are profession-gated; skip them.
EOF
    fi
    printf '\nWhen you are done, run:  gear-pass.sh restore\n'
    ;;

tank)
    # BOT_01, the prot paladin. Separate from pass A because A forces
    # paladin to holy for Nathos, and one probability table cannot say
    # "holy for that paladin, prot for this one" at the same time.
    #
    # RENAMED IN ROLE, NOT IN SPEC, 2026-08-12 (ADR 0014). He is the
    # OFF-TANK now, not the main tank — the human main-tanks again. His
    # spec, gear and defence floor are unchanged; what changed is that he
    # must be converted out of tankhood in the AI afterwards. The pass
    # prints that step; do not skip it.
    backup_once
    banner "pass: tank (BOT_01 paladin -> protection, off-tank)"
    force_spec 2 1                      # paladin: prot pve
    set_key AiPlayerbot.EquipAndSpecPersistence 0
    printf '  EquipAndSpecPersistence -> 0\n'
    name="$(roster_name 01)"
    IC="$(init_cmd "${2:-}")"
    printf '\nNow, in game:\n\n  .reload config\n  .playerbots bot reload\n'
    if [[ -n "$name" ]]; then
        printf '  .playerbots bot %s %s\n' "$IC" "$name"
    else
        printf '  .playerbots bot %s <the paladin name>\n' "$IC"
        printf '\n  (roster.conf BOT_01 is empty — run `.playerbots bot addclass\n'
        printf '   paladin`, take the name from `.playerbots bot list`, write it\n'
        printf '   into BOT_01_NAME, and this prints the line for you)\n'
    fi
    cat <<'EOF'

Then: gear-pass.sh restore, and both reloads again.

*** THEN CONVERT HIM OUT OF TANKHOOD — ONE WHISPER, ONCE. ***

  /w Ararin co -tank,-tank assist,+dps,+dps assist
  /w Ararin nc -tank assist,+dps assist

WITHOUT THIS HE TAUNTS BOSSES OFF THE HUMAN TANK ON COOLDOWN, FOREVER.
That is not a tuning problem and no threat setting reaches it (ADR 0014,
promoting the corollary appended to ADR 0013):

  LoseAggroTrigger = !AI_VALUE2(bool, "has aggro", "current target")
                                              GenericTriggers.cpp:110
  -> NextAction("hand of reckoning", ACTION_HIGH + 7)
                                       TankPaladinStrategy.cpp:116-123

A bot tank's `tank assist` strategy points it at the MASTER's target. So
while the human holds that target the bot never has aggro, the trigger is
permanently satisfied, and it fires a taunt at near-top action priority
every time the cooldown is up.

The whisper clears STRATEGY_TYPE_TANK, carried by both `tank` and
`tank assist` (TankAssistStrategy.h:20), so IsTank() goes false for him.
That ends the taunt loop, the retarget onto the human's target, and the
two-tank ThreatValue mute, all three, in one line.

He KEEPS his prot talents, his gear and his crit immunity. He off-tanks
by damage threat — Consecration and Holy Shield hold adds fine when
nobody else is on them — and does modest single-target damage otherwise.

DO NOT whisper him `co -threat`. That was ADR 0013's fix for TWO BOT
tanks measuring each other through ThreatValue. With the human as the
only body IsTank() accepts, that calculation finds a real tank and the
global +threat cap works as intended.

DO NOT flag him main tank or assist tank in the raid frame. The human is
the tank, and IsTank() is true for a human prot warrior via the spec
fallback, so an unflagged raid resolves to him correctly.

THE OVERRIDE PERSISTS. `co` writes the bot's whole strategy list to
playerbots_db_store, where it outranks AiFactory's spec defaults AND
AiPlayerbot.CombatStrategies from then on. Apply it once, not nightly —
and `co !` him BEFORE ever re-running this pass, or he returns with a
frozen strategy list and nothing warns you.

TANK FLOOR — the bot will NOT be crit-immune off this pass. It still
applies to him as an off-tank: he eats add melee for whole packs.

StatsWeightCalculator scores raw stats and has no concept of defence
skill, so the factory fills trinkets, neck and shield with zero-defence
pieces (ADR 0008). Check it:

  roster-status.sh          <- reports defence on the tank slot

THERE IS NO `equip` CHAT COMMAND. Do not try to whisper one.

The action exists (ChatActionContext.h registers "equip" ->
EquipAction), but ChatCommandHandlerStrategy's supported list contains
only "equip upgrade" and "glyph equip" — bare "equip" is absent from all
90 entries. So the whisper is parsed by nothing and silently discarded,
no error, no hint. `equip upgrade` is no help either: it runs the same
StatsWeightCalculator that ignored defence in the first place.

Fixing a bot's defence therefore means a direct inventory swap, with the
bot LOGGED OUT (`.playerbots bot remove <name>`) or the in-memory copy
overwrites the DB on next save.

  1. Find what is actually equipped first. Do NOT assume the four items
     from the Bullwark list are all upgrades — the factory often hands
     out a good shield (e.g. Aldori Legacy Defender, ilvl 125, 13 def)
     that beats Platinum Shield of the Valorous (ilvl 112, 24 def) on
     everything but defence. Usually only the TRINKETS are wrong,
     because the scorer fills them with pure DPS pieces at 0 defence.

     SELECT ci.slot, ii.itemEntry, it.name FROM characters c
       JOIN character_inventory ci ON ci.guid=c.guid
       JOIN item_instance ii ON ii.guid=ci.item
       JOIN acore_world.item_template it ON it.entry=ii.itemEntry
      WHERE c.name='<bot>' AND ci.bag=0 AND ci.slot<=18 ORDER BY ci.slot;

  2. Trade the wanted items over so they exist in the bot's bags, then
     swap by ITEM GUID via a free backpack slot (34-38 are usually
     free). Never swap two rows directly — (guid,bag,slot) is unique and
     will collide mid-statement.

     START TRANSACTION;
     UPDATE character_inventory SET slot=34 WHERE item=<old trinket1>;
     UPDATE character_inventory SET slot=35 WHERE item=<old trinket2>;
     UPDATE character_inventory SET slot=12 WHERE item=<new trinket1>;
     UPDATE character_inventory SET slot=13 WHERE item=<new trinket2>;
     COMMIT;

     Equipment slots: 1 neck, 12/13 trinkets, 15 mainhand, 16 offhand.

  3. Re-add the bot and re-check. 490 skill is the floor, and the sum
     above counts item_template base stats only — gems and enchants are
     not in it, so the real figure is >= what you compute.

ONGOING HAZARD: AutoEquipUpgradeLoot = 1 means a higher-SCORING trinket
dropping in the raid can knock a defence trinket back out, silently
dropping the tank under 490. Re-check after loot.
EOF
    ;;

offtank)
    # *** DORMANT since 2026-08-12 (ADR 0014). ***
    # BOT_09 (Netohje) is benched: 0014 removed the second-tank
    # requirement along with Zul'Aman as a target. The pass is kept intact
    # because un-benching is meant to cost one line.
    #
    # IF YOU EVER RUN IT AGAIN ALONGSIDE A HUMAN TANK, he needs the same
    # conversion the `tank` pass prints —
    #   /w Netohje co -tank,-tank assist,+arms,+dps assist
    #   /w Netohje nc -tank assist,+dps assist
    # — and for a warrior it matters MORE, not less: his taunt sits at
    # ACTION_INTERRUPT + 1 (TankWarriorStrategy.cpp:217-224), a higher
    # priority than the paladin's ACTION_HIGH + 7. Otherwise the human
    # stands down and this becomes a real bot tank again.
    #
    # The SECOND tank, added for Zul'Aman (ADR 0012). Nalorakk's form swap
    # (NalorakkTanksPositionBossAction -> FirstAssistTankPositionBearForm)
    # and Halazzi's Spirit Lynx pickup both branch on
    # IsAssistTankOfIndex(bot, 0, true) — a bot self-check, so the off-tank
    # has to be a bot for exactly the reason the main tank does (ADR 0010).
    #
    # Separate from pass B for the same reason `tank` is separate from A:
    # pass B used to force warrior -> fury for this very character, and one
    # probability table cannot say fury for one warrior and prot for another.
    die "The 'offtank' pass is RETIRED.

Netohje, the prot warrior this pass geared, is no longer in the roster
(verified on the box 2026-08-13 — he was not among the 24). Slot BOT_09
now holds a hunter, so running this pass would force warrior->prot and
then gear the wrong character.

The raid's off-tanking is done by three CONVERTED plate bots — Ararin,
Crumm and Rechiw — which keep tank gear and crit immunity but are out of
tankhood in the AI. See CLAUDE.md rule 1 and roster.conf.

If you ever want a real bot tank back, the human must stand down first:
a bot tank and a human tank cannot share a raid at all."

    backup_once
    banner "pass: offtank (RETIRED)"
    force_spec 1 2                      # warrior: prot pve
    set_key AiPlayerbot.EquipAndSpecPersistence 0
    printf '  EquipAndSpecPersistence -> 0\n'
    name="$(roster_name 09)"
    IC="$(init_cmd "${2:-}")"
    printf '\nNow, in game:\n\n  .reload config\n  .playerbots bot reload\n'
    if [[ -n "$name" ]]; then
        printf '  .playerbots bot %s %s\n' "$IC" "$name"
    else
        printf '  .playerbots bot %s <the warrior name>\n' "$IC"
        printf '\n  (roster.conf BOT_09 is empty — fill it in and this prints the line)\n'
    fi
    cat <<'EOF'

Then: gear-pass.sh restore, and both reloads again.

FLAG HIM ASSIST TANK, INDEX 0 — and leave Ararin flagged MAIN TANK.
IsAssistTankOfIndex(bot, 0, true) resolves by raid-frame flag and group
order, so in an unflagged raid the Nalorakk bear-form position and the
Halazzi lynx pickup fall to whichever body happens to sort first — quite
possibly the main tank, who is already holding the boss.

TANK FLOOR — the same 490 as the main tank, and it genuinely applies here.
Nalorakk alternates troll and bear form and the fight is built as a tank
swap, so the off-tank eats boss melee for whole phases. Check it with:

  roster-status.sh          <- reports defence for ANY slot with role tank

THIS IS THE KNOWN ITEMIZATION CASE, not the harder one. ADR 0008's list was
computed against Bullwark — a prot warrior at Karazhan tier, which is
exactly what this character becomes — so unlike Ararin the paladin, it
transfers directly:

  .additem 30629    # Scarab of Displacement           trinket  +42
  .additem 32534    # Brooch of the Immortal King      trinket  +32
  .additem 30099    # Frayed Tether of the Drowned     neck     +24
  .additem 27887    # Platinum Shield of the Valorous  shield   +24

Still CHECK what the factory actually equipped before swapping any of it.
It may hand out a better shield, as it did for Ararin (Aldori Legacy
Defender, ilvl 125). Usually only the trinkets are wrong, both at zero
defence, because the scorer fills them with pure DPS pieces.

THERE IS NO `equip` CHAT COMMAND (ADR 0011). Fix by direct inventory swap
with the bot LOGGED OUT (`.playerbots bot remove <name>`), swapping by item
guid through a free backpack slot — never swap two rows directly, since
(guid,bag,slot) is unique and collides mid-statement. Then PARK THE LOSERS
IN THE BANK (slots 39-66): bags are re-scanned and re-equipped on any trade
or item pickup, the bank is not. Full procedure in docs/session.md.
EOF
    ;;

a)
    backup_once
    banner "pass A (resto shaman, arcane mage, hunter, priest, rogue)"
    force_spec 2 0                      # paladin: holy pve  — Nathos, benched;
                                        #   forced anyway so that swapping him
                                        #   back in is "add 01 to the line below"
                                        #   and nothing else (ADR 0014).
    force_spec 7 2                      # shaman:  resto pve
    force_spec 8 0                      # mage:    arcane pve
    force_spec 3 0                      # hunter:  bm pve
    force_spec 5 2                      # priest:  shadow pve
    force_spec 4 1                      # rogue:   combat pve
    set_key AiPlayerbot.EquipAndSpecPersistence 0
    printf '  EquipAndSpecPersistence -> 0\n'
    # BOT_01 (Nathos, holy paladin) left this line when 0014 benched him.
    # Add `01` back to it if he is swapped in for Krast — the healer note
    # in roster.conf explains when you would want that.
    names="$(join_names 02 03 05 06 08)"
    IC="$(init_cmd "${2:-}")"
    printf '\nNow, in game:\n\n  .reload config\n  .playerbots bot reload\n'
    if [[ -n "$names" ]]; then
        printf '  .playerbots bot %s %s\n' "$IC" "$names"
    else
        printf '  .playerbots bot %s <shaman1,mage1,hunter,priest,rogue>\n' "$IC"
        printf '\n  (roster.conf has no names yet — fill it in and this prints them for you)\n'
    fi
    printf '\nThen:  gear-pass.sh c %s\n' "${2:-}"
    ;;

c)
    # Added 2026-08-12 for the ADR 0014 roster. Three slots that could not
    # ride pass A: the shaman collides with Krast's resto (one probability
    # table, one shaman spec), and the druid and warlock are classes the
    # roster had never held — the human was the druid until 0014, and there
    # was never a warlock at all while Magtheridon was live content.
    #
    # This pass resolves class AND spec from roster.conf via force_slots
    # rather than hardcoding indices, because two of its three spec strings
    # were unverified when it was written: "enh pve" and "destro pve" are
    # the plausible names, not confirmed ones. force_slots validates all
    # three BEFORE writing any, and dies with the grep to run if one is
    # wrong — the correct failure. A hardcoded index would instead have
    # quietly geared the wrong spec, which is ADR 0007's whole subject.
    backup_once
    banner "pass C (enhancement shaman, resto druid, destruction warlock)"
    force_slots 07 11 12                # shaman enh, druid resto, warlock destro
    set_key AiPlayerbot.EquipAndSpecPersistence 0
    printf '  EquipAndSpecPersistence -> 0\n'
    names="$(join_names 07 11 12)"
    IC="$(init_cmd "${2:-}")"
    printf '\nNow, in game:\n\n  .reload config\n  .playerbots bot reload\n'
    if [[ -n "$names" ]]; then
        printf '  .playerbots bot %s %s\n' "$IC" "$names"
    else
        printf '  .playerbots bot %s <shaman2,druid,warlock>\n' "$IC"
    fi
    cat <<'EOF'

BOT_11 and BOT_12 are NEW DRAWS and start empty in roster.conf. Draw them
first or this pass has nothing to gear:

  .playerbots bot addclass druid
  .playerbots bot addclass warlock
  .playerbots bot list          <- take the two new names
                                   write them into BOT_11_NAME / BOT_12_NAME
                                   and commit BEFORE running this pass

SEHJECE IS BEING RE-ROLLED, NOT RESPECCED. `talents spec` never re-runs
InitEquipment (ADR 0007), so a respec would leave an enhancement shaman
in elemental caster mail. This pass is the only way across.

If he has ever taken a `co` whisper, reset it FIRST:

  /w Sehjece co !          <- rebuild strategies from spec defaults

`co` overrides persist in playerbots_db_store and outrank the spec
defaults, so a re-rolled bot otherwise comes back running the OLD spec's
strategies with no warning (ADR 0013, amended).

AFTERWARDS, expect to whisper him `co -aoe`. AiFactory.cpp:339 gives every
shaman spec the `aoe` strategy, and enhancement's Magma Totem and Fire
Nova put threat on everything the tank has not touched — from melee range.
This is the same fault that made elemental Sehjece pull adds; `+threat`
never covered it, because ThreatMultiplier only zeroes actions that
already carry a threat type and a pulsing totem is not one.
EOF
    printf '\nThen:  gear-pass.sh restore\n'
    ;;

b)
    # *** DORMANT since 2026-08-12 (ADR 0014). ***
    # Both bodies this pass gears left the raid: BOT_07 (Sehjece) moved from
    # elemental to enhancement and is in pass C now, and BOT_04 (Lomul, fire
    # mage) is benched — the roster wants one mage and Izri is arcane.
    # Kept intact because un-benching is meant to cost one line; if Lomul
    # returns, run this with `names` trimmed to 04 alone.
    #
    # The warrior LEFT this pass in ADR 0012. BOT_09 (Netohje) re-rolled
    # protection as the Zul'Aman assist tank, so forcing warrior -> fury here
    # would silently undo that and strip his hand-fixed defence itemization
    # the next time anyone re-ran pass B. He is gear-pass.sh offtank now.
    # If he is ever put back to fury DPS, move slot 09 and `force_spec 1 1`
    # back into this pass rather than running both.
    backup_once
    banner "pass B (second shaman, second mage) — DORMANT, both benched"
    force_spec 7 0                      # shaman:  ele pve
    force_spec 8 1                      # mage:    fire pve
    set_key AiPlayerbot.EquipAndSpecPersistence 0
    printf '  EquipAndSpecPersistence -> 0\n'
    names="$(join_names 07 04)"
    IC="$(init_cmd "${2:-}")"
    printf '\nNow, in game:\n\n  .reload config\n  .playerbots bot reload\n'
    if [[ -n "$names" ]]; then
        printf '  .playerbots bot %s %s\n' "$IC" "$names"
    else
        printf '  .playerbots bot %s <shaman2,mage2>\n' "$IC"
    fi
    printf '\nThen:  gear-pass.sh restore\n'
    ;;

restore)
    backup_once
    banner "restoring stock spec probabilities and re-enabling persistence"
    n=0
    while read -r key; do
        val="$(get_key "$key" "$DIST")"
        [[ -n "$val" ]] || continue
        set_key "$key" "$val"
        n=$((n+1))
    done < <(grep -oE '^AiPlayerbot\.RandomClassSpecProb\.[0-9]+\.[0-9]+' "$DIST" | sort -u)
    printf '  restored %s RandomClassSpecProb keys from the .dist\n' "$n"

    for k in AiPlayerbot.EquipAndSpecPersistence AiPlayerbot.EquipAndSpecPersistenceLevel; do
        v="$(get_key "$k" "$DIST")"
        [[ -n "$v" ]] && { set_key "$k" "$v"; printf '  %s -> %s\n' "$k" "$v"; }
    done
    cat <<'EOF'

Now, in game:

  .reload config
  .playerbots bot reload

Persistence back on means gear and specs survive relogs — gearing was a
one-time cost, not a per-session one. Verify with:

  /opt/hprv/scripts/roster-status.sh
EOF
    ;;

tier)
    ilvl="$(tier_ilvl "${2:-}")"
    if [[ -z "$ilvl" ]]; then
        printf 'usage: gear-pass.sh tier <kara|p2|p3|p4>\n\n' >&2
        printf '  kara / t4 / p1   ilvl 125   Karazhan, Gruul, Magtheridon\n' >&2
        printf '  p2  / ssc / tk   ilvl 141   SSC, Tempest Keep, Zul Aman\n' >&2
        printf '  p3  / hyjal / bt ilvl 156   Hyjal, Black Temple\n' >&2
        printf '  p4  / sunwell    ilvl 164   Sunwell Plateau\n' >&2
        exit 1
    fi
    gs="$(gs_for_ilvl "$ilvl")"
    backup_once
    banner "progression cap -> ${2} (item level ${ilvl})"
    set_key AiPlayerbot.AutoGearScoreLimit "$ilvl"
    printf '  AutoGearScoreLimit -> %s\n' "$ilvl"
    printf '  matching init gearscore for epics: %s  (%s x 1.4641)\n' "$gs" "$ilvl"
    cat <<EOF

AutoGearScoreLimit caps what bots will EQUIP from drops, so from here on
they progress by raiding rather than by being handed gear. It does not
strip what they already wear — autogear only ever upgrades.

To actually reset the roster DOWN to this tier, re-roll it with the
matching gearscore. That re-rolls specs too, so it needs both passes:

  gear-pass.sh a ${gs}        # then both reloads + the printed init=${gs}
  gear-pass.sh b ${gs}        # then both reloads + the printed init=${gs}
  gear-pass.sh restore        # then both reloads

Then in game:  .reload config  &&  .playerbots bot reload

Note: 'restore' deliberately leaves AutoGearScoreLimit alone. It is a
progression setting you chose, not a leftover from a pass.
EOF
    ;;

show)
    printf 'conf: %s\n\n' "$CONF"
    printf '%-46s %s\n' "AiPlayerbot.EquipAndSpecPersistence" "$(get_key AiPlayerbot.EquipAndSpecPersistence "$CONF")"
    printf '%-46s %s\n' "AiPlayerbot.EquipAndSpecPersistenceLevel" "$(get_key AiPlayerbot.EquipAndSpecPersistenceLevel "$CONF")"
    lim="$(get_key AiPlayerbot.AutoGearScoreLimit "$CONF")"
    printf '%-46s %s%s\n\n' "AiPlayerbot.AutoGearScoreLimit" "$lim" \
        "$([[ "$lim" == "0" ]] && echo '  (no cap — bots equip any upgrade)' || echo "  (init gearscore: $(gs_for_ilvl "$lim"))")"
    printf 'non-zero spec probabilities (what init= will roll):\n'
    grep -E '^AiPlayerbot\.RandomClassSpecProb\.' "$CONF" \
      | grep -vE '= *0 *$' \
      | while read -r line; do
            key="${line%% *}"; val="${line##*= }"
            cls="$(cut -d. -f3 <<<"$key")"; spec="$(cut -d. -f4 <<<"$key")"
            printf '  %-8s %-16s %s%%\n' "${CLASS_NAME[$cls]:-cls$cls}" \
                "$(get_key "AiPlayerbot.PremadeSpecName.${cls}.${spec}" "$CONF")" "$val"
        done
    ;;

*)
    # Prints the header block above as the usage text. The range ends one
    # line before `set -euo pipefail`; re-check it if the header grows.
    sed -n '2,94p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
