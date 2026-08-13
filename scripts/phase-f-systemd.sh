#!/usr/bin/env bash
#
# HPRV — Phase F: systemd units for authserver + worldserver.
#
# Installs and enables both units so the daemons survive an LXC reboot,
# per the Homelab convention. Follows the documented house unit pattern
# (Type=simple, User=, Restart=on-failure, journal for both streams —
# see clintonops-infra/docs/speaches_install.md) plus what AzerothCore
# specifically needs: a long stop timeout, and stdin closed.
#
# This is the ONE script in the set that requires root — installing unit
# files does. Everything it touches is root-owned system state; it does
# not write to acore's configs unless you opt in (HPRV_SET_CONSOLE=1).
#
# IT INSTALLS AND ENABLES, BUT DOES NOT START. First light should be an
# interactive worldserver run: that is when the GM account gets created
# via the console, and when acore_playerbots populates. Starting under
# systemd first means doing that through a journal you cannot type into.
# Order is: run interactively once -> verify -> then systemctl start.
#
# Usage (inside the LXC, as root):
#   /opt/hprv/scripts/phase-f-systemd.sh
#
# Optional env overrides:
#   HPRV_SERVER_DIR=/mnt/hprv/server
#   ACORE_USER=acore
#   HPRV_SET_CONSOLE=1   also set Console.Enable=0 in worldserver.conf
#   HPRV_NO_ENABLE=1     install units but do not `systemctl enable`
#
set -euo pipefail

HPRV_SERVER_DIR="${HPRV_SERVER_DIR:-/mnt/hprv/server}"
ACORE_USER="${ACORE_USER:-acore}"
HPRV_SET_CONSOLE="${HPRV_SET_CONSOLE:-0}"
HPRV_NO_ENABLE="${HPRV_NO_ENABLE:-0}"

CONF_DIR="$HPRV_SERVER_DIR/etc"
BIN_DIR="$HPRV_SERVER_DIR/bin"
UNIT_DIR=/etc/systemd/system

log()  { printf '\033[1;32m[phase-f]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[phase-f]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[phase-f]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Run as root — installing unit files requires it.
     (Every other HPRV script refuses root; this one needs it.)"
  cd / || die "Cannot cd to /."
}

require_layout() {
  id -u "$ACORE_USER" >/dev/null 2>&1 || die "No '$ACORE_USER' user — Phase A incomplete."
  for b in authserver worldserver; do
    [[ -x "$BIN_DIR/$b" ]] || die "Missing $BIN_DIR/$b — Phase C incomplete."
  done
  for c in authserver.conf worldserver.conf; do
    [[ -f "$CONF_DIR/$c" ]] || die "Missing $CONF_DIR/$c — run phase-e-config.sh first."
  done
  [[ -f "$CONF_DIR/modules/playerbots.conf" ]] \
    || die "Missing $CONF_DIR/modules/playerbots.conf — run phase-e-config.sh first."
  systemctl is-active --quiet mysql \
    || warn "mysql.service is not active. The units require it; start it before they will."
  log "Binaries, configs and service user present."
}

# Under systemd stdin is /dev/null. Some AzerothCore builds treat EOF on
# stdin as a shutdown request, so a worldserver with Console.Enable = 1
# can exit immediately on start with no useful error. Setting it to 0 is
# the correct pairing for a daemonised run — but it must stay 1 for the
# interactive first light, which is where the GM account is created.
# Hence: check, explain, and only change it if explicitly asked.
check_console() {
  local conf="$CONF_DIR/worldserver.conf" val
  val="$(grep -E "^[[:space:]]*Console\.Enable[[:space:]]*=" "$conf" \
         | tail -n1 | sed -E 's/.*=[[:space:]]*//' | tr -d '"[:space:]')" || true

  if [[ "$val" == "0" ]]; then
    log "Console.Enable = 0 — correct for systemd."
    return 0
  fi

  if [[ "$HPRV_SET_CONSOLE" == "1" ]]; then
    sed -i -E 's|^[[:space:]]*Console\.Enable[[:space:]]*=.*|Console.Enable = 0|' "$conf"
    log "Console.Enable set to 0 in worldserver.conf."
    return 0
  fi

  warn "Console.Enable is '${val:-unset}', not 0."
  warn "Leave it at 1 for the interactive first light (the GM account is"
  warn "created at that console). Set it to 0 BEFORE 'systemctl start':"
  warn "    sed -i -E 's|^[[:space:]]*Console\\.Enable.*|Console.Enable = 0|' \\"
  warn "      $conf"
  warn "or re-run this script with HPRV_SET_CONSOLE=1."
}

write_unit() {
  local name="$1" desc="$2" bin="$3" conf="$4" stop_timeout="$5" extra="$6"
  local path="$UNIT_DIR/$name"

  if [[ -f "$path" ]]; then
    cp -a "$path" "$path.bak"
    log "$name: existing unit backed up to $name.bak"
  fi

  cat >"$path" <<EOF
[Unit]
Description=$desc
Documentation=https://github.com/mod-playerbots/azerothcore-wotlk
After=network-online.target mysql.service
Wants=network-online.target
Requires=mysql.service

[Service]
Type=simple
User=$ACORE_USER
Group=$ACORE_USER
WorkingDirectory=$BIN_DIR
ExecStart=$bin -c $conf
Restart=on-failure
RestartSec=15
# systemd gives no tty; see Console.Enable in worldserver.conf.
StandardInput=null
StandardOutput=journal
StandardError=journal
$extra
[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$path"
  log "$name written."
}

install_units() {
  write_unit "hprv-authserver.service" \
    "HPRV AzerothCore authserver" \
    "$BIN_DIR/authserver" "$CONF_DIR/authserver.conf" 30 \
"TimeoutStopSec=30
"

  # worldserver saves world state on shutdown and can take a while with a
  # populated bot roster. A short timeout means SIGKILL mid-save, which
  # is how character data gets lost. 300s is deliberate generosity.
  write_unit "hprv-worldserver.service" \
    "HPRV AzerothCore worldserver (mod-playerbots)" \
    "$BIN_DIR/worldserver" "$CONF_DIR/worldserver.conf" 300 \
"TimeoutStopSec=300
KillSignal=SIGTERM
LimitNOFILE=16384
"

  systemctl daemon-reload
  log "systemd daemon-reload done."

  if [[ "$HPRV_NO_ENABLE" == "1" ]]; then
    warn "HPRV_NO_ENABLE=1 — units installed but not enabled."
    return 0
  fi
  systemctl enable hprv-authserver.service hprv-worldserver.service >/dev/null
  log "Both units enabled (start on boot). NOT started — see below."
}

step_summary() {
  cat <<EOF

$(log "Phase F (systemd) complete. Units enabled, deliberately NOT started.")

  $UNIT_DIR/hprv-authserver.service
  $UNIT_DIR/hprv-worldserver.service

FIRST LIGHT — do this interactively, once, before using systemd:

  1. su -s /bin/bash -l $ACORE_USER
     cd $BIN_DIR
     ./authserver -c $CONF_DIR/authserver.conf     # separate tmux pane
     ./worldserver -c $CONF_DIR/worldserver.conf   # this one needs the console

  2. Watch worldserver's startup for the playerbots schema populating.
     It applies acore_playerbots base+updates on first start — that is
     the moment the fourth-schema work either pays off or does not.
     Afterwards, from another shell:

       mysql -u <dbuser> -p -N -B -e "SELECT COUNT(*) FROM \\
         information_schema.tables WHERE table_schema='acore_playerbots';"

     Still 0 means PlayerbotsDatabaseInfo or SourceDirectory is wrong in
     $CONF_DIR/modules/playerbots.conf — not a bot problem.

  3. At the worldserver console (M0):
       account create <name> <password>
       account set gmlevel <name> 3 -1

  4. Client realmlist.wtf -> set realmlist 192.168.4.124
     Use a CLEAN 3.3.5a client, not a private-server repack — custom
     MPQ patches override DBCs and the client will disagree with the
     server about what exists.

  5. Shut worldserver down cleanly from its console:  server shutdown 1

THEN switch to systemd:

  sed -i -E 's|^[[:space:]]*Console\\.Enable.*|Console.Enable = 0|' \\
    $CONF_DIR/worldserver.conf
  systemctl start hprv-authserver hprv-worldserver
  systemctl status hprv-authserver hprv-worldserver
  journalctl -u hprv-worldserver -f

Reboot test before calling M0 done — surviving a reboot is the whole
point of the units:  reboot, then systemctl status both.

No ports are opened. Auth 3724 and world 8085 stay on the LAN, per the
CLAUDE.md guardrail.
EOF
}

main() {
  require_root
  require_layout
  check_console
  install_units
  step_summary
}

main "$@"
