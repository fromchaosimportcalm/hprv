#!/usr/bin/env bash
#
# HPRV — Phase D (databases): import auth / characters / world.
#
# Writes dbimport.conf from the installed .dist using the credentials
# Phase A generated, then runs dbimport once. Idempotent: dbimport is an
# incremental updater and tracks what it has applied, so re-running is
# how you pick up new SQL, not a mistake.
#
# WHAT THIS DOES NOT DO (by design):
#
#   - It does NOT populate acore_playerbots. That fourth schema is NOT
#     handled by dbimport: dbimport.conf has no PlayerbotsDatabaseInfo
#     and its update mask stops at 4 (1=auth, 2=characters, 4=world).
#     The connection string lives in playerbots.conf as
#     PlayerbotsDatabaseInfo, and the fork's *worldserver* applies that
#     database's base+updates at startup, gated on
#     Playerbots.Updates.EnableDatabases (default 1). So the fourth
#     schema fills in at Phase F first-start, not here. Verified against
#     the pinned commit 2026-08-08.
#
#   - It does NOT run data/sql/create/. Phase A already created the four
#     schemas and the acore MySQL user with a GENERATED password stored
#     in /etc/hprv/hprv.env. AzerothCore's create_mysql.sql would reset
#     that user to the project default password and break every
#     connection string. Most AC guides tell you to run it; they assume
#     you have not done a Phase A. Do not "fix" this.
#
#   - It does NOT extract client data. That's phase-d-extract.sh.
#
# The module's own world/ and characters/ SQL need no special handling:
# mod-playerbots ships them under data/sql/{world,characters}/{base,
# updates}, which is AzerothCore's module convention, and
# Updates.AllowedModules = "all" picks them up.
#
# Usage (inside the LXC, as 'acore', NOT root):
#   /opt/hprv/scripts/phase-d-dbimport.sh
#
# Optional env overrides:
#   HPRV_SRC_ROOT=/mnt/hprv/build/azerothcore   source tree (SQL lives here)
#   HPRV_SERVER_DIR=/mnt/hprv/server            install prefix
#   HPRV_ENV_FILE=/etc/hprv/hprv.env            DB credentials
#   HPRV_ALLOW_ROOT=1                           bypass the root guard
#
set -euo pipefail

HPRV_SRC_ROOT="${HPRV_SRC_ROOT:-/mnt/hprv/build/azerothcore}"
HPRV_SERVER_DIR="${HPRV_SERVER_DIR:-/mnt/hprv/server}"
HPRV_ENV_FILE="${HPRV_ENV_FILE:-/etc/hprv/hprv.env}"
HPRV_ALLOW_ROOT="${HPRV_ALLOW_ROOT:-0}"

CONF_DIR="$HPRV_SERVER_DIR/etc"
DBIMPORT_CONF="$CONF_DIR/dbimport.conf"

log()  { printf '\033[1;32m[phase-d-db]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[phase-d-db]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[phase-d-db]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- Guards -----------------------------------------------------------

require_not_root() {
  if [[ "$(id -u)" -eq 0 && "$HPRV_ALLOW_ROOT" != "1" ]]; then
    die "Run as the service user, not root:
       su -s /bin/bash -l acore
     (Override with HPRV_ALLOW_ROOT=1 only if you know why.)"
  fi
  # `find`/relative-path tools break if cwd is unreadable; su without -l
  # leaves you in /root, which acore cannot read.
  cd / || die "Cannot cd to /."
}

load_env() {
  [[ -r "$HPRV_ENV_FILE" ]] || die "Cannot read $HPRV_ENV_FILE.
     Phase A writes it root:acore mode 640 — check $(id -un) is in the acore group."
  # shellcheck disable=SC1090
  source "$HPRV_ENV_FILE"
  for v in ACORE_DB_USER ACORE_DB_PASS ACORE_DB_AUTH ACORE_DB_CHARACTERS \
           ACORE_DB_WORLD ACORE_DB_PLAYERBOTS; do
    [[ -n "${!v:-}" ]] || die "$v is unset in $HPRV_ENV_FILE.
     If ACORE_DB_PLAYERBOTS is the missing one, this container was
     provisioned before 2026-08-05 — re-run phase-a-bootstrap.sh. It is
     idempotent and will not rotate the password."
  done
  ACORE_DB_HOST="${ACORE_DB_HOST:-127.0.0.1}"
  ACORE_DB_PORT="${ACORE_DB_PORT:-3306}"
  log "Credentials loaded from $HPRV_ENV_FILE (user: $ACORE_DB_USER)."
}

require_tools() {
  [[ -x "$HPRV_SERVER_DIR/bin/dbimport" ]] \
    || die "No dbimport at $HPRV_SERVER_DIR/bin — Phase C incomplete."
  command -v mysql >/dev/null \
    || die "mysql client not found. dbimport shells out to it for base imports."
  [[ -f "$CONF_DIR/dbimport.conf.dist" ]] \
    || die "No dbimport.conf.dist in $CONF_DIR — Phase C did not install configs."
  log "dbimport, mysql client and dbimport.conf.dist present."
}

require_sql_tree() {
  local base="$HPRV_SRC_ROOT/data/sql/base"
  [[ -d "$base/db_world" ]] \
    || die "No $base/db_world — dbimport has no base world data to import.
     The source tree must be the Phase B clone, not a stripped copy."
  # The world base is ~126 MB in-repo at this pin, so the import is fully
  # offline. If a future pin moves it to a downloaded release asset, this
  # check is where that change surfaces.
  log "Base SQL present ($(du -sh "$base/db_world" 2>/dev/null | cut -f1) of world data)."
}

check_db_connect() {
  local out
  out="$(mysql -h "$ACORE_DB_HOST" -P "$ACORE_DB_PORT" \
           -u "$ACORE_DB_USER" -p"$ACORE_DB_PASS" \
           -N -B -e "SHOW DATABASES LIKE 'acore%';" 2>&1)" \
    || die "Cannot connect to MySQL as $ACORE_DB_USER: $out"

  local missing=()
  for db in "$ACORE_DB_AUTH" "$ACORE_DB_CHARACTERS" "$ACORE_DB_WORLD" \
            "$ACORE_DB_PLAYERBOTS"; do
    grep -qx "$db" <<<"$out" || missing+=("$db")
  done
  (( ${#missing[@]} )) && die "Schemas missing: ${missing[*]}
     Re-run phase-a-bootstrap.sh; it creates all four idempotently."
  log "Connected. All four schemas exist."
}

# ---- Config -----------------------------------------------------------

# Replace a key in an AzerothCore .conf, or append it if absent. Values
# are passed already-quoted where the format wants quotes, because AC
# treats quoted and bare values differently (strings vs numbers).
set_conf_key() {
  local file="$1" key="$2" value="$3" esc
  esc="$(sed -e 's/[\\&|]/\\&/g' <<<"$value")"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$file"; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${esc}|" "$file"
  else
    warn "Key '$key' not found in $(basename "$file") — appending."
    printf '%s = %s\n' "$key" "$value" >>"$file"
  fi
}

write_dbimport_conf() {
  # Regenerated from .dist every run so the file is a pure function of
  # the env file plus the pinned .dist — never hand-edited state that
  # drifts. Anything bespoke belongs in this script, not in the .conf.
  if [[ -f "$DBIMPORT_CONF" ]]; then
    cp -a "$DBIMPORT_CONF" "$DBIMPORT_CONF.bak"
    log "Existing dbimport.conf backed up to dbimport.conf.bak"
  fi
  cp "$CONF_DIR/dbimport.conf.dist" "$DBIMPORT_CONF"
  chmod 640 "$DBIMPORT_CONF"   # it carries the DB password

  local conn_auth conn_chars conn_world
  conn_auth="\"${ACORE_DB_HOST};${ACORE_DB_PORT};${ACORE_DB_USER};${ACORE_DB_PASS};${ACORE_DB_AUTH}\""
  conn_chars="\"${ACORE_DB_HOST};${ACORE_DB_PORT};${ACORE_DB_USER};${ACORE_DB_PASS};${ACORE_DB_CHARACTERS}\""
  conn_world="\"${ACORE_DB_HOST};${ACORE_DB_PORT};${ACORE_DB_USER};${ACORE_DB_PASS};${ACORE_DB_WORLD}\""

  set_conf_key "$DBIMPORT_CONF" "LoginDatabaseInfo"     "$conn_auth"
  set_conf_key "$DBIMPORT_CONF" "CharacterDatabaseInfo" "$conn_chars"
  set_conf_key "$DBIMPORT_CONF" "WorldDatabaseInfo"     "$conn_world"

  # 7 = auth|characters|world. Verified against the .dist comments at the
  # pinned commit: 1=DATABASE_LOGIN, 2=DATABASE_CHARACTER, 4=DATABASE_WORLD.
  # There is deliberately no playerbots bit — see the header.
  set_conf_key "$DBIMPORT_CONF" "Updates.EnableDatabases" "7"
  set_conf_key "$DBIMPORT_CONF" "Updates.AutoSetup"       "1"
  set_conf_key "$DBIMPORT_CONF" "Updates.Redundancy"      "1"
  # "all" is already the .dist default, but it is what pulls in
  # mod-playerbots' world/ and characters/ SQL, so make it explicit.
  set_conf_key "$DBIMPORT_CONF" "Updates.AllowedModules"  "\"all\""

  # The updater needs the source tree to find SQL files, and the mysql
  # binary to stream the base dumps. Both default to build-time paths
  # that are wrong for a moved install prefix.
  set_conf_key "$DBIMPORT_CONF" "SourceDirectory"  "\"$HPRV_SRC_ROOT\""
  set_conf_key "$DBIMPORT_CONF" "MySQLExecutable"  "\"$(command -v mysql)\""

  log "Wrote $DBIMPORT_CONF (mode 640 — contains the DB password)."
}

# ---- Run --------------------------------------------------------------

table_count() {
  mysql -h "$ACORE_DB_HOST" -P "$ACORE_DB_PORT" \
        -u "$ACORE_DB_USER" -p"$ACORE_DB_PASS" -N -B \
        -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$1';" \
        2>/dev/null || echo "?"
}

run_dbimport() {
  log "Table counts before: auth=$(table_count "$ACORE_DB_AUTH") \
chars=$(table_count "$ACORE_DB_CHARACTERS") world=$(table_count "$ACORE_DB_WORLD")"
  log "Running dbimport — first run imports ~126 MB of world data, several minutes."
  ( cd "$HPRV_SERVER_DIR/bin" && ./dbimport )
}

step_summary() {
  cat <<EOF

$(log "Phase D (databases) complete.")

  auth       : $(table_count "$ACORE_DB_AUTH") tables
  characters : $(table_count "$ACORE_DB_CHARACTERS") tables
  world      : $(table_count "$ACORE_DB_WORLD") tables
  playerbots : $(table_count "$ACORE_DB_PLAYERBOTS") tables  <- expected 0 here

acore_playerbots is populated by worldserver at first start, not by
dbimport (Playerbots.Updates.EnableDatabases in playerbots.conf). If it
is still 0 after Phase F first-start, that is the thing to investigate.

Next (Phase E — config):
  - worldserver.conf : the three DB connection strings + DataDir=/mnt/hprv/data
  - playerbots.conf  : PlayerbotsDatabaseInfo — the .dist default password
                       is 'acore', which is NOT the generated one. It must
                       be rewritten or the fourth schema never populates.
  - acore_auth.realmlist : the LAN/WireGuard address the client hits
EOF
}

main() {
  require_not_root
  load_env
  require_tools
  require_sql_tree
  check_db_connect
  write_dbimport_conf
  run_dbimport
  step_summary
}

main "$@"
