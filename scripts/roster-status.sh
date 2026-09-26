#!/usr/bin/env bash
#
# HPRV — roster status report.
#
# Reads scripts/roster.conf and prints what the database actually knows
# about the nine bots plus the master: level, class, online state, and
# equipped-item count. Read-only — it runs SELECTs and nothing else.
#
# WHY THIS EXISTS. A worldserver restart costs ~6 minutes (311s of it is
# the module parsing its own 102 KB playerbots.conf), so "log in and
# look" is an expensive way to answer "did the gearing actually take?".
# This answers it from outside the game in about a second.
#
# It also catches the failure mode that is otherwise invisible: an
# AddClass-pool character that was never `init=`'d is still level 1 with
# no gear, and a level-1 bot in a level-70 raid does not announce itself
# — it just contributes nothing and dies to the first AoE.
#
# Usage (inside the LXC; root or acore, either works):
#   /opt/hprv/scripts/roster-status.sh
#
# Optional env overrides:
#   HPRV_ENV_FILE=/etc/hprv/hprv.env
#   HPRV_ROSTER=<path to roster.conf>   (default: alongside this script)
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HPRV_ENV_FILE="${HPRV_ENV_FILE:-/etc/hprv/hprv.env}"
HPRV_ROSTER="${HPRV_ROSTER:-${SCRIPT_DIR}/roster.conf}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -r "$HPRV_ENV_FILE" ]] || die "cannot read $HPRV_ENV_FILE (it is 640 root:acore — run as root or acore)"
[[ -r "$HPRV_ROSTER" ]]   || die "cannot read $HPRV_ROSTER"

# shellcheck disable=SC1090
set -a; . "$HPRV_ENV_FILE"; set +a
# shellcheck disable=SC1090
. "$HPRV_ROSTER"
# shellcheck disable=SC1091
. "${SCRIPT_DIR}/defence.conf"

DB_CHARS="${ACORE_DB_CHARACTERS:-acore_characters}"
DB_PB="${ACORE_DB_PLAYERBOTS:-acore_playerbots}"
PB_CONF="${HPRV_PB_CONF:-/mnt/hprv/server/etc/modules/playerbots.conf}"

mysql_q() {
    mysql --default-character-set=utf8mb4 -N -B \
        -h "${ACORE_DB_HOST:-127.0.0.1}" -P "${ACORE_DB_PORT:-3306}" \
        -u "$ACORE_DB_USER" -p"$ACORE_DB_PASS" -e "$1" 2>/dev/null
}

# Class id -> name. The module skips 10 (there is no class 10 in 3.3.5a).
class_name() {
    case "$1" in
        1) echo warrior ;;  2) echo paladin ;;  3) echo hunter ;;
        4) echo rogue   ;;  5) echo priest  ;;  6) echo dk ;;
        7) echo shaman  ;;  8) echo mage    ;;  9) echo warlock ;;
        11) echo druid  ;;  *) echo "class:$1" ;;
    esac
}

# The factory records the spec it rolled: InitTalentsTree() ends with
#   sRandomPlayerbotMgr.SetValue(guid, "specNo", specIndex + 1)
# which lands in playerbots_random_bots as event 'specNo'. Stored value is
# index+1, so 0 means "never initialised". This is the only way to read a
# bot's ACTUAL spec without DBC access — character_talent holds spell ids
# whose talent-tab mapping lives in DBC, not in any database table.
actual_spec() {  # actual_spec <charName> <classId> -> spec name or "-"
    local v idx
    v="$(mysql_q "SELECT r.value FROM ${DB_PB}.playerbots_random_bots r
                    JOIN ${DB_CHARS}.characters c ON c.guid=r.bot
                   WHERE r.event='specNo' AND c.name='${1}' LIMIT 1;")"
    [[ -n "$v" && "$v" != "0" ]] || { printf -- '-'; return; }
    idx=$((v - 1))
    local name
    name="$(grep -E "^AiPlayerbot\.PremadeSpecName\.${2}\.${idx} *=" "$PB_CONF" 2>/dev/null \
            | head -1 | sed 's/.*= *//')"
    printf '%s' "${name:-idx$idx}"
}

ONLINE_NAMES=""

printf '%-14s %-9s %-7s %-13s %-13s %-5s %-4s %-4s %s\n' \
    NAME CLASS ROLE WANTED-SPEC ACTUAL-SPEC LEVEL EQP ON NOTE
printf '%s\n' "----------------------------------------------------------------------------------------------"

report_one() {
    local name="$1" want_class="$2" want_spec="$3" role="$4" bench="${5:-}"
    [[ -n "$name" ]] || { printf '%-14s %-9s %-7s %-13s %-13s %-5s %-4s %-4s %s\n' \
        "(empty)" "$want_class" "$role" "$want_spec" "-" "-" "-" "-" "slot not filled in roster.conf"; return; }

    local row
    row="$(mysql_q "SELECT c.class, c.level, c.online,
                      (SELECT COUNT(*) FROM ${DB_CHARS}.character_inventory i
                        WHERE i.guid=c.guid AND i.bag=0 AND i.slot<19)
                    FROM ${DB_CHARS}.characters c WHERE c.name='${name}';")"

    if [[ -z "$row" ]]; then
        printf '%-14s %-9s %-7s %-13s %-13s %-5s %-4s %-4s %s\n' \
            "$name" "$want_class" "$role" "$want_spec" "?" "?" "?" "?" "NOT FOUND in characters"
        return
    fi

    local cls lvl on equipped note actual
    IFS=$'\t' read -r cls lvl on equipped <<<"$row"
    actual="$(class_name "$cls")"

    local spec; spec="$(actual_spec "$name" "$cls")"

    note=""
    [[ "$actual" == "$want_class" ]] || note="CLASS MISMATCH (is $actual)"
    # The one that silently ruins a raid: a healer slot that rolled DPS.
    # `talents spec` cannot fix it — respeccing never re-runs InitEquipment
    # (ADR 0007). Re-roll it through scripts/gear-pass.sh instead.
    if [[ -n "$want_spec" && "$spec" != "-" && "$spec" != "$want_spec" ]]; then
        note="${note:+$note; }SPEC MISMATCH — re-run the gear pass"
    fi
    if [[ "$lvl" -lt 70 ]]; then
        note="${note:+$note; }level $lvl — needs .playerbots bot init=epic"
    fi
    if [[ "$equipped" -lt 10 ]]; then
        note="${note:+$note; }only $equipped equipped — gearing did not take"
    fi
    # A benched bot is still reported in full — level, spec drift and gear
    # all keep mattering, because the whole point of a bench is that you
    # can bring the body back without a gear pass. It is only kept out of
    # the summon line, so a raid stays at ten.
    if [[ -n "$bench" && "$bench" != "no" ]]; then
        note="BENCHED${note:+ — $note}"
    fi
    [[ -n "$note" ]] || note="ok"

    printf '%-14s %-9s %-7s %-13s %-13s %-5s %-4s %-4s %s\n' \
        "$name" "$actual" "$role" "$want_spec" "$spec" "$lvl" "$equipped" \
        "$([[ "$on" == "1" ]] && echo yes || echo no)" "$note"
}

# The tank is the one raid slot that cannot be scaled down freely. Against
# a level-73 boss, avoiding crits needs 490 defence skill: 350 base at
# level 70 plus 140 from gear, at ~2.37 defence rating per skill point.
# Under that, the boss crits and crushes and no healing throughput covers
# it — so a gear downgrade has a hard floor here that it does not have
# anywhere else in the raid.
#
# This runs for ANY slot whose role is "tank", not just the master. A bot
# tank needs it more than a human one does: you notice your own character
# getting crushed within one pull, whereas a bot silently drops under the
# cap and just starts dying. See decisions/0010.
defence_line() {  # defence_line <character name>
    local who="$1" g items enchants defrtg skill
    [[ -n "$who" ]] || return 0
    g="$(mysql_q "SELECT guid FROM ${DB_CHARS}.characters WHERE name='${who}';")"
    [[ -n "$g" ]] || return 0
    # Items AND enchants/gems (defence.conf). Items alone read low.
    read -r items enchants < <(mysql_q "$(defence_rating_sql "$DB_CHARS" "${ACORE_DB_WORLD:-acore_world}" "$g")")
    defrtg=$(( ${items:-0} + ${enchants:-0} ))
    skill="$(defence_skill_from_rating "$defrtg")"
    if [[ "$skill" -ge 490 ]]; then
        printf '  tank defence: %s rating (%s items + %s enchants/gems) -> %s skill (crit-immune vs lvl 73, needs 490)\n' \
            "$defrtg" "${items:-0}" "${enchants:-0}" "$skill"
    else
        printf '  tank defence: %s rating (%s items + %s enchants/gems) -> %s skill  ** UNDER 490 — boss will crit **\n' \
            "$defrtg" "${items:-0}" "${enchants:-0}" "$skill"
    fi

    # Tonight's failure mode (2026-08-11): EquipUpgradesPacketAction fires
    # on any completed trade or item entering BAGS, re-scores the whole
    # inventory and re-equips whatever StatsWeightCalculator likes — which
    # is never the defence piece. Anything defence-bearing sitting in bags
    # is therefore both a missed upgrade and evidence the swap already
    # happened. The bank is invisible to that scan (ITERATE_ITEMS_IN_BAGS),
    # which is where parked pieces belong.
    local bagdef
    bagdef="$(mysql_q "SELECT COUNT(*)
      FROM ${DB_CHARS}.character_inventory i
      JOIN ${DB_CHARS}.item_instance ii ON ii.guid=i.item
      JOIN ${ACORE_DB_WORLD:-acore_world}.item_template t ON t.entry=ii.itemEntry
      JOIN ${DB_CHARS}.characters c ON c.guid=i.guid
     WHERE i.bag=0 AND i.slot BETWEEN 23 AND 38 AND c.name='${who}'
       AND (t.stat_type1=12 OR t.stat_type2=12 OR t.stat_type3=12 OR t.stat_type4=12
         OR t.stat_type5=12 OR t.stat_type6=12 OR t.stat_type7=12 OR t.stat_type8=12
         OR t.stat_type9=12 OR t.stat_type10=12);")"
    if [[ "${bagdef:-0}" -gt 0 ]]; then
        printf '  ** %s defence item(s) sitting in BAGS, not equipped — check the trinkets **\n' \
            "$bagdef"
    fi
}

# The master's class and role are NOT fixed. ADR 0010 moved the main tank to
# a bot and ADR 0012 re-rolled the human to a resto druid, so both are read
# from roster.conf the same way gear-pass.sh reads them. Hardcoding
# `warrior TANK` here made every run after the switch print a false
# "CLASS MISMATCH (is druid)" against a correctly-specced healer — the exact
# noise this report exists to suppress.
#
# Role is derived from MASTER_SPEC rather than stored, so there is one fewer
# field to keep in sync; the label stays upper-case to distinguish the human
# from the bot rows.
master_role() {
    case "${MASTER_SPEC:-}" in
        prot*|bear*)        printf 'TANK' ;;
        resto*|holy*|disc*) printf 'HEAL' ;;
        *)                  printf 'DPS'  ;;
    esac
}
report_one "${MASTER_NAME:-}" "${MASTER_CLASS:-warrior}" "${MASTER_SPEC:-}" "$(master_role)"
# Defence only matters while the master is actually tanking. Same pair of
# globs as the tank-floor block in `gear-pass.sh master`, so the two agree.
[[ "${MASTER_SPEC:-}" == prot* || "${MASTER_SPEC:-}" == bear* ]] && defence_line "${MASTER_NAME:-}"

for n in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do
    eval "nm=\${BOT_${n}_NAME:-}"
    eval "cl=\${BOT_${n}_CLASS:-}"
    eval "sp=\${BOT_${n}_SPEC:-}"
    eval "ro=\${BOT_${n}_ROLE:-}"
    eval "bn=\${BOT_${n}_BENCH:-}"
    eval "gp=\${BOT_${n}_GROUP:-}"
    # The bench is vestigial at 25 bodies — it existed to hold the raid at
    # ten for Karazhan, and nothing is benched now. It is still honoured:
    # a benched bot keeps its name, gear and spec in roster.conf but stays
    # out of the paste line.
    # GROUP=ten auto-logs-in on account 101, so it's already online and
    # doesn't belong in the summon line.
    if [[ -n "$nm" && "$gp" != "ten" && ( -z "$bn" || "$bn" == "no" ) ]]; then
        ONLINE_NAMES="${ONLINE_NAMES:+$ONLINE_NAMES,}$nm"
    fi
    report_one "$nm" "$cl" "$sp" "$ro" "$bn"
    # Role `offtank` gets the defence line too. Since ADR 0014 the raid's
    # second plate body is a prot paladin converted out of tankhood in the
    # AI (`co -tank,...`) but NOT out of prot gear — he still eats add
    # melee and still needs 490. The role string is deliberately not
    # "tank": that word now means "a bot the module drives as a tank",
    # which is the thing 0014 says cannot coexist with a human tank.
    case "$ro" in
        tank|offtank) [[ -z "$bn" || "$bn" == "no" ]] && defence_line "$nm" ;;
    esac
done

# The one line that starts a session. Bots do not persist across a
# master logout — PlayerbotMgr logs them out with you — so every session
# begins by re-adding them by name. Printing it here means you never have
# to remember or retype nine names.
if [[ -n "$ONLINE_NAMES" ]]; then
    # Split into chunks of 12. 24 names plus the command is ~190 chars and
    # the client's chat input is not a place to discover a length limit.
    printf '\n%s\n' "Summon the raid (paste in game, in order):"
    IFS=',' read -r -a _names <<< "$ONLINE_NAMES"
    for ((_i = 0; _i < ${#_names[@]}; _i += 12)); do
        _chunk="$(IFS=','; printf '%s' "${_names[*]:_i:12}")"
        printf '  .playerbots bot add %s\n' "$_chunk"
    done
fi

# The AddClass pool is what makes this roster re-addable by name at all
# (decisions/0005). If the pool ever empties or the account types are
# wiped, `.playerbots bot add <name>` starts failing with "not allowed
# to control bot" and the cause is not obvious from in game.
printf '\n%s\n' "AddClass pool (source of the roster — do not delete these accounts):"
mysql_q "SELECT CONCAT('  type-2 accounts: ', COUNT(*)) FROM ${DB_PB}.playerbots_account_type WHERE account_type=2;
         SELECT CONCAT('  pool characters: ', COUNT(*)) FROM ${DB_CHARS}.characters c
           JOIN ${DB_PB}.playerbots_account_type t ON t.account_id=c.account WHERE t.account_type=2;"
