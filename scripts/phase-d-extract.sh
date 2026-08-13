#!/usr/bin/env bash
#
# HPRV — Phase D: extract client data (dbc / maps / vmaps / mmaps).
#
# Runs the four extractor tools built in Phase C against a 3.3.5a client
# on Tank, then moves the results into $HPRV_DATA_DIR for Phase E's
# DataDir. Idempotent: a step whose output already exists is skipped, so
# an interrupted run resumes rather than restarting.
#
# WHAT THIS DOES NOT DO (by design):
#   - It does NOT fetch a game client. Blizzard copyright; Clinton
#     supplies it. See CLAUDE.md guardrails.
#   - It does NOT touch the databases. That's the other half of Phase D.
#   - It does NOT build anything. Phase C already did.
#
# Usage (inside the LXC, as 'acore', NOT root):
#   /opt/hprv/scripts/phase-d-extract.sh [all|maps|vmaps|mmaps]
#
# mmaps takes HOURS on 4 vCPU. Run it under tmux.
#
# Optional env overrides:
#   HPRV_CLIENT_DIR=/mnt/hprv/client    dir containing Data/
#   HPRV_DATA_DIR=/mnt/hprv/data        where output lands
#   HPRV_BIN_DIR=/mnt/hprv/server/bin   the Phase C tools
#   HPRV_FORCE=1                        redo steps that already have output
#   HPRV_MMAPS_THREADS=N                pass --threads N to mmaps_generator
#   HPRV_ALLOW_ROOT=1                   bypass the "don't run as root" guard
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HPRV_CLIENT_DIR="${HPRV_CLIENT_DIR:-/mnt/hprv/client}"
HPRV_DATA_DIR="${HPRV_DATA_DIR:-/mnt/hprv/data}"
HPRV_BIN_DIR="${HPRV_BIN_DIR:-/mnt/hprv/server/bin}"
HPRV_FORCE="${HPRV_FORCE:-0}"
HPRV_MMAPS_THREADS="${HPRV_MMAPS_THREADS:-}"
HPRV_ALLOW_ROOT="${HPRV_ALLOW_ROOT:-0}"

# Extraction writes into the client dir first, then the results are
# renamed into place. Both live under the same mp0 bind-mount, so the
# move is a rename (instant), not a 20 GB copy.
WORK_DIR="$HPRV_CLIENT_DIR"

# maps+vmaps+mmaps+dbc land at 15-25 GB, and Buildings/ is a further
# few GB of intermediate. Refuse early rather than filling the pool.
MIN_FREE_GB=40

log()  { printf '\033[1;32m[phase-d]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[phase-d]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[phase-d]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- Guards -----------------------------------------------------------

require_not_root() {
  if [[ "$(id -u)" -eq 0 && "$HPRV_ALLOW_ROOT" != "1" ]]; then
    die "Run as the service user, not root:
       su -s /bin/bash acore
     Output written as root would leave the daemons unable to manage it,
     and /mnt/hprv is host-root-owned so root cannot fix it from inside.
     (Override with HPRV_ALLOW_ROOT=1 only if you know why.)"
  fi
}

require_tools() {
  local missing=()
  for t in map_extractor vmap4_extractor vmap4_assembler mmaps_generator; do
    [[ -x "$HPRV_BIN_DIR/$t" ]] || missing+=("$t")
  done
  if (( ${#missing[@]} )); then
    die "Missing Phase C tools in $HPRV_BIN_DIR: ${missing[*]}
     These come from -DTOOLS_BUILD=all. If the build predates that flag,
     re-run cmake and make. Note the names use underscores."
  fi
  log "All four extractor tools present."
}

# The single highest-value check in this script. MPQ archives layer, and
# later ones override earlier ones — so a custom content patch silently
# replaces Blizzard's maps, models and DBCs, and the extraction produces
# data for a world the AzerothCore server has never heard of. It builds
# fine, starts fine, and then bots path into geometry that isn't there.
#
# Stock 3.3.5a ships exactly seven lowercase archives in Data/. Private
# server repacks add capitalised, lettered ones (Patch-F.MPQ, Patch-H.MPQ
# ...). Found on this very client, 2026-08-08 — hence the check.
require_stock_client() {
  local data="$HPRV_CLIENT_DIR/Data"
  [[ -d "$data" ]] || die "No Data/ directory at $data.
     Copy the client's Data/ folder there first — see docs/host-create.md."

  local custom=()
  while IFS= read -r f; do custom+=("$(basename "$f")"); done \
    < <(find "$data" -maxdepth 2 -name 'Patch-[A-Z]*.MPQ' 2>/dev/null)

  if (( ${#custom[@]} )); then
    die "Non-stock MPQ archives found in Data/: ${custom[*]}
     These are custom content patches from a private-server repack. They
     override Blizzard's data, and extracting with them present yields
     maps/DBCs that will not match the server. Move them aside first:
       mkdir -p $HPRV_CLIENT_DIR/custom-patches
       mv $data/Patch-[A-Z]*.MPQ $HPRV_CLIENT_DIR/custom-patches/
     (Case-sensitive: this leaves the stock patch.MPQ / patch-2 / patch-3.)"
  fi

  local expected=(common.MPQ common-2.MPQ expansion.MPQ lichking.MPQ
                  patch.MPQ patch-2.MPQ patch-3.MPQ)
  local absent=()
  for m in "${expected[@]}"; do
    [[ -f "$data/$m" ]] || absent+=("$m")
  done
  (( ${#absent[@]} )) && die "Missing stock archives in Data/: ${absent[*]}"

  # The locale dir is the one people forget, and map_extractor fails on
  # it late rather than early.
  local locale_dir
  locale_dir="$(find "$data" -maxdepth 1 -type d -name 'en[A-Z][A-Z]' | head -n1)"
  [[ -n "$locale_dir" ]] \
    || die "No locale directory (enUS/enGB/...) under $data.
     DBC extraction needs it. Copy the whole Data/ tree, not just the MPQs."

  log "Client looks stock: 7 base archives + $(basename "$locale_dir")/."
}

require_space() {
  local free_gb
  free_gb="$(df -BG --output=avail "$HPRV_CLIENT_DIR" | tail -n1 | tr -dc '0-9')"
  if [[ -z "$free_gb" ]]; then
    warn "Could not determine free space — continuing."
    return 0
  fi
  (( free_gb < MIN_FREE_GB )) \
    && die "Only ${free_gb}G free; want >= ${MIN_FREE_GB}G for output + intermediates."
  log "Free space: ${free_gb}G."
}

# ---- Helpers ----------------------------------------------------------

# A step is "done" if its output directory exists and is non-empty. That
# is deliberately cheap rather than a content checksum: the point is to
# make a resumed run skip the hours already paid for, not to verify
# Blizzard's data.
have_output() {
  local d="$1"
  [[ -d "$d" && -n "$(ls -A "$d" 2>/dev/null)" ]]
}

skip_or_run() {
  local label="$1" outdir="$2"
  if have_output "$outdir" && [[ "$HPRV_FORCE" != "1" ]]; then
    log "$label: output already at $outdir — skipping (HPRV_FORCE=1 to redo)."
    return 1
  fi
  return 0
}

# Extractors write into the working directory; move results to the data
# dir. Same filesystem, so this is a rename.
stage_output() {
  local name="$1"
  local src="$WORK_DIR/$name" dst="$HPRV_DATA_DIR/$name"
  [[ -d "$src" ]] || return 0
  if [[ -d "$dst" ]]; then
    if [[ "$HPRV_FORCE" == "1" ]]; then
      warn "$name: replacing existing $dst"
      rm -rf "$dst"
    else
      die "$name: both $src and $dst exist. Refusing to guess which is current."
    fi
  fi
  mv "$src" "$dst"
  log "$name -> $dst ($(du -sh "$dst" 2>/dev/null | cut -f1))"
}

# ---- Steps ------------------------------------------------------------

# map_extractor produces BOTH dbc/ and maps/ in one pass. They are one
# step, not two, however much the phase list implies otherwise.
step_maps() {
  skip_or_run "maps+dbc" "$HPRV_DATA_DIR/maps" || return 0
  log "map_extractor: dbc/ + maps/ (~20-30 min)..."
  ( cd "$WORK_DIR" && "$HPRV_BIN_DIR/map_extractor" )
  stage_output dbc
  stage_output maps
}

step_vmaps() {
  skip_or_run "vmaps" "$HPRV_DATA_DIR/vmaps" || return 0

  # Buildings/ is the expensive half of this step. If it already exists,
  # a previous run got that far and only the assembler failed — redoing
  # 30-45 minutes of extraction to retry a 15-minute assemble is pure
  # waste. HPRV_FORCE=1 still starts over.
  if have_output "$WORK_DIR/Buildings" && [[ "$HPRV_FORCE" != "1" ]]; then
    log "vmap4_extractor: Buildings/ already present — skipping extraction."
  else
    log "vmap4_extractor: raw Buildings/ (~30-45 min)..."
    ( cd "$WORK_DIR" && "$HPRV_BIN_DIR/vmap4_extractor" )
  fi

  have_output "$WORK_DIR/Buildings" \
    || die "vmap4_extractor produced no Buildings/ — nothing to assemble."

  log "vmap4_assembler: Buildings/ -> vmaps/ (~15 min)..."
  mkdir -p "$WORK_DIR/vmaps"
  ( cd "$WORK_DIR" && "$HPRV_BIN_DIR/vmap4_assembler" Buildings vmaps )

  stage_output vmaps
  log "Buildings/ is intermediate and can be deleted: rm -rf $WORK_DIR/Buildings"
}

# The expensive one. mmaps_generator reads maps/ and vmaps/ from its
# working directory — so both must be staged back alongside it, and both
# must be COMPLETE. Starting it against a half-extracted maps/ burns
# hours before failing, which is the whole reason this guard exists.
step_mmaps() {
  skip_or_run "mmaps" "$HPRV_DATA_DIR/mmaps" || return 0

  for d in maps vmaps; do
    have_output "$HPRV_DATA_DIR/$d" \
      || die "mmaps needs $HPRV_DATA_DIR/$d populated first.
     Run the 'maps' and 'vmaps' steps before this one — mmaps_generator
     would otherwise run for hours and then fail."
  done

  # Work against the staged copies rather than re-extracting.
  ln -sfn "$HPRV_DATA_DIR/maps"  "$WORK_DIR/maps"
  ln -sfn "$HPRV_DATA_DIR/vmaps" "$WORK_DIR/vmaps"
  mkdir -p "$WORK_DIR/mmaps"

  # This build ships mmaps-config.yaml beside the binary; the tool looks
  # for it in the working directory.
  if [[ -f "$HPRV_BIN_DIR/mmaps-config.yaml" && ! -f "$WORK_DIR/mmaps-config.yaml" ]]; then
    cp "$HPRV_BIN_DIR/mmaps-config.yaml" "$WORK_DIR/"
    log "Copied mmaps-config.yaml into the working directory."
  fi

  local args=()
  [[ -n "$HPRV_MMAPS_THREADS" ]] && args+=(--threads "$HPRV_MMAPS_THREADS")

  warn "mmaps_generator takes HOURS on 4 vCPU. Detach-safe shell strongly advised."
  log "mmaps_generator: mmaps/ ..."
  ( cd "$WORK_DIR" && "$HPRV_BIN_DIR/mmaps_generator" "${args[@]}" )

  rm -f "$WORK_DIR/maps" "$WORK_DIR/vmaps"
  stage_output mmaps
}

step_summary() {
  cat <<EOF

$(log "Phase D (extraction) state:")

  Client   : $HPRV_CLIENT_DIR
  DataDir  : $HPRV_DATA_DIR
$(for d in dbc maps vmaps mmaps; do
    if have_output "$HPRV_DATA_DIR/$d"; then
      printf '  %-8s : %s\n' "$d" "$(du -sh "$HPRV_DATA_DIR/$d" 2>/dev/null | cut -f1)"
    else
      printf '  %-8s : MISSING\n' "$d"
    fi
  done)

mmaps are non-negotiable — bot pathing depends on them, and a raid of
bots with no mmaps is useless (CLAUDE.md Phase D).

Once all four are present, the client copy is no longer needed:
  rm -rf $HPRV_CLIENT_DIR

Next: the other half of Phase D (DB imports), then Phase E sets
DataDir=$HPRV_DATA_DIR in worldserver.conf.
EOF
}

main() {
  local step="${1:-all}"

  # Every path here is absolute, and each step cds explicitly in a
  # subshell — but `find` fails outright if it cannot restore its initial
  # working directory. `su -s /bin/bash acore` leaves you in root's home,
  # which acore cannot read, so the very first guard dies with a
  # confusing "Failed to restore initial working directory".
  cd / || die "Cannot cd to / — something is very wrong."

  require_not_root
  require_tools
  require_stock_client
  require_space
  mkdir -p "$HPRV_DATA_DIR"

  case "$step" in
    all)   step_maps; step_vmaps; step_mmaps ;;
    maps)  step_maps ;;
    vmaps) step_vmaps ;;
    mmaps) step_mmaps ;;
    *)     die "Unknown step '$step'. Use: all | maps | vmaps | mmaps" ;;
  esac

  step_summary
}

main "$@"
