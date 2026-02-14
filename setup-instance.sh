#!/bin/bash
set -euo pipefail

# ============================================
# n8n Dashboard Analytics — Instance Setup
# ============================================
# Reads an instance .env file, installs dependencies,
# sets up the database schema, and verifies the hooks path.
#
# Usage:
#   ./setup-instance.sh <instance>.env              # run the full setup
#   ./setup-instance.sh <instance>.env --dry-run    # preview without changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "\n${CYAN}==>${NC} $1"; }
dry()   { echo -e "${YELLOW}[DRY-RUN]${NC} Would: $1"; }

# ------------------------------------------
# Parse arguments
# ------------------------------------------
if [[ $# -lt 1 ]]; then
  err "Usage: $0 <instance>.env [--dry-run]"
  echo "  Example: $0 psync1.env"
  echo "  Example: $0 ctg.env --dry-run"
  exit 1
fi

ENV_FILE="$1"
DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

if [[ ! -f "$ENV_FILE" ]]; then
  err "File not found: $ENV_FILE"
  exit 1
fi

# ------------------------------------------
# Helper: read a value from the .env file
# ------------------------------------------
env_get() {
  local key="$1"
  local default="${2:-}"
  local value
  value=$(grep -m1 "^${key}=" "$ENV_FILE" | sed 's/^[^=]*=//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  if [[ -z "$value" ]]; then
    echo "$default"
  else
    echo "$value"
  fi
}

# ------------------------------------------
# 0. Parse .env file
# ------------------------------------------
INSTANCE_NAME=$(basename "$ENV_FILE" .env)
step "Parsing $ENV_FILE for instance '$INSTANCE_NAME'..."

DB_HOST=$(env_get DB_POSTGRESDB_HOST localhost)
DB_PORT=$(env_get DB_POSTGRESDB_PORT 5432)
DB_NAME=$(env_get DB_POSTGRESDB_DATABASE "$INSTANCE_NAME")
DB_USER=$(env_get DB_POSTGRESDB_USER "$INSTANCE_NAME")
DB_PASS=$(env_get DB_POSTGRESDB_PASSWORD "")
N8N_HOST=$(env_get N8N_HOST "")
N8N_PORT=$(env_get N8N_PORT "")
HOOKS_PATH=$(env_get EXTERNAL_HOOK_FILES "")

if [[ -z "$DB_PASS" ]]; then
  err "DB_POSTGRESDB_PASSWORD not found in $ENV_FILE"
  exit 1
fi

info "Instance:  $INSTANCE_NAME"
info "Domain:    $N8N_HOST"
info "n8n port:  $N8N_PORT"
info "Database:  $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"
if [[ -n "$HOOKS_PATH" ]]; then
  info "Hooks:     $HOOKS_PATH"
fi

# ------------------------------------------
# 1. Check prerequisites
# ------------------------------------------
step "Checking prerequisites..."

if ! command -v node &>/dev/null; then
  err "Node.js is not installed. Install Node.js v18+ first."
  exit 1
fi
info "Node.js $(node -v)"

if ! command -v npm &>/dev/null; then
  err "npm is not found."
  exit 1
fi
info "npm $(npm -v)"

if ! command -v n8n &>/dev/null; then
  err "n8n is not installed. Install with: npm install -g n8n@latest"
  exit 1
fi
info "n8n $(n8n --version)"

if ! command -v pm2 &>/dev/null; then
  err "pm2 is not installed. Install with: npm install -g pm2"
  exit 1
fi
info "pm2 $(pm2 -v)"

if ! command -v psql &>/dev/null; then
  err "psql is not installed. Install postgresql-client first."
  exit 1
fi
info "psql available"

# Check if this instance is already running in pm2
if pm2 list 2>/dev/null | grep -q "$INSTANCE_NAME"; then
  info "$INSTANCE_NAME is running in pm2"
else
  warn "$INSTANCE_NAME is not running in pm2 yet."
fi

# ------------------------------------------
# 2. Install npm dependencies (pg)
# ------------------------------------------
step "Installing npm dependencies..."

if $DRY_RUN; then
  dry "npm install --prefix $SCRIPT_DIR"
else
  npm install --prefix "$SCRIPT_DIR"
  info "pg module installed"
fi

# ------------------------------------------
# 3. Set up database schema
# ------------------------------------------
step "Setting up database schema for '$DB_NAME'..."

SCHEMA_FILE="$SCRIPT_DIR/schema.sql"

if [[ ! -f "$SCHEMA_FILE" ]]; then
  err "Schema file not found: $SCHEMA_FILE"
  exit 1
fi

if $DRY_RUN; then
  dry "psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c 'SELECT 1'"
  dry "psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f $SCHEMA_FILE"
else
  if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1" &>/dev/null; then
    info "Database connection successful"
  else
    err "Cannot connect to PostgreSQL at $DB_HOST:$DB_PORT/$DB_NAME as $DB_USER"
    echo "    Ensure PostgreSQL is running and accepts TCP connections."
    echo "    Check pg_hba.conf and postgresql.conf if needed."
    exit 1
  fi

  PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE"
  info "Schema applied — n8n_execution_logs table ready"
fi

# ------------------------------------------
# 4. Verify hooks file
# ------------------------------------------
step "Verifying hooks file..."

if [[ -z "$HOOKS_PATH" ]]; then
  warn "EXTERNAL_HOOK_FILES not set in $ENV_FILE"
  warn "Add this line to $ENV_FILE:"
  echo "    EXTERNAL_HOOK_FILES=$SCRIPT_DIR/hooks/execution-hooks.js"
else
  if [[ -f "$HOOKS_PATH" ]]; then
    info "Hooks file exists: $HOOKS_PATH"
  else
    # The path may be for a remote/container filesystem — check local equivalent
    LOCAL_HOOKS="$SCRIPT_DIR/hooks/execution-hooks.js"
    if [[ -f "$LOCAL_HOOKS" ]]; then
      warn "Hooks path in .env ($HOOKS_PATH) not found locally, but local file exists: $LOCAL_HOOKS"
      warn "Ensure the path is correct for the runtime environment."
    else
      err "Hooks file not found: $HOOKS_PATH"
      err "Also not found locally at: $LOCAL_HOOKS"
      exit 1
    fi
  fi
fi

# ------------------------------------------
# 5. Summary
# ------------------------------------------
echo ""
echo -e "${GREEN}============================================${NC}"
if $DRY_RUN; then
  echo -e "${GREEN} Dry run complete — no changes were made${NC}"
else
  echo -e "${GREEN} Setup complete for instance: $INSTANCE_NAME${NC}"
fi
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Start this n8n instance with pm2:"
echo "     pm2 start n8n --name $INSTANCE_NAME --env-file $ENV_FILE"
echo ""
echo "  2. Check the logs:"
echo "     pm2 logs $INSTANCE_NAME --lines 20"
echo ""
echo "  3. Look for these lines:"
echo "     [HOOK FILE] execution-hooks.js loaded at: ..."
echo "     [HOOK] n8n.ready - Server is ready!"
echo "     [HOOK] PostgreSQL connection verified at: ..."
echo ""
echo "  4. Run a workflow, then verify:"
echo "     PGPASSWORD='$DB_PASS' psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \\"
echo "       -c \"SELECT execution_id, workflow_name, status FROM n8n_execution_logs ORDER BY created_at DESC LIMIT 5;\""
