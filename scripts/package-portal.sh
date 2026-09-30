#!/usr/bin/env bash
# package-portal.sh — build the portal package for another HPRV server.
#
#   ./scripts/package-portal.sh          # -> dist/hprv-portal-<date>.tar.gz
#
# portal/ is the single source, the same arrangement as package-npcs.sh.
# The target unpacks it and runs install.sh as root; portal/README.md is
# the whole of the instructions.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/portal"
NAME="hprv-portal-$(date +%Y%m%d)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

( cd "$SRC" && python3 -m unittest -q test_portal.py )

P="$STAGE/$NAME"
mkdir -p "$P/static"
cp "$SRC/README.md" "$SRC/hprv_portal.py" "$SRC/portal.ini.example" "$P/"
cp "$SRC/install.sh" "$SRC/uninstall.sh" "$P/"
cp "$SRC/static/style.css" "$P/static/"
chmod 755 "$P/install.sh" "$P/uninstall.sh"

mkdir -p "$ROOT/dist"
tar -C "$STAGE" -czf "$ROOT/dist/$NAME.tar.gz" "$NAME"
echo "$ROOT/dist/$NAME.tar.gz"
tar -tzf "$ROOT/dist/$NAME.tar.gz"
