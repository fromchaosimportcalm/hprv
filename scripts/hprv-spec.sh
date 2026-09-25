#!/usr/bin/env bash
# hprv-spec.sh — switch one pool character's spec AND the gear to match.
#
#   hprv-spec.sh <character> <spec> [--mode human|bot] [--quality epic]
#   hprv-spec.sh <character> --show
#   hprv-spec.sh --list [class]
#
# Runs ON THE BOX (needs playerbots.conf and mysql).
#
# WHY THIS SCRIPT EXISTS
#
# A respec never re-gears. `.playerbots bot init=` picks a spec by
# AiPlayerbot.RandomClassSpecProb and THEN gears for whatever it rolled,
# so the only way to land a chosen spec with matching gear is to force the
# probability table to 100% for that spec first, run init=, and put the
# table back. Doing that by hand is six steps with two silent failure
# modes, and it is why gear-pass.sh existed. This generalises it to any
# character and any spec.
#
# WHAT IT CANNOT DO, AND WHY THERE IS NO WAY AROUND IT
#
# It cannot run the in-game commands for you. `.playerbots bot` is
# registered Console::No (PlayerbotCommandScript.cpp:36) and its handler
# opens with:
#
#     WorldSession* m_session = handler->GetSession();
#     if (!m_session) { "You may only add bots from an active session"; }
#
# So it needs a live WorldSession with a Player behind it. SOAP and RA
# both execute as console sessions and have neither — this is not a
# permission bit that can be flipped, and enabling SOAP does not help.
#
# What this script DOES automate is the part that actually goes wrong:
# the probability-table surgery (with backup and guaranteed restore), the
# stale `co` override deletion, the spec-name validation against the
# installed config, and the post-pass defence check. You paste three
# lines; it does the six fiddly things around them.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
POOL_CONF="${HPRV_POOL:-${SCRIPT_DIR}/pool.conf}"
PB_CONF="${HPRV_PB_CONF:-/mnt/hprv/server/etc/modules/playerbots.conf}"
ENV_FILE="${HPRV_ENV_FILE:-/etc/hprv/hprv.env}"

MODE="human"
QUALITY="epic"

die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARN:  %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

[[ -r "$POOL_CONF" ]] || die "cannot read $POOL_CONF"
[[ -r "$PB_CONF"   ]] || die "cannot read $PB_CONF"
[[ -r "$ENV_FILE"  ]] || die "cannot read $ENV_FILE (it is 640 root:acore — run as root or acore)"

# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
# shellcheck disable=SC1090
. "$POOL_CONF"

DB_CHARS="${ACORE_DB_CHARACTERS:-acore_characters}"
DB_PB="${ACORE_DB_PLAYERBOTS:-acore_playerbots}"

mysql_q() {
    mysql --default-character-set=utf8mb4 -N -B \
          -h"${ACORE_DB_HOST:-127.0.0.1}" -u"${ACORE_DB_USER:-acore}" \
          -p"${ACORE_DB_PASS:?ACORE_DB_PASS not set in $ENV_FILE}" -e "$1" 2>/dev/null
}

# --- class id <-> name -------------------------------------------------
declare -A CLASS_ID=(
    [warrior]=1 [paladin]=2 [hunter]=3 [rogue]=4  [priest]=5
    [dk]=6      [shaman]=7  [mage]=8   [warlock]=9 [druid]=11
)

# In-game commands are collected and printed as an ordered paste block.
CMDS=()
queue() { CMDS+=("$1"); }

flush_cmds() {
    local c
    info ""
    for c in "${CMDS[@]}"; do info "    $c"; done
    info ""
    CMDS=()
}

# --- pool lookup -------------------------------------------------------
pool_line() {
    printf '%s\n' "$POOL" | grep -iE "^${1}:" | head -1 || true
}

pool_field() { printf '%s\n' "$1" | cut -d: -f"$2"; }

list_pool() {
    local filter="${1:-}"
    printf '%-14s %-8s %-14s %s\n' NAME CLASS HOME-SPEC OFFSPECS
    printf '%s\n' "--------------------------------------------------------------------------"
    printf '%s\n' "$POOL" | grep -E '^[A-Za-z]' | while IFS=: read -r n c h o s; do
        [[ -n "$filter" && "$c" != "$filter" ]] && continue
        printf '%-14s %-8s %-14s %s%s\n' "$n" "$c" "$h" "${o//|/, }" \
            "$([[ "$s" == "needs-init" ]] && printf '   [needs-init]')"
    done
}

# --- spec index resolution --------------------------------------------
# Reads AiPlayerbot.PremadeSpecName.<class>.<idx> straight out of the
# installed config. Never hardcode these — they are pin-specific.
spec_index() {
    local cid="$1" spec="$2"
    grep -E "^AiPlayerbot\.PremadeSpecName\.${cid}\.[0-9]+ *= *${spec}$" "$PB_CONF" \
      | head -1 | sed -E "s/^AiPlayerbot\.PremadeSpecName\.${cid}\.([0-9]+).*/\1/" || true
}

spec_list_for_class() {
    grep -E "^AiPlayerbot\.PremadeSpecName\.${1}\.[0-9]+ *=" "$PB_CONF" \
      | sed -E 's/.*= *//' | grep -v pvp | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}

# --- probability table -------------------------------------------------
PB_BACKUP=""
backup_conf() {
    PB_BACKUP="${PB_CONF}.hprv-spec.$(date +%Y%m%d-%H%M%S).bak"
    cp -p "$PB_CONF" "$PB_BACKUP"
    info "  backup: $PB_BACKUP"
}

force_spec_prob() {
    local cid="$1" want="$2" idx
    # Every PvE and PvP index for this class -> 0, then the wanted one -> 100.
    while read -r idx; do
        sed -i -E "s/^(AiPlayerbot\.RandomClassSpecProb\.${cid}\.${idx} *= *).*/\10/" "$PB_CONF"
    done < <(grep -E "^AiPlayerbot\.RandomClassSpecProb\.${cid}\.[0-9]+ *=" "$PB_CONF" \
             | sed -E "s/^AiPlayerbot\.RandomClassSpecProb\.${cid}\.([0-9]+).*/\1/")
    sed -i -E "s/^(AiPlayerbot\.RandomClassSpecProb\.${cid}\.${want} *= *).*/\1100/" "$PB_CONF"
}

# EquipAndSpecPersistence gates BOTH resetTalents() and InitTalentsTree()
# inside PlayerbotFactory (lines 625, 691). With it on, a level-70 bot runs
# init=, gets re-geared, and keeps its OLD SPEC — silently. It is also why
# specNo stops being written. gear-pass.sh has always turned it off for a
# pass; this must too.
set_key() {
    local key="$1" val="$2"
    if grep -qE "^AiPlayerbot\.${key} *=" "$PB_CONF"; then
        sed -i -E "s/^(AiPlayerbot\.${key} *= *).*/\1${val}/" "$PB_CONF"
    else
        printf 'AiPlayerbot.%s = %s\n' "$key" "$val" >> "$PB_CONF"
    fi
}

restore_conf() {
    [[ -n "$PB_BACKUP" && -r "$PB_BACKUP" ]] || return 0
    cp -p "$PB_BACKUP" "$PB_CONF"
    info "  restored $PB_CONF from backup"
}

# --- character state ---------------------------------------------------
char_guid()  { mysql_q "SELECT guid FROM ${DB_CHARS}.characters WHERE name='${1}';"; }
char_online(){ mysql_q "SELECT online FROM ${DB_CHARS}.characters WHERE name='${1}';"; }

has_co_override() {
    local g="$1"
    [[ -n "$(mysql_q "SELECT 1 FROM ${DB_PB}.playerbots_db_store WHERE guid=${g} AND \`key\`='co' LIMIT 1;")" ]]
}

clear_co_override() {
    local g="$1"
    mysql_q "DELETE FROM ${DB_PB}.playerbots_db_store WHERE guid=${g} AND \`key\`='co';"
}

defence_skill() {
    # Same shape as roster-status.sh: defence RATING off equipped items,
    # converted to skill. 490 is crit-immunity vs a level 73 boss.
    local g="$1" rating
    rating=$(mysql_q "
      SELECT COALESCE(SUM(
        CASE WHEN t.stat_type1=12 THEN t.stat_value1 ELSE 0 END +
        CASE WHEN t.stat_type2=12 THEN t.stat_value2 ELSE 0 END +
        CASE WHEN t.stat_type3=12 THEN t.stat_value3 ELSE 0 END +
        CASE WHEN t.stat_type4=12 THEN t.stat_value4 ELSE 0 END +
        CASE WHEN t.stat_type5=12 THEN t.stat_value5 ELSE 0 END +
        CASE WHEN t.stat_type6=12 THEN t.stat_value6 ELSE 0 END +
        CASE WHEN t.stat_type7=12 THEN t.stat_value7 ELSE 0 END +
        CASE WHEN t.stat_type8=12 THEN t.stat_value8 ELSE 0 END +
        CASE WHEN t.stat_type9=12 THEN t.stat_value9 ELSE 0 END +
        CASE WHEN t.stat_type10=12 THEN t.stat_value10 ELSE 0 END),0)
      FROM ${DB_CHARS}.character_inventory i
      JOIN ${DB_CHARS}.item_instance ii ON ii.guid=i.item
      JOIN ${ACORE_DB_WORLD:-acore_world}.item_template t ON t.entry=ii.itemEntry
      WHERE i.guid=${g} AND i.bag=0 AND i.slot < 19;")
    rating="${rating:-0}"
    # MUST match roster-status.sh's defence_line() or the two reports will
    # disagree about whether a tank is crit-immune.
    awk -v r="$rating" 'BEGIN{printf "%d", 350 + int(r/2.37)}'
}

is_tank_spec() {
    case "$1" in
        "prot pve"|"prot pvp"|"bear pve"|"blood pve"|"double aura blood pve") return 0 ;;
        *) return 1 ;;
    esac
}

is_plate_or_bear() {
    case "$1" in warrior|paladin|dk|druid) return 0 ;; *) return 1 ;; esac
}

# The rule-1 conversion, per class. Two whispers: IsTank() is
# ContainsStrategy(STRATEGY_TYPE_TANK) across ALL engines, and `tank
# assist` is itself TANK-typed, so the non-combat copy must go too. The
# class tank strategy is named differently per class (DK `blood`, druid
# `bear`), and each needs a DPS rotation put back in its place: warriors
# have no `dps` strategy, so a bare `-tank` left them with no rotation at all.
# Read from AiFactory.cpp / *AiObjectContext.cpp at the pin, 2026-09-26.
convert_co() {
    case "$1" in
        warrior) echo "co -tank,-tank assist,+arms,+dps assist" ;;
        paladin) echo "co -tank,-tank assist,+dps,+dps assist" ;;
        dk)      echo "co -blood,-tank assist,+frost,+frost aoe,+dps assist" ;;
        druid)   echo "co -bear,-tank assist,+cat,+dps assist" ;;
    esac
}
CONVERT_NC="nc -tank assist,+dps assist"

# ======================================================================
# args
# ======================================================================
[[ $# -ge 1 ]] || { list_pool; exit 0; }

if [[ "$1" == "--list" ]]; then list_pool "${2:-}"; exit 0; fi

if [[ "$1" == "--restore" ]]; then
    newest="$(ls -1t "${PB_CONF}".hprv-spec.*.bak 2>/dev/null | head -1 || true)"
    [[ -n "$newest" ]] || die "no hprv-spec backup found next to $PB_CONF"
    cp -p "$newest" "$PB_CONF"
    info "Restored $PB_CONF from $newest"
    info ""
    info "Now, in game:"
    info ""
    info "    .reload config"
    info "    .playerbots bot reload"
    info ""
    info "Verify:  $(dirname "$0")/roster-status.sh"
    exit 0
fi

CHAR="$1"; shift
LINE="$(pool_line "$CHAR")"
[[ -n "$LINE" ]] || die "'$CHAR' is not in $POOL_CONF. Run --list to see the pool."

CHAR="$(pool_field "$LINE" 1)"      # canonical casing
CLASS="$(pool_field "$LINE" 2)"
HOME_SPEC="$(pool_field "$LINE" 3)"
OFFSPECS="$(pool_field "$LINE" 4)"
STATUS="$(pool_field "$LINE" 5)"
CID="${CLASS_ID[$CLASS]:?unknown class '$CLASS' for $CHAR}"

if [[ "${1:-}" == "--show" ]]; then
    G="$(char_guid "$CHAR")"
    info "$CHAR — $CLASS"
    info "  home spec : $HOME_SPEC"
    info "  offspecs  : ${OFFSPECS//|/, }"
    info "  status    : $STATUS"
    info "  online    : $([[ "$(char_online "$CHAR")" == "1" ]] && echo yes || echo no)"
    info "  co override: $(has_co_override "$G" && echo 'YES — will be cleared on switch' || echo no)"
    is_plate_or_bear "$CLASS" && info "  defence   : $(defence_skill "$G") (floor ${DEFENCE_FLOOR:-490})"
    info "  all specs for $CLASS: $(spec_list_for_class "$CID")"
    exit 0
fi

TARGET_SPEC="${1:?usage: hprv-spec.sh <character> <spec> [--mode human|bot]}"; shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)    MODE="${2:?}";    shift 2 ;;
        --quality) QUALITY="${2:?}"; shift 2 ;;
        *) die "unknown option '$1'" ;;
    esac
done

[[ "$MODE" == "human" || "$MODE" == "bot" ]] || die "--mode must be 'human' or 'bot'"

# Validate the spec is one this character is meant to run. Not a hard
# technical limit — it is a guard against typos that would otherwise cost
# a full gear pass to notice.
if [[ "$TARGET_SPEC" != "$HOME_SPEC" ]] && ! printf '%s' "$OFFSPECS" | tr '|' '\n' | grep -qxF "$TARGET_SPEC"; then
    die "'$TARGET_SPEC' is not $CHAR's home spec or an offspec.
  home:     $HOME_SPEC
  offspecs: ${OFFSPECS//|/, }
  all $CLASS specs at this pin: $(spec_list_for_class "$CID")
  (edit pool.conf if you genuinely want a new offspec for this character)"
fi

IDX="$(spec_index "$CID" "$TARGET_SPEC")"
[[ -n "$IDX" ]] || die "'$TARGET_SPEC' is not a PremadeSpecName for $CLASS at this pin.
  available: $(spec_list_for_class "$CID")"

GUID="$(char_guid "$CHAR")"
[[ -n "$GUID" ]] || die "$CHAR has no character row — is the pool migrated yet?"

# ======================================================================
info "=============================================================="
info " $CHAR ($CLASS)  $HOME_SPEC  ->  $TARGET_SPEC"
info " mode: $MODE    quality: init=$QUALITY    spec index: ${CID}.${IDX}"
info "=============================================================="

if [[ "$(char_online "$CHAR")" != "1" ]]; then
    warn "$CHAR is not online."
    warn "init= only works on a bot that already has you as master, so summon"
    warn "it first:  .playerbots bot add $CHAR"
    die "aborting — nothing has been changed. Summon it, then re-run."
fi

info ""
info "1. forcing RandomClassSpecProb.${CID}.* -> ${IDX}=100, rest 0"
backup_conf
force_spec_prob "$CID" "$IDX"
# Without this the respec is a silent no-op on any level-70 bot.
set_key EquipAndSpecPersistence 0
info "  EquipAndSpecPersistence -> 0 (restored in step 3)"

info ""
info "2. PASTE THESE IN GAME, IN THIS ORDER"
# Both reloads, in this order. `.playerbots bot reload` alone re-applies
# what ConfigMgr cached at startup — it never reads disk.
queue ".reload config"
queue ".playerbots bot reload"
queue ".playerbots bot init=${QUALITY} ${CHAR}"
flush_cmds

# The config is deliberately LEFT FORCED here. Restoring it at this point
# is what made every earlier pass roll the default spec: the script cannot
# wait for the paste, so the table has to survive until `--restore`.

# --- strategy overrides ------------------------------------------------
info ""
info "3. strategy overrides"
if has_co_override "$GUID"; then
    clear_co_override "$GUID"
    info "  cleared the stale 'co' override (it was frozen at the OLD spec's"
    info "  strategy list and would have outranked the new spec silently)"
else
    info "  no 'co' override to clear"
fi

NEEDS_WHISPER=""
if is_plate_or_bear "$CLASS" && is_tank_spec "$TARGET_SPEC"; then
    if [[ "$MODE" == "human" ]]; then
        NEEDS_WHISPER="/w ${CHAR} $(convert_co "$CLASS")"
    fi
fi

# --- report ------------------------------------------------------------
info ""
info "=============================================================="
info " NOT DONE YET — two steps remain, in this order."
info "=============================================================="
info ""
info " 1. Paste the three lines from step 2 above, in game, now."
info "    The forced probability table is LIVE in $PB_CONF while you do."
info ""
info " 2. Then put the config back:"
info ""
info "        $0 --restore"
info ""
info " Until you run --restore, every OTHER $CLASS rolls $TARGET_SPEC too."
info " This is two commands rather than one because the script cannot wait"
info " for you to paste — an earlier version restored the table immediately"
info " and the pass silently rolled the DEFAULT spec every time."

if [[ -n "$NEEDS_WHISPER" ]]; then
    info ""
    info "!! ONE MANUAL STEP. $CHAR is a tank-specced plate/bear body and you"
    info "!! are in HUMAN-tank mode. Left alone it will taunt bosses off you"
    info "!! on cooldown, all night — LoseAggroTrigger is permanently satisfied"
    info "!! while you hold the target, and no threat setting reaches it."
    info "!!"
    info "!! Whisper BOTH, after this pass. Any later init= pass deletes them"
    info "!! again (PlayerbotFactory::Randomize -> PlayerbotRepository::Reset):"
    info "!!"
    info "!!     $NEEDS_WHISPER"
    info "!!     /w ${CHAR} ${CONVERT_NC}"
    info "!!"
    info "!! Then assert the 'co' AND 'nc' rows exist and hold no tank / blood /"
    info "!! bear / tank assist. Absence of a row is NOT conversion."
fi

if [[ "$MODE" == "bot" ]] && is_tank_spec "$TARGET_SPEC"; then
    info ""
    info "NOTE — bot-tank mode. If this raid will run TWO bot tanks, whisper"
    info "  co -threat  to BOTH of them. ThreatValue scales each tank against"
    info "the OTHER tanks, so an unmodified pair mutes each other and neither"
    info "holds anything. Do NOT do this with only one tank."
fi

if is_tank_spec "$TARGET_SPEC" && is_plate_or_bear "$CLASS"; then
    D="$(defence_skill "$GUID")"
    info ""
    info "DEFENCE CHECK: $CHAR is at ${D} defence skill (floor ${DEFENCE_FLOOR:-490})."
    if [[ "$D" -lt "${DEFENCE_FLOOR:-490}" ]]; then
        info "  ** UNDER THE FLOOR — bosses will crit. **"
        info "  Expected: init= scores raw stats and has no concept of defence"
        info "  skill, so it fills trinkets/neck/shield with zero-defence"
        info "  pieces every single time. Top it up by hand with .additem;"
        info "  at this tier the available items total well past what you need."
        info "  Then .save before trusting roster-status.sh."
    else
        info "  crit-immune vs a level 73 boss."
    fi
fi

info ""
info "Verify:  scripts/roster-status.sh    (reads LAST-SAVED state — .save first)"
