#!/usr/bin/env bash
#
# hprv-portal — install or update, on the server, as root.
#
#   ./install.sh                 # from the unpacked package or a copy of portal/
#   HPRV_PORTAL_PORT=8080 ./install.sh
#
# Idempotent. Re-running it updates the code and restarts the service;
# it never overwrites /etc/hprv/portal.ini or rotates the DB password.
#
# What it does:
#   1. copies the app to /opt/hprv/portal
#   2. creates a system user, hprv-portal, to run it
#   3. creates a MySQL user, hprv_portal@localhost, that can only SELECT
#      what the page shows. It is granted account(id, username) and no
#      other account column, so it cannot read password verifiers.
#   4. writes /etc/hprv/portal.cnf (its password) and portal.ini (config)
#   5. installs and starts hprv-portal.service
#
# Needs: python3 (3.8+), the mysql client, and MySQL admin access as root
# over the socket (the Ubuntu default). Override with MYSQL_ADMIN="mysql -u root -p".
#
# Undo: ./uninstall.sh
set -euo pipefail

SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEST=/opt/hprv/portal
ETC=/etc/hprv
SVC_USER=hprv-portal
DB_USER=hprv_portal
PORT="${HPRV_PORTAL_PORT:-8096}"
MYSQL_ADMIN="${MYSQL_ADMIN:-mysql}"

log() { printf '\033[1;32m[portal]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[portal]\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "run as root"
command -v python3 >/dev/null || die "python3 not found"
python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' || die "python3 3.8+ needed"
command -v mysql >/dev/null || die "mysql client not found"
[[ -f "$SRC/hprv_portal.py" ]] || die "run this from the portal directory"
$MYSQL_ADMIN -N -e 'SELECT 1' >/dev/null 2>&1 \
    || die "cannot reach MySQL as admin with '$MYSQL_ADMIN' (set MYSQL_ADMIN)"

# Database names: from HPRV's own env file when there is one, so a box
# that renamed its schemas gets the grants on the right ones.
[[ -r "$ETC/hprv.env" ]] && { set -a; . "$ETC/hprv.env"; set +a; }
DB_AUTH="${ACORE_DB_AUTH:-acore_auth}"
DB_CHARS="${ACORE_DB_CHARACTERS:-acore_characters}"
DB_WORLD="${ACORE_DB_WORLD:-acore_world}"
DB_BOTS="${ACORE_DB_PLAYERBOTS:-acore_playerbots}"

# 1. code
install -d -m 755 "$DEST" "$DEST/static"
install -m 644 "$SRC/hprv_portal.py" "$DEST/hprv_portal.py"
install -m 644 "$SRC/static/style.css" "$DEST/static/style.css"
log "app copied to $DEST"

# 2. system user
if ! id -u "$SVC_USER" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir /nonexistent \
            --shell /usr/sbin/nologin "$SVC_USER"
    log "system user $SVC_USER created"
fi
install -d -m 755 "$ETC"

# 3 + 4. MySQL user and its option file. The password only ever lives in
# portal.cnf, so if that file exists the user is left alone.
if [[ ! -f "$ETC/portal.cnf" ]]; then
    PASS="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 28)"
    $MYSQL_ADMIN -e "
      CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$PASS';
      ALTER USER '$DB_USER'@'localhost' IDENTIFIED BY '$PASS';"
    umask 027
    cat >"$ETC/portal.cnf" <<EOF
[client]
user=$DB_USER
password=$PASS
host=localhost
EOF
    umask 022
    chown root:"$SVC_USER" "$ETC/portal.cnf"
    chmod 640 "$ETC/portal.cnf"
    log "MySQL user $DB_USER created, password in $ETC/portal.cnf"
fi

# Grants are re-applied every run, so a new column or table the app
# starts reading only needs a re-install. GRANT is additive and safe to repeat.
$MYSQL_ADMIN -e "
  GRANT SELECT (id, username) ON \`$DB_AUTH\`.account TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_AUTH\`.realmlist TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_AUTH\`.uptime TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_CHARS\`.characters TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_CHARS\`.character_inventory TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_CHARS\`.item_instance TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_CHARS\`.guild TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_CHARS\`.group_member TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_CHARS\`.guild_member TO '$DB_USER'@'localhost';
  GRANT SELECT (entry, name, Quality, ItemLevel, InventoryType)
        ON \`$DB_WORLD\`.item_template TO '$DB_USER'@'localhost';
  GRANT SELECT ON \`$DB_BOTS\`.playerbots_account_type TO '$DB_USER'@'localhost';"
log "read-only grants applied"

if [[ ! -f "$ETC/portal.ini" ]]; then
    sed -e "s/^port = .*/port = $PORT/" \
        -e "s/^auth = .*/auth = $DB_AUTH/" \
        -e "s/^characters = .*/characters = $DB_CHARS/" \
        -e "s/^world = .*/world = $DB_WORLD/" \
        -e "s/^playerbots = .*/playerbots = $DB_BOTS/" \
        "$SRC/portal.ini.example" >"$ETC/portal.ini"
    chmod 644 "$ETC/portal.ini"
    log "config written to $ETC/portal.ini — add your [players] there"
fi

# 5. service
cat >/etc/systemd/system/hprv-portal.service <<EOF
[Unit]
Description=HPRV portal (read-only realm status page)
After=network-online.target mysql.service
Wants=network-online.target

[Service]
Type=simple
User=$SVC_USER
Group=$SVC_USER
ExecStart=/usr/bin/python3 $DEST/hprv_portal.py --config $ETC/portal.ini
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable hprv-portal.service >/dev/null
systemctl restart hprv-portal.service
sleep 2
systemctl is-active --quiet hprv-portal.service \
    || die "service did not start — journalctl -u hprv-portal -n 50"

PORT_NOW="$(sed -n 's/^port *= *//p' "$ETC/portal.ini" | head -1)"
if curl -fsS -o /dev/null "http://127.0.0.1:${PORT_NOW:-$PORT}/status.json" 2>/dev/null; then
    log "serving: http://$(hostname -I | awk '{print $1}'):${PORT_NOW:-$PORT}/"
else
    log "service is up but the page did not answer yet — journalctl -u hprv-portal -n 50"
fi
