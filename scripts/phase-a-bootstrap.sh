#!/usr/bin/env bash
#
# HPRV — Phase A bootstrap
# Prepares a fresh Ubuntu 22.04 LXC for the AzerothCore + mod-playerbots
# build. Idempotent: safe to re-run. Stops cleanly at the build
# boundary (Phase B/C do the clone + compile).
#
# WHAT THIS DOES NOT DO (by design):
#   - It does NOT create the LXC. Container creation, Tank ZFS
#     allocation, and vCPU/RAM sizing are host-side operations on the
#     Proxmox host — see docs/host-create.md. Run this script INSIDE
#     the container once it exists.
#   - It does NOT fetch the game client or any Blizzard data.
#   - It does NOT open any firewall ports.
#   - It does NOT clone or build AzerothCore (that's Phase B/C).
#
# SECRETS: follows the ClintonOps house pattern (.env + .env.example,
# see clintonops-infra README "Never committed: .env files"). The DB
# password lives in an env file on the container only; the repo carries
# scripts/hprv.env.example as the template. Nothing secret is ever
# written into the repo.
#
# Usage (inside the LXC, as root or via sudo):
#   ./phase-a-bootstrap.sh
#
# Optional env overrides:
#   ACORE_USER=acore            service user that owns build + daemons
#   ACORE_DB_USER=acore         MySQL user
#   ACORE_DB_PASS=...           supply your own; else generated once
#   HPRV_ENV_FILE=/etc/hprv/hprv.env
#   HPRV_ROTATE_DB_PASS=1       explicitly rotate an existing password
#   HPRV_ALLOW_NON_CONTAINER=1  bypass the "am I in the LXC?" guard
#
set -euo pipefail

# ---- Config (override via env) ---------------------------------------
ACORE_USER="${ACORE_USER:-acore}"
ACORE_DB_USER="${ACORE_DB_USER:-acore}"
ACORE_DB_PASS="${ACORE_DB_PASS:-}"
HPRV_ENV_FILE="${HPRV_ENV_FILE:-/etc/hprv/hprv.env}"
HPRV_ROTATE_DB_PASS="${HPRV_ROTATE_DB_PASS:-0}"
HPRV_ALLOW_NON_CONTAINER="${HPRV_ALLOW_NON_CONTAINER:-0}"
# ----------------------------------------------------------------------

log()  { printf '\033[1;32m[phase-a]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[phase-a]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[phase-a]\033[0m %s\n' "$*" >&2; exit 1; }

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "Run as root (or via sudo) inside the LXC."
  fi
}

# This script runs apt full-upgrade and reconfigures MySQL. Running it
# on the Proxmox host by mistake would be genuinely bad, so refuse
# unless we can see we're containerised.
require_container() {
  local virt="unknown"
  if command -v systemd-detect-virt &>/dev/null; then
    virt="$(systemd-detect-virt --container 2>/dev/null || echo none)"
  fi
  if [[ "$virt" == "lxc" || "$virt" == "lxc-libvirt" ]]; then
    return 0
  fi
  if [[ -e /proc/1/environ ]] && grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then
    return 0
  fi
  if [[ "$HPRV_ALLOW_NON_CONTAINER" == "1" ]]; then
    warn "Container guard bypassed (HPRV_ALLOW_NON_CONTAINER=1). Detected: ${virt}"
    return 0
  fi
  die "Not running inside an LXC (detected: ${virt}).
     This script is for the HPRV container, not the Proxmox host.
     If you are certain, re-run with HPRV_ALLOW_NON_CONTAINER=1."
}

check_ubuntu_2204() {
  if ! grep -q 'VERSION_ID="22.04"' /etc/os-release 2>/dev/null; then
    warn "This targets Ubuntu 22.04. Detected:"
    warn "  $(grep PRETTY_NAME /etc/os-release || echo unknown)"
    warn "Continuing, but deps/versions may differ."
  fi
}

# ---- 1. System update -------------------------------------------------
step_update() {
  log "Updating apt and upgrading base system..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get full-upgrade -y
}

# ---- 2. Build + runtime dependencies ---------------------------------
# Matches the Phase A dep list in CLAUDE.md, plus a few the AC build
# needs in practice. apt is idempotent.
step_deps() {
  log "Installing build + runtime dependencies..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y \
    git cmake make gcc g++ clang \
    libmysqlclient-dev libssl-dev libbz2-dev \
    libreadline-dev libncurses-dev libboost-all-dev \
    mysql-server \
    curl unzip zip pkg-config libgoogle-perftools-dev \
    libtool m4 autoconf openssl ca-certificates
}

# ---- 3. Service user --------------------------------------------------
# Non-root user owns the build and runs the daemons. Never run the
# cores as root. Idempotent: skips if the user already exists.
#
# Note: the ansible common role in clintonops-infra provisions a generic
# 'apps' user on shared LXCs. HPRV deliberately uses its own 'acore'
# user instead — CLAUDE.md Phase A calls for it, and the cores want a
# dedicated owner for the build tree and the systemd units.
step_user() {
  if id "$ACORE_USER" &>/dev/null; then
    log "Service user '$ACORE_USER' already exists — skipping."
  else
    log "Creating service user '$ACORE_USER'..."
    useradd --create-home --shell /bin/bash "$ACORE_USER"
  fi
}

# ---- 4. Secrets: resolve the DB password ------------------------------
# Precedence:
#   1. Existing env file  (re-run: reuse, never silently rotate)
#   2. ACORE_DB_PASS from the environment
#   3. Generate one
# Rotation is opt-in via HPRV_ROTATE_DB_PASS=1, because rotating behind
# an already-configured worldserver.conf would break a working install.
step_secrets() {
  local env_dir
  env_dir="$(dirname "$HPRV_ENV_FILE")"
  install -d -o root -g "$ACORE_USER" -m 750 "$env_dir"

  local existing=""
  if [[ -f "$HPRV_ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    existing="$(grep -E '^ACORE_DB_PASS=' "$HPRV_ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  fi

  if [[ -n "$existing" && "$HPRV_ROTATE_DB_PASS" != "1" ]]; then
    log "Reusing DB password from $HPRV_ENV_FILE (set HPRV_ROTATE_DB_PASS=1 to rotate)."
    ACORE_DB_PASS="$existing"
    DB_PASS_IS_NEW=0
  else
    if [[ -n "$existing" && "$HPRV_ROTATE_DB_PASS" == "1" ]]; then
      warn "Rotating DB password. Any worldserver.conf/authserver.conf still"
      warn "holding the old one must be updated (Phase E)."
    fi

    if [[ -z "$ACORE_DB_PASS" ]]; then
      log "Generating a DB password."
      ACORE_DB_PASS="$(openssl rand -base64 24)"
    else
      log "Using ACORE_DB_PASS from the environment."
    fi
    DB_PASS_IS_NEW=1
  fi

  # The file is rewritten every run, not just when the password is new.
  # Re-running is how this script delivers *new* keys (ACORE_DB_PLAYERBOTS
  # was added after the first run against CT 124) — an early return on the
  # reuse path would leave an already-provisioned container permanently
  # missing them. The password written is the one resolved above, so a
  # plain re-run still cannot rotate it.
  #
  # Subshell so the restrictive umask cannot leak into later steps —
  # the MySQL drop-in written in step_mysql must stay world-readable
  # or mysqld (running as the mysql user) will not read it.
  ( umask 077
    cat > "$HPRV_ENV_FILE" <<EOF
# HPRV — generated by scripts/phase-a-bootstrap.sh. DO NOT COMMIT.
# Template: scripts/hprv.env.example
ACORE_DB_HOST=127.0.0.1
ACORE_DB_PORT=3306
ACORE_DB_USER=${ACORE_DB_USER}
ACORE_DB_PASS=${ACORE_DB_PASS}
ACORE_DB_AUTH=acore_auth
ACORE_DB_CHARACTERS=acore_characters
ACORE_DB_WORLD=acore_world
ACORE_DB_PLAYERBOTS=acore_playerbots
EOF
  )
  chown root:"$ACORE_USER" "$HPRV_ENV_FILE"
  chmod 640 "$HPRV_ENV_FILE"
  log "Wrote $HPRV_ENV_FILE (root:${ACORE_USER}, mode 640)."
}

# ---- 5. MySQL: service up, hardened, DB user + schemas ----------------
# Creates the three schemas AzerothCore owns and a DB user scoped to
# them. ALL PRIVILEGES on those three schemas is what AC actually needs
# — dbimport creates, alters and drops tables — but the grant stops at
# the schema boundary; the user has nothing server-wide.
step_mysql() {
  log "Ensuring MySQL is running and enabled..."
  systemctl enable --now mysql

  # Bind to loopback only. Ubuntu's default already does this, but the
  # "never expose ports" guardrail is worth pinning rather than
  # inheriting from a package default that could change.
  local bind_conf=/etc/mysql/mysql.conf.d/zz-hprv-bind.cnf
  if [[ ! -f "$bind_conf" ]]; then
    log "Pinning MySQL bind-address to 127.0.0.1..."
    cat > "$bind_conf" <<'EOF'
# HPRV: never expose MySQL beyond the container. See CLAUDE.md guardrails.
[mysqld]
bind-address = 127.0.0.1
EOF
    chmod 644 "$bind_conf"
    systemctl restart mysql
  else
    log "MySQL bind-address already pinned — skipping."
  fi

  # The non-interactive equivalent of the parts of
  # mysql_secure_installation that matter here: no anonymous users, no
  # remote root, no test database. Idempotent.
  log "Applying MySQL hardening (anonymous users, remote root, test db)..."
  mysql --protocol=socket -u root <<'SQL'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

  log "Creating AzerothCore schemas and DB user (idempotent)..."
  # FOUR schemas, not three. acore_playerbots is owned by mod-playerbots,
  # not stock AzerothCore — worldserver reads it as PlayerbotsDatabaseInfo
  # and the module ships data/sql/playerbots/{base,updates} against it.
  # Missing it does not fail here; it fails later at Phase D/F, which is a
  # much worse place to find out.
  # Uses local root socket auth (default on fresh Ubuntu mysql-server).
  mysql --protocol=socket -u root <<SQL
CREATE DATABASE IF NOT EXISTS acore_auth       DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS acore_characters DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS acore_world      DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS acore_playerbots DEFAULT CHARSET utf8mb4 COLLATE utf8mb4_general_ci;

CREATE USER IF NOT EXISTS '${ACORE_DB_USER}'@'localhost' IDENTIFIED BY '${ACORE_DB_PASS}';

GRANT ALL PRIVILEGES ON acore_auth.*       TO '${ACORE_DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON acore_characters.* TO '${ACORE_DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON acore_world.*      TO '${ACORE_DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON acore_playerbots.* TO '${ACORE_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

  # Only touch the password when we actually minted a new one, so a
  # plain re-run can't rotate it out from under a configured core.
  if [[ "${DB_PASS_IS_NEW:-0}" == "1" ]]; then
    log "Setting DB user password..."
    mysql --protocol=socket -u root <<SQL
ALTER USER '${ACORE_DB_USER}'@'localhost' IDENTIFIED BY '${ACORE_DB_PASS}';
FLUSH PRIVILEGES;
SQL
  fi

  log "Verifying the DB user can actually connect..."
  if mysql -h 127.0.0.1 -u "$ACORE_DB_USER" -p"$ACORE_DB_PASS" -e 'SELECT 1;' &>/dev/null; then
    log "DB credentials verified."
  else
    die "DB user '${ACORE_DB_USER}' cannot connect with the resolved password.
     If this container had a prior install, re-run with HPRV_ROTATE_DB_PASS=1."
  fi
}

# ---- 6. Summary / handoff --------------------------------------------
step_summary() {
  cat <<EOF

$(log "Phase A complete.")

  Service user : ${ACORE_USER}
  DB user      : ${ACORE_DB_USER}@localhost
  DB password  : ${HPRV_ENV_FILE} (root:${ACORE_USER}, mode 640)
  Schemas      : acore_auth, acore_characters, acore_world, acore_playerbots
  MySQL        : bound to 127.0.0.1, anon users + test db removed

Next (Phase B — do NOT run as root; su to ${ACORE_USER}):
  - Clone the liyunfan1223 AzerothCore playerbots fork (NOT stock AC).
  - Add mod-playerbots into modules/.
  - Pin both to known-good commits and record the two SHAs as an ADR.

Phase E will read DB settings from ${HPRV_ENV_FILE}; systemd units can
consume it directly with EnvironmentFile=.

Not done here (by design): LXC creation, client data, firewall,
AzerothCore clone/build. See CLAUDE.md Phases B–I and docs/host-create.md.
EOF
}

main() {
  require_root
  require_container
  check_ubuntu_2204
  step_update
  step_deps
  step_user
  step_secrets
  step_mysql
  step_summary
}

main "$@"
