#!/usr/bin/env bash
#
# hprv-portal — remove it completely, as root. Touches nothing of the
# game server: only the portal's own service, files, users and grants.
set -euo pipefail

MYSQL_ADMIN="${MYSQL_ADMIN:-mysql}"
[[ "$(id -u)" -eq 0 ]] || { echo "run as root" >&2; exit 1; }

systemctl disable --now hprv-portal.service 2>/dev/null || true
rm -f /etc/systemd/system/hprv-portal.service
systemctl daemon-reload
$MYSQL_ADMIN -e "DROP USER IF EXISTS 'hprv_portal'@'localhost';"
rm -rf /opt/hprv/portal
rm -f /etc/hprv/portal.cnf
id -u hprv-portal >/dev/null 2>&1 && userdel hprv-portal
echo "hprv-portal removed. /etc/hprv/portal.ini kept; delete it by hand if you want it gone."
