#!/usr/bin/env bash
# package-npcs.sh — build the raid-NPC package for another server.
#
#   ./scripts/package-npcs.sh            # -> dist/hprv-npcs-<date>.tar.gz
#
# custom/ is the single source. HPRV applies those files by name, and
# this only copies them into the numbered layout the package README
# documents. So a fix made in custom/ reaches both.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/custom"
NAME="hprv-npcs-$(date +%Y%m%d)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

P="$STAGE/$NAME"
mkdir -p "$P/optional"

cp "$SRC/README.md"                       "$P/README.md"
cp "$SRC/precheck.sql"                    "$P/00-precheck.sql"
cp "$SRC/teleporter-npc.sql"              "$P/01-teleporter-npc.sql"
cp "$SRC/tier-vendors.sql"                "$P/02-tier-vendors.sql"
cp "$SRC/weapon-vendor.sql"               "$P/03-weapon-vendor.sql"
cp "$SRC/stormwind-spawns.sql"            "$P/04-stormwind-spawns.sql"
cp "$SRC/weapon-vendor-free-prices.sql"   "$P/optional/weapon-vendor-free-prices.sql"
cp "$SRC/weapon-vendor-revert-prices.sql" "$P/optional/weapon-vendor-revert-prices.sql"
cp "$SRC/uninstall.sql"                   "$P/uninstall.sql"

# Nothing in the package may name HPRV's own database. It has to run
# against whatever the target's world DB is called.
if grep -l 'acore_' "$P"/*.sql "$P"/optional/*.sql; then
    echo "ERROR: a file above names a database explicitly" >&2
    exit 1
fi

mkdir -p "$ROOT/dist"
tar -C "$STAGE" -czf "$ROOT/dist/$NAME.tar.gz" "$NAME"
echo "$ROOT/dist/$NAME.tar.gz"
tar -tzf "$ROOT/dist/$NAME.tar.gz"
