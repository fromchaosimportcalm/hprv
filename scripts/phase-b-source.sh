#!/usr/bin/env bash
#
# HPRV — Phase B: source tree + module, pinned.
#
# Clones the mod-playerbots AzerothCore fork and the module into it, at
# the exact commits recorded in scripts/pins.conf. Idempotent: re-running
# fetches and re-checks out the pins, so it doubles as "put the tree back
# where it should be".
#
# WHAT THIS DOES NOT DO (by design):
#   - It does NOT build. That's Phase C (cmake + make), deliberately
#     separate because it's the 20-40 minute step and wants its own
#     babysitting.
#   - It does NOT fetch the game client or any Blizzard data.
#   - It does NOT touch the databases.
#
# Usage (inside the LXC, as the 'acore' user, NOT root):
#   su - acore
#   /root/hprv/scripts/phase-b-source.sh      # or wherever the repo is
#
# Optional env overrides:
#   HPRV_SRC_ROOT=/mnt/hprv/build/azerothcore   clone target
#   HPRV_PINS=<path>                            pins file
#   HPRV_ALLOW_ROOTFS=1   bypass the "not on the rootfs" guard
#   HPRV_ALLOW_ROOT=1     bypass the "don't run as root" guard
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HPRV_SRC_ROOT="${HPRV_SRC_ROOT:-/mnt/hprv/build/azerothcore}"
HPRV_PINS="${HPRV_PINS:-$SCRIPT_DIR/pins.conf}"
HPRV_ALLOW_ROOTFS="${HPRV_ALLOW_ROOTFS:-0}"
HPRV_ALLOW_ROOT="${HPRV_ALLOW_ROOT:-0}"

# All three measured 2026-08-08 after a completed Phase B + Phase C:
#   source tree (core + module, full history)   1.7 GB
#   build objects + static link                 9.3 GB
#   install prefix (make install)               1.5 GB
#                                              --------
#                                              12.5 GB
#
# The old 12 GB floor was set from a 5-7 GB guess at build output. Build
# output is actually 9.3 GB, so 12 would have PASSED preflight and then
# run the pool dry during Phase C — the exact failure this guard exists
# to prevent. 16 gives a real margin.
#
# Note these are ZFS post-compression figures (`du` on the pool). The
# install prefix is 1.5 GB on disk against ~2.4 GB apparent, because
# worldserver carries RelWithDebInfo debug symbols.
MIN_FREE_GB=16

log()  { printf '\033[1;32m[phase-b]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[phase-b]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[phase-b]\033[0m %s\n' "$*" >&2; exit 1; }

# ---- Guards -----------------------------------------------------------

# The cores must not be owned by root (CLAUDE.md Phase A). A tree cloned
# as root is a tree that has to be chown'd later, usually after the build
# has already written root-owned objects into it.
require_not_root() {
  if [[ "$(id -u)" -eq 0 && "$HPRV_ALLOW_ROOT" != "1" ]]; then
    die "Run as the service user, not root:
       su - acore
     (Override with HPRV_ALLOW_ROOT=1 only if you know why.)"
  fi
}

# /mnt/hprv is a Tank bind-mount; the rootfs is 10 GB on a 92%-full thin
# pool (docs/host-create.md §2). Cloning to /home/acore by mistake is the
# single most likely way to fill the pool, so check the target is on a
# different filesystem than / before writing anything.
require_not_rootfs() {
  local mount_root="${HPRV_SRC_ROOT%%/azerothcore}"
  local probe="$HPRV_SRC_ROOT"
  while [[ ! -d "$probe" && "$probe" != "/" ]]; do probe="$(dirname "$probe")"; done

  local dev_root dev_target
  dev_root="$(stat -c '%d' / 2>/dev/null || echo 0)"
  dev_target="$(stat -c '%d' "$probe" 2>/dev/null || echo 0)"

  if [[ "$dev_root" == "$dev_target" ]]; then
    if [[ "$HPRV_ALLOW_ROOTFS" == "1" ]]; then
      warn "Target is on the rootfs; continuing (HPRV_ALLOW_ROOTFS=1)."
      return 0
    fi
    die "Target '$HPRV_SRC_ROOT' resolves onto the rootfs, not the Tank mount.
     The rootfs is 10 GB on a nearly-full thin pool — a 1.7 GB tree plus build output
     does not belong there (docs/host-create.md §2).
     Check that mp0 is mounted:  df -h /mnt/hprv
     Override only if deliberate: HPRV_ALLOW_ROOTFS=1"
  fi
  log "Target is on a separate filesystem from / (good — Tank mount, not rootfs)."
  unset mount_root
}

require_writable() {
  local probe="$HPRV_SRC_ROOT"
  while [[ ! -d "$probe" && "$probe" != "/" ]]; do probe="$(dirname "$probe")"; done
  if [[ ! -w "$probe" ]]; then
    die "'$probe' is not writable by $(id -un).
     If it shows as nobody:nogroup, the unprivileged UID shift was never
     applied. On the Proxmox host, as root:
       ACORE_UID=\$(pct exec 124 -- id -u acore)
       chown -R \$((100000 + ACORE_UID)):\$((100000 + ACORE_UID)) \\
         /tank/games/hprv/build /tank/games/hprv/data
     See docs/host-create.md §3."
  fi
}

require_space() {
  local probe="$HPRV_SRC_ROOT" free_gb
  while [[ ! -d "$probe" && "$probe" != "/" ]]; do probe="$(dirname "$probe")"; done
  free_gb="$(df -BG --output=avail "$probe" | tail -n1 | tr -dc '0-9')"
  if [[ -z "$free_gb" ]]; then
    warn "Could not determine free space on '$probe' — continuing."
    return 0
  fi
  if (( free_gb < MIN_FREE_GB )); then
    die "Only ${free_gb}G free on '$probe'; want >= ${MIN_FREE_GB}G for the tree + Phase C objects."
  fi
  log "Free space on target: ${free_gb}G."
}

load_pins() {
  [[ -f "$HPRV_PINS" ]] || die "Pins file not found: $HPRV_PINS"
  # shellcheck disable=SC1090
  source "$HPRV_PINS"
  for v in AC_REPO AC_BRANCH AC_COMMIT MOD_REPO MOD_BRANCH MOD_COMMIT; do
    [[ -n "${!v:-}" ]] || die "$v is unset in $HPRV_PINS"
  done
  log "Pins loaded from $HPRV_PINS"
  log "  core   ${AC_COMMIT:0:12}  (${AC_REPO##*/}@${AC_BRANCH})"
  log "  module ${MOD_COMMIT:0:12}  (${MOD_REPO##*/}@${MOD_BRANCH})"
}

# ---- Clone / pin ------------------------------------------------------

# One function for both repos: clone if absent, fetch if present, then
# hard-checkout the pinned SHA and verify we actually landed on it. A
# detached HEAD is correct here — the pin is the point, not tracking a
# branch that moves under the build.
sync_repo() {
  local dir="$1" repo="$2" branch="$3" commit="$4" label="$5"

  if [[ -d "$dir/.git" ]]; then
    log "$label: existing clone at $dir"
    local origin
    origin="$(git -C "$dir" remote get-url origin 2>/dev/null || echo '')"
    if [[ "$origin" != "$repo" ]]; then
      warn "$label: origin is '$origin', pins expect '$repo'."
      warn "$label: leaving the remote alone — fix by hand if this is wrong."
    fi
    if [[ -n "$(git -C "$dir" status --porcelain)" ]]; then
      die "$label: working tree at $dir has local changes.
     Refusing to move HEAD under them. Commit, stash, or clean first."
    fi
  else
    if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]; then
      die "$label: '$dir' exists, is non-empty, and is not a git repo. Move it aside."
    fi
    log "$label: cloning $repo (branch $branch)..."
    if [[ "$label" == "core" ]]; then
      log "  (full history — ~1.7 GB on disk, several minutes. Deliberate: a blobless"
      log "   partial clone would be smaller but needs network at every"
      log "   checkout, and Tank has 14.9 TB. Robustness over disk.)"
    fi
    git clone --branch "$branch" "$repo" "$dir"
  fi

  # Pin may predate or postdate whatever the clone landed on.
  log "$label: fetching..."
  git -C "$dir" fetch --tags origin "$branch"

  if ! git -C "$dir" cat-file -e "${commit}^{commit}" 2>/dev/null; then
    die "$label: pinned commit $commit not found after fetch.
     It may have been force-pushed away, or the pins file is wrong."
  fi

  log "$label: checking out $commit"
  git -C "$dir" checkout --detach --force "$commit"

  local head
  head="$(git -C "$dir" rev-parse HEAD)"
  [[ "$head" == "$commit" ]] || die "$label: HEAD is $head, expected $commit."
  log "$label: pinned at $head"
}

# ---- Verification -----------------------------------------------------

verify_tree() {
  local mod_dir="$HPRV_SRC_ROOT/modules/mod-playerbots"

  [[ -f "$HPRV_SRC_ROOT/CMakeLists.txt" ]] \
    || die "No CMakeLists.txt at $HPRV_SRC_ROOT — that is not an AzerothCore tree."

  # Mirror what the build actually does. GetModuleSourceList() in
  # src/cmake/macros/ConfigureModules.cmake globs modules/* and keeps any
  # entry where modules/<name>/src IS_DIRECTORY. There is no per-module
  # CMakeLists.txt in the contract, and mod-playerbots ships none — an
  # earlier version of this check looked for one and wrongly failed a
  # perfectly good tree.
  [[ -d "$mod_dir/src" ]] \
    || die "No 'src' directory at $mod_dir.
     CMake discovers modules by globbing modules/*/src, so a module
     without it is silently skipped: the core builds fine and has no bots."
  log "Module discoverable by CMake (modules/mod-playerbots/src exists)."

  # Phase D needs the module's SQL; Phase E needs its config template.
  # Cheap to assert now, annoying to discover mid-import.
  [[ -d "$mod_dir/data/sql/playerbots" ]] \
    || warn "Missing data/sql/playerbots — Phase D will have nothing to import."
  [[ -f "$mod_dir/conf/playerbots.conf.dist" ]] \
    || warn "Missing conf/playerbots.conf.dist — Phase E has no config template."

  # Sanity-check the raid strategies this project actually exists for.
  local raid_dir="$mod_dir/src/Ai/Raid"
  local missing=()
  for r in Mag Gruul Kara; do
    [[ -d "$raid_dir/$r" ]] || missing+=("$r")
  done
  if (( ${#missing[@]} )); then
    warn "Raid strategies missing at this pin: ${missing[*]}"
    warn "M2/M3 depend on these. Check the pin before building."
  else
    log "Raid strategies present: Mag, Gruul, Kara (M2 + M3 covered)."
  fi
}

step_summary() {
  local mod_dir="$HPRV_SRC_ROOT/modules/mod-playerbots"
  cat <<EOF

$(log "Phase B complete.")

  Core tree  : $HPRV_SRC_ROOT
               $(git -C "$HPRV_SRC_ROOT" rev-parse HEAD)
  Module     : $mod_dir
               $(git -C "$mod_dir" rev-parse HEAD)
  Pins file  : $HPRV_PINS (committed — both SHAs reproducible from either remote)
  Tree size  : $(du -sh "$HPRV_SRC_ROOT" 2>/dev/null | cut -f1)

Both are on a detached HEAD at the pinned commit. That is intentional —
the pin determines raid-strategy polish, so the tree should not drift
with the branch. To advance: edit $HPRV_PINS, re-run this script, log an
ADR for the move.

Phase D will need a FOURTH schema, acore_playerbots — the module's own
(PlayerbotsDatabaseInfo, with data/sql/playerbots/ to import). Re-run
scripts/phase-a-bootstrap.sh if this container was provisioned before
2026-08-05; it is idempotent and will not rotate the DB password.

Next (Phase C — the 20-40 minute step, still as $(id -un)):
  mkdir -p $HPRV_SRC_ROOT/build && cd $HPRV_SRC_ROOT/build
  cmake ../ -DCMAKE_INSTALL_PREFIX=/mnt/hprv/server \\
    -DTOOLS_BUILD=all -DSCRIPTS=static -DMODULES=static
  make -j\$(nproc)          # drop -j if the link step gets OOM-killed
  make install

Note the install prefix is on Tank, not the rootfs (docs/host-create.md §2).
EOF
}

main() {
  require_not_root
  load_pins
  require_not_rootfs
  require_writable
  require_space

  mkdir -p "$(dirname "$HPRV_SRC_ROOT")"
  sync_repo "$HPRV_SRC_ROOT" "$AC_REPO" "$AC_BRANCH" "$AC_COMMIT" "core"

  mkdir -p "$HPRV_SRC_ROOT/modules"
  sync_repo "$HPRV_SRC_ROOT/modules/mod-playerbots" \
    "$MOD_REPO" "$MOD_BRANCH" "$MOD_COMMIT" "module"

  verify_tree
  step_summary
}

main "$@"
