#!/usr/bin/env bash
#
# HPRV — Phase E: server configuration.
#
# Writes authserver.conf, worldserver.conf and modules/playerbots.conf
# from their .dist templates, wires in the Phase A credentials, points
# DataDir at the Phase D extraction, and sets the realmlist row the
# client connects to.
#
# CREATE-THEN-PATCH, NOT REGENERATE. A .conf is copied from its .dist
# only if it does not already exist; thereafter only the keys this
# script owns are rewritten in place. That matters most for
# playerbots.conf: it is the M4 tuning surface (bot damage/healing
# multipliers, bot counts, strategy toggles), so regenerating it would
# silently discard every tuning pass. phase-d-dbimport.sh regenerates
# dbimport.conf wholesale because that file has no tuning surface — the
# difference is deliberate.
#
# WHAT THIS DOES NOT DO (by design):
#   - No systemd units. Those need root; Phase F installs them.
#   - No GM account. That's a worldserver console command, Phase F.
#   - It does NOT open any firewall port. LAN/WireGuard only, per the
#     CLAUDE.md guardrail.
#
# Usage (inside the LXC, as 'acore', NOT root):
#   /opt/hprv/scripts/phase-e-config.sh
#
# Optional env overrides:
#   HPRV_REALM_ADDRESS=192.168.4.124   what the client connects to
#   HPRV_REALM_NAME=HPRV               realm name in the client's list
#   HPRV_REALM_PORT=8085               worldserver port
#   HPRV_DATA_DIR=/mnt/hprv/data       extracted client data
#   HPRV_SRC_ROOT=/mnt/hprv/build/azerothcore
#   HPRV_SERVER_DIR=/mnt/hprv/server
#   HPRV_ENV_FILE=/etc/hprv/hprv.env
#   HPRV_ALLOW_ROOT=1
#
set -euo pipefail

HPRV_SERVER_DIR="${HPRV_SERVER_DIR:-/mnt/hprv/server}"
HPRV_SRC_ROOT="${HPRV_SRC_ROOT:-/mnt/hprv/build/azerothcore}"
HPRV_DATA_DIR="${HPRV_DATA_DIR:-/mnt/hprv/data}"
HPRV_ENV_FILE="${HPRV_ENV_FILE:-/etc/hprv/hprv.env}"
HPRV_REALM_ADDRESS="${HPRV_REALM_ADDRESS:-192.168.4.124}"
HPRV_REALM_NAME="${HPRV_REALM_NAME:-HPRV}"
HPRV_REALM_PORT="${HPRV_REALM_PORT:-8085}"
HPRV_ALLOW_ROOT="${HPRV_ALLOW_ROOT:-0}"

CONF_DIR="$HPRV_SERVER_DIR/etc"
MOD_CONF_DIR="$CONF_DIR/modules"

log()  { printf '\033[1;32m[phase-e]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[phase-e]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[phase-e]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- Guards -----------------------------------------------------------

require_not_root() {
  if [[ "$(id -u)" -eq 0 && "$HPRV_ALLOW_ROOT" != "1" ]]; then
    die "Run as the service user, not root:
       su -s /bin/bash -l acore
     Configs written as root are configs the daemons cannot read back."
  fi
  cd / || die "Cannot cd to /."
}

load_env() {
  [[ -r "$HPRV_ENV_FILE" ]] || die "Cannot read $HPRV_ENV_FILE."
  # shellcheck disable=SC1090
  source "$HPRV_ENV_FILE"
  for v in ACORE_DB_USER ACORE_DB_PASS ACORE_DB_AUTH ACORE_DB_CHARACTERS \
           ACORE_DB_WORLD ACORE_DB_PLAYERBOTS; do
    [[ -n "${!v:-}" ]] || die "$v is unset in $HPRV_ENV_FILE."
  done
  ACORE_DB_HOST="${ACORE_DB_HOST:-127.0.0.1}"
  ACORE_DB_PORT="${ACORE_DB_PORT:-3306}"
  log "Credentials loaded (user: $ACORE_DB_USER)."
}

require_layout() {
  for d in "$CONF_DIR" "$HPRV_SERVER_DIR/bin"; do
    [[ -d "$d" ]] || die "Missing $d — Phase C incomplete."
  done
  for f in authserver.conf.dist worldserver.conf.dist; do
    [[ -f "$CONF_DIR/$f" ]] || die "Missing $CONF_DIR/$f."
  done
  [[ -f "$MOD_CONF_DIR/playerbots.conf.dist" ]] \
    || die "Missing $MOD_CONF_DIR/playerbots.conf.dist.
     The module did not install its config — check Phase C linked it in."

  # DataDir is the single most common Phase E mistake: worldserver starts
  # happily with a wrong one and then fails to load maps much later.
  local missing=()
  for d in dbc maps vmaps mmaps; do
    [[ -d "$HPRV_DATA_DIR/$d" && -n "$(ls -A "$HPRV_DATA_DIR/$d" 2>/dev/null)" ]] \
      || missing+=("$d")
  done
  (( ${#missing[@]} )) && die "Client data missing from $HPRV_DATA_DIR: ${missing[*]}
     Run phase-d-extract.sh first. mmaps in particular are required —
     bots cannot path without them."
  log "Client data present: dbc, maps, vmaps, mmaps."
}

# ---- Config helpers ---------------------------------------------------

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

# Copy from .dist only on first run. Never clobber an existing .conf —
# see the header note about playerbots.conf being the tuning surface.
ensure_conf() {
  local conf="$1" dist="$2"
  if [[ -f "$conf" ]]; then
    log "$(basename "$conf"): exists — patching managed keys only."
  else
    cp "$dist" "$conf"
    log "$(basename "$conf"): created from $(basename "$dist")."
  fi
  chmod 640 "$conf"   # every one of these ends up holding the DB password
}

conn_string() { printf '"%s;%s;%s;%s;%s"' \
  "$ACORE_DB_HOST" "$ACORE_DB_PORT" "$ACORE_DB_USER" "$ACORE_DB_PASS" "$1"; }

# ---- Steps ------------------------------------------------------------

step_authserver() {
  local conf="$CONF_DIR/authserver.conf"
  ensure_conf "$conf" "$CONF_DIR/authserver.conf.dist"
  set_conf_key "$conf" "LoginDatabaseInfo" "$(conn_string "$ACORE_DB_AUTH")"
  set_conf_key "$conf" "LogsDir" "\"$HPRV_SERVER_DIR/logs\""
}

step_worldserver() {
  local conf="$CONF_DIR/worldserver.conf"
  ensure_conf "$conf" "$CONF_DIR/worldserver.conf.dist"

  set_conf_key "$conf" "LoginDatabaseInfo"     "$(conn_string "$ACORE_DB_AUTH")"
  set_conf_key "$conf" "CharacterDatabaseInfo" "$(conn_string "$ACORE_DB_CHARACTERS")"
  set_conf_key "$conf" "WorldDatabaseInfo"     "$(conn_string "$ACORE_DB_WORLD")"

  set_conf_key "$conf" "DataDir" "\"$HPRV_DATA_DIR\""
  set_conf_key "$conf" "LogsDir" "\"$HPRV_SERVER_DIR/logs\""

  # worldserver — not dbimport — is what populates acore_playerbots at
  # first start. To do that it has to find the module's SQL on disk, so
  # SourceDirectory must point at the Phase B tree. Wrong here and the
  # fourth schema stays empty with no obvious error.
  set_conf_key "$conf" "SourceDirectory" "\"$HPRV_SRC_ROOT\""
  set_conf_key "$conf" "MySQLExecutable" "\"$(command -v mysql)\""
  set_conf_key "$conf" "Updates.AutoSetup"       "1"
  set_conf_key "$conf" "Updates.EnableDatabases" "7"

  # mmaps are required for bot pathing (CLAUDE.md Phase D). The .dist
  # default is already 1, but a raid of bots that cannot path is the
  # entire project failing quietly, so assert it.
  #
  # The key is MoveMaps.Enable. An earlier version used TrinityCore's
  # name (mmap.enablePathFinding), which AzerothCore ignores — so the
  # assertion silently did nothing while appearing to succeed. If you
  # see "Key not found ... appending" for this key, verify against the
  # .dist before trusting it rather than assuming the append worked.
  set_conf_key "$conf" "MoveMaps.Enable" "1"
}

step_playerbots() {
  local conf="$MOD_CONF_DIR/playerbots.conf"
  ensure_conf "$conf" "$MOD_CONF_DIR/playerbots.conf.dist"

  # THE line that matters. The .dist ships
  #   PlayerbotsDatabaseInfo = "127.0.0.1;3306;acore;acore;acore_playerbots"
  # with password 'acore' — not the password Phase A generated. Leave it
  # and worldserver cannot reach the fourth schema, so it never
  # populates and the bots never get their tables.
  set_conf_key "$conf" "PlayerbotsDatabaseInfo" \
    "$(conn_string "$ACORE_DB_PLAYERBOTS")"

  # Gates worldserver applying playerbots base+updates at startup.
  set_conf_key "$conf" "Playerbots.Updates.EnableDatabases" "1"

  warn "playerbots.conf: bot counts, specs and the M4 damage/healing"
  warn "multipliers are left at .dist defaults — those are tuning"
  warn "decisions, logged as ADRs, not something this script should pick."
}

step_realmlist() {
  local out
  out="$(mysql -h "$ACORE_DB_HOST" -P "$ACORE_DB_PORT" \
          -u "$ACORE_DB_USER" -p"$ACORE_DB_PASS" "$ACORE_DB_AUTH" -N -B -e "
      UPDATE realmlist
         SET name         = '${HPRV_REALM_NAME}',
             address      = '${HPRV_REALM_ADDRESS}',
             localAddress = '${HPRV_REALM_ADDRESS}',
             port         = ${HPRV_REALM_PORT},
             flag         = 0
       WHERE id = 1;
      SELECT id, name, address, port, flag, gamebuild FROM realmlist;" 2>&1)" \
    || die "realmlist update failed: $out"
  log "realmlist row: $out"
  # flag = 2 is REALM_FLAG_OFFLINE, and the base auth row ships with it
  # set. The realm then appears in the client's list permanently greyed
  # as "offline" — it may still be connectable, which makes it read like
  # an intermittent network fault rather than a config value. Hit for
  # real 2026-08-09. gamebuild must be 12340 for 3.3.5a; the base row is
  # already correct, so it is selected above for eyeballing, not set.
  log "flag forced to 0 (base row ships flag=2 = REALM_FLAG_OFFLINE)."
  log "The client's realmlist.wtf must point at ${HPRV_REALM_ADDRESS}."
}

step_summary() {
  cat <<EOF

$(log "Phase E complete.")

  authserver.conf   : $CONF_DIR/authserver.conf
  worldserver.conf  : $CONF_DIR/worldserver.conf
  playerbots.conf   : $MOD_CONF_DIR/playerbots.conf
  DataDir           : $HPRV_DATA_DIR
  SourceDirectory   : $HPRV_SRC_ROOT
  Realm             : ${HPRV_REALM_NAME} @ ${HPRV_REALM_ADDRESS}:${HPRV_REALM_PORT}

All three configs are mode 640 and carry the DB password.

Next (Phase F — first light):
  1. systemd units for authserver + worldserver (needs root).
  2. First worldserver start populates acore_playerbots — watch for it.
     Verify afterwards:
       mysql -u ${ACORE_DB_USER} -p -N -B -e \\
         "SELECT COUNT(*) FROM information_schema.tables
           WHERE table_schema='${ACORE_DB_PLAYERBOTS}';"
     Still 0 means PlayerbotsDatabaseInfo or SourceDirectory is wrong.
  3. Console: create the account, then
       account set gmlevel <acct> 3 -1
  4. Client realmlist.wtf -> set realmlist ${HPRV_REALM_ADDRESS}

Ports stay on the LAN. No forward, no proxy — see the CLAUDE.md
guardrail; opening them is the environment-promotion trigger.
EOF
}

main() {
  require_not_root
  load_env
  require_layout
  mkdir -p "$HPRV_SERVER_DIR/logs"
  step_authserver
  step_worldserver
  step_playerbots
  step_realmlist
  step_summary
}

main "$@"
