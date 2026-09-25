#!/usr/bin/env bash
# deploy.sh — push this repo's scripts to the server.
#
#   ./scripts/deploy.sh              # deploy to the default host
#   HPRV_HOST=root@10.0.0.5 ./scripts/deploy.sh
#   ./scripts/deploy.sh --dry-run
#
# WHY THIS EXISTS
#
# roster-status.sh, gear-pass.sh and hprv-spec.sh all read things that
# only exist on the server — /mnt/hprv/server/etc/modules/playerbots.conf,
# /etc/hprv/hprv.env, and a local MySQL socket. Running them from a
# workstation checkout fails with:
#
#   ERROR: cannot read /mnt/hprv/server/etc/modules/playerbots.conf
#
# They are server-side tools kept under version control, not local ones.
# Edit here, deploy, run there.
set -euo pipefail

HPRV_HOST="${HPRV_HOST:-root@192.168.4.124}"
DEST="${HPRV_DEST:-/opt/hprv/scripts}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

DRY=""
[[ "${1:-}" == "--dry-run" ]] && DRY="--dry-run"

# Deliberately NOT --delete. /opt/hprv/scripts also holds artefacts from
# hprv-archive (roster-gruul.conf, timestamped roster backups) that
# are still worth having and are not tracked here.
rsync -av $DRY \
    --chmod=F755 \
    "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/*.conf "$SCRIPT_DIR"/*.sql \
    "$HPRV_HOST:$DEST/"

if [[ -z "$DRY" ]]; then
    printf '\nDeployed to %s:%s\n\n' "$HPRV_HOST" "$DEST"
    printf 'Run them there, e.g.:\n'
    printf '  ssh %s %s/roster-status.sh\n' "$HPRV_HOST" "$DEST"
    printf '  ssh %s %s/hprv-spec.sh Ararin --show\n' "$HPRV_HOST" "$DEST"
fi
