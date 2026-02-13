#!/bin/bash
set -euo pipefail

# ============================================
# n8n Dashboard Analytics — Setup Script
# ============================================
# Clones the repo, sets up the database, installs dependencies,
# and configures n8n to load the execution hooks.
#
# Usage:
#   ./setup.sh              # run the full setup
#   ./setup.sh --dry-run    # preview what would be done without making changes

REPO_URL="https://github.com/avanaihq/n8n-dashboard-analytics.git"
INSTALL_DIR="$HOME/n8n-dashboard-analytics"
ECOSYSTEM="$HOME/ecosystem.config.js"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "\n${CYAN}==>${NC} $1"; }
dry()   { echo -e "${YELLOW}[DRY-RUN]${NC} Would: $1"; }

# ------------------------------------------
# 0. Prerequisites
# ------------------------------------------
step "Checking prerequisites..."

# Node.js
if ! command -v node &>/dev/null; then
  err "Node.js is not installed. Install Node.js v18+ first."
  exit 1
fi
NODE_VER=$(node -v)
info "Node.js $NODE_VER"

# npm
if ! command -v npm &>/dev/null; then
  err "npm is not found."
  exit 1
fi
info "npm $(npm -v)"

# n8n
if ! command -v n8n &>/dev/null; then
  err "n8n is not installed. Install with: npm install -g n8n@latest"
  exit 1
fi
info "n8n $(n8n --version)"

# pm2
if ! command -v pm2 &>/dev/null; then
  err "pm2 is not installed. Install with: npm install -g pm2"
  exit 1
fi
info "pm2 $(pm2 -v)"

# pm2 running n8n
if ! pm2 list 2>/dev/null | grep -q "n8n"; then
  warn "n8n is not running in pm2. It will need to be restarted after setup."
else
  info "n8n is running in pm2"
fi

# psql
if ! command -v psql &>/dev/null; then
  err "psql is not installed. Install postgresql-client first."
  exit 1
fi
info "psql available"

# ecosystem.config.js
if [[ ! -f "$ECOSYSTEM" ]]; then
  err "$ECOSYSTEM not found. Create it first with your n8n pm2 config."
  exit 1
fi
info "Found $ECOSYSTEM"

# ------------------------------------------
# 1. Extract DB credentials from ecosystem.config.js
# ------------------------------------------
step "Reading database credentials from $ECOSYSTEM..."

DB_HOST=$(node -e "const c = require('$ECOSYSTEM'); console.log(c.apps[0].env.DB_POSTGRESDB_HOST || 'localhost')")
DB_PORT=$(node -e "const c = require('$ECOSYSTEM'); console.log(c.apps[0].env.DB_POSTGRESDB_PORT || 5432)")
DB_NAME=$(node -e "const c = require('$ECOSYSTEM'); console.log(c.apps[0].env.DB_POSTGRESDB_DATABASE || 'n8n')")
DB_USER=$(node -e "const c = require('$ECOSYSTEM'); console.log(c.apps[0].env.DB_POSTGRESDB_USER || 'n8n')")
DB_PASS=$(node -e "const c = require('$ECOSYSTEM'); console.log(c.apps[0].env.DB_POSTGRESDB_PASSWORD || '')")

if [[ -z "$DB_PASS" ]]; then
  err "DB_POSTGRESDB_PASSWORD not found in $ECOSYSTEM"
  exit 1
fi

info "Database: $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME"

# ------------------------------------------
# 2. Clone repository
# ------------------------------------------
step "Setting up repository..."

if [[ -d "$INSTALL_DIR" ]]; then
  info "Directory $INSTALL_DIR already exists, pulling latest changes"
  if $DRY_RUN; then
    dry "git -C $INSTALL_DIR pull"
  else
    git -C "$INSTALL_DIR" pull
  fi
else
  if $DRY_RUN; then
    dry "git clone $REPO_URL $INSTALL_DIR"
  else
    git clone "$REPO_URL" "$INSTALL_DIR"
  fi
fi

# ------------------------------------------
# 3. Install npm dependencies (pg)
# ------------------------------------------
step "Installing npm dependencies..."

if $DRY_RUN; then
  dry "npm install --prefix $INSTALL_DIR"
else
  npm install --prefix "$INSTALL_DIR"
  info "pg module installed"
fi

# ------------------------------------------
# 4. Create database table
# ------------------------------------------
step "Setting up database schema..."

SCHEMA_FILE="$INSTALL_DIR/schema.sql"

# Test database connection
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
# 5. Configure EXTERNAL_HOOK_FILES in ecosystem.config.js
# ------------------------------------------
step "Configuring ecosystem.config.js..."

HOOKS_PATH="$INSTALL_DIR/hooks/execution-hooks.js"

# Check if EXTERNAL_HOOK_FILES is already set
if grep -q "EXTERNAL_HOOK_FILES" "$ECOSYSTEM"; then
  CURRENT=$(node -e "const c = require('$ECOSYSTEM'); console.log(c.apps[0].env.EXTERNAL_HOOK_FILES || '')")
  if [[ "$CURRENT" == "$HOOKS_PATH" ]]; then
    info "EXTERNAL_HOOK_FILES already set correctly"
  else
    warn "EXTERNAL_HOOK_FILES is set to: $CURRENT"
    warn "Expected: $HOOKS_PATH"
    if $DRY_RUN; then
      dry "Update EXTERNAL_HOOK_FILES in $ECOSYSTEM to '$HOOKS_PATH'"
    else
      sed -i "s|EXTERNAL_HOOK_FILES:.*|EXTERNAL_HOOK_FILES: '$HOOKS_PATH'|" "$ECOSYSTEM"
      info "Updated EXTERNAL_HOOK_FILES in $ECOSYSTEM"
    fi
  fi
else
  if $DRY_RUN; then
    dry "Add EXTERNAL_HOOK_FILES: '$HOOKS_PATH' to $ECOSYSTEM"
  else
    # Insert EXTERNAL_HOOK_FILES before the closing brace of env block
    sed -i "/env: {/,/}/ {
      /}/ i\\      EXTERNAL_HOOK_FILES: '$HOOKS_PATH',
    }" "$ECOSYSTEM"

    # Verify it was added
    if grep -q "EXTERNAL_HOOK_FILES" "$ECOSYSTEM"; then
      info "Added EXTERNAL_HOOK_FILES to $ECOSYSTEM"
    else
      err "Failed to add EXTERNAL_HOOK_FILES automatically."
      echo "    Please add this line manually inside the env: { } block in $ECOSYSTEM:"
      echo "      EXTERNAL_HOOK_FILES: '$HOOKS_PATH'"
    fi
  fi
fi

# ------------------------------------------
# 6. Summary
# ------------------------------------------
echo ""
echo -e "${GREEN}============================================${NC}"
if $DRY_RUN; then
  echo -e "${GREEN} Dry run complete — no changes were made${NC}"
else
  echo -e "${GREEN} Setup complete!${NC}"
fi
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart n8n to load the hooks:"
echo "     pm2 delete n8n && pm2 start $ECOSYSTEM"
echo ""
echo "  2. Check the logs for hook output:"
echo "     pm2 logs n8n --lines 20"
echo ""
echo "  3. Look for these lines:"
echo "     [HOOK FILE] execution-hooks.js loaded at: ..."
echo "     [HOOK] n8n.ready - Server is ready!"
echo "     [HOOK] PostgreSQL connection verified at: ..."
echo ""
echo "  4. Run a workflow in n8n, then verify:"
echo "     PGPASSWORD='$DB_PASS' psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME \\"
echo "       -c \"SELECT execution_id, workflow_name, status FROM n8n_execution_logs ORDER BY created_at DESC LIMIT 5;\""
