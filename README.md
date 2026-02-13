# n8n Execution Dashboard - Backend

An observability backend for n8n workflows. Captures every workflow execution from a locally-hosted n8n instance using internal lifecycle hooks and stores the data in a local PostgreSQL database for monitoring and analytics.

### Frontend UI

The dashboard frontend is a separate project:
**[n8n Dashboard Analytics UI](https://github.com/avanaihq/n8n-dashboard-anatlycis-ui)**

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   n8n Instance  │────▶│  Execution Hooks │────▶│   PostgreSQL    │
│  (localhost)    │     │  (JavaScript)    │     │   (localhost)   │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                                                          ▼
                                                 ┌─────────────────┐
                                                 │  Dashboard UI   │
                                                 └─────────────────┘
```

n8n fires internal lifecycle hooks on every workflow event. The hooks file (`hooks/execution-hooks.js`) intercepts `workflow.postExecute`, extracts execution metadata and node outputs, and inserts a row into the `n8n_execution_logs` table via the `pg` (node-postgres) package.

## Prerequisites

- **Node.js** v18+ (v22 recommended)
- **PostgreSQL** 14+ running locally
- **n8n** installed globally (`npm install -g n8n@latest`)

## Setup

### Step 1: Clone the repository

```bash
git clone git@github.com:avanaihq/n8n-dashboard-analytics.git
cd n8n-dashboard-analytics
```

### Step 2: Install the `pg` dependency

The hooks file uses the `pg` npm package to connect to PostgreSQL. Install it in the project directory:

```bash
npm install
```

This installs `pg` into `./node_modules`, which Node.js can resolve when n8n loads the hooks file.

### Step 3: Set up PostgreSQL

If you don't have a PostgreSQL database yet, create one:

```bash
# Connect as the postgres superuser
sudo -u postgres psql

# Inside psql, run:
CREATE USER n8n WITH PASSWORD 'your-secure-password';
CREATE DATABASE n8n OWNER n8n;
\q
```

Then apply the schema to create the `n8n_execution_logs` table:

```bash
psql -h localhost -U n8n -d n8n -f schema.sql
```

You'll be prompted for the password you set above. You should see:

```
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
CREATE INDEX
```

#### PostgreSQL connection settings

If PostgreSQL is only listening on Unix sockets (default on some systems), you may need to enable TCP connections:

1. Find your `postgresql.conf` (usually `/etc/postgresql/*/main/postgresql.conf`):
   ```bash
   sudo grep -r "listen_addresses" /etc/postgresql/
   ```

2. Set it to listen on localhost:
   ```
   listen_addresses = 'localhost'
   ```

3. In `pg_hba.conf` (same directory), ensure there's a line allowing local TCP connections:
   ```
   # TYPE  DATABASE  USER  ADDRESS       METHOD
   host    n8n       n8n   127.0.0.1/32  md5
   ```

4. Restart PostgreSQL:
   ```bash
   sudo systemctl restart postgresql
   ```

### Step 4: Configure environment variables

Copy the example file and fill in your values:

```bash
cp .env.example .env
```

Edit `.env`:

```env
# n8n Configuration
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost:5678/

# Tell n8n to load the execution hooks
# Use the ABSOLUTE path to the hooks file on your system
EXTERNAL_HOOK_FILES=/absolute/path/to/n8n-dashboard-analytics/hooks/execution-hooks.js

# PostgreSQL Configuration
DB_POSTGRESDB_HOST=localhost
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=your-secure-password
```

**Important**: `EXTERNAL_HOOK_FILES` must be an **absolute path** to `hooks/execution-hooks.js` on your filesystem.

### Step 5: Start n8n

Load the `.env` file and start n8n:

```bash
# Option A: Export the env vars and run n8n
set -a && source .env && set +a
n8n start

# Option B: Use env-cmd or dotenv-cli if installed
npx env-cmd n8n start
```

n8n will be available at **http://localhost:5678**

### Step 6: Verify it's working

In the n8n startup output, look for these log lines:

```
[HOOK FILE] execution-hooks.js loaded at: 2025-01-01T00:00:00.000Z
[HOOK] n8n.ready - Server is ready!
[HOOK] PostgreSQL connection verified at: 2025-01-01T00:00:00.000Z
```

If you see `PostgreSQL connection verified`, the hooks are connected to the database.

Now run any workflow in n8n (even a simple manual test), then verify the execution was logged:

```bash
psql -h localhost -U n8n -d n8n -c \
  "SELECT execution_id, workflow_name, status, duration_ms FROM n8n_execution_logs ORDER BY created_at DESC LIMIT 5;"
```

## What Gets Captured

Every time a workflow executes, the hook captures:

| Data | Description |
|------|-------------|
| Execution ID | Unique identifier for the execution |
| Workflow ID & name | Which workflow ran |
| Status | `success`, `error`, `running`, `waiting`, or `canceled` |
| Timing | Start time, end time, duration in milliseconds |
| Mode | How it was triggered: `manual`, `trigger`, `webhook`, etc. |
| Node count | Number of nodes that executed |
| Error message | Error details if the execution failed |
| Execution data (JSONB) | Full node outputs and run data |
| Workflow data (JSONB) | Workflow definition (nodes, connections, settings) |

## Database Schema

The `n8n_execution_logs` table:

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key (auto-generated) |
| `execution_id` | TEXT | n8n execution ID (unique) |
| `workflow_id` | TEXT | Workflow ID |
| `workflow_name` | TEXT | Workflow name |
| `status` | TEXT | success, error, running, waiting, canceled |
| `finished` | BOOLEAN | Whether execution completed |
| `started_at` | TIMESTAMPTZ | Execution start time |
| `finished_at` | TIMESTAMPTZ | Execution end time |
| `duration_ms` | INTEGER | Duration in milliseconds |
| `mode` | TEXT | Trigger mode |
| `node_count` | INTEGER | Number of nodes executed |
| `error_message` | TEXT | Error details (null if successful) |
| `execution_data` | JSONB | Full execution data and node outputs |
| `workflow_data` | JSONB | Workflow definition snapshot |
| `created_at` | TIMESTAMPTZ | When the log row was inserted |

**Indexes**: B-tree on `workflow_id`, `workflow_name`, `status`, `created_at`, `finished_at`. GIN index on `execution_data` for JSONB queries.

## Hooks Reference

The hooks file registers handlers for these n8n lifecycle events:

| Hook | When it fires | What it does |
|------|--------------|--------------|
| `n8n.ready` | Server startup | Verifies PostgreSQL connectivity |
| `workflow.preExecute` | Before a workflow runs | Logs to console |
| `workflow.postExecute` | After a workflow runs | Extracts data and inserts into PostgreSQL |
| `workflow.create` | Workflow created | Logs to console |
| `workflow.update` | Workflow updated | Logs to console |
| `workflow.activate` | Workflow activated | Logs to console |

## Safety

The hooks file includes a safety net: if the `pg` module is not installed or PostgreSQL is unreachable, **n8n will still start normally**. You'll see a warning in the logs:

```
[HOOK] pg module not found — database logging disabled. Install with: npm install pg
```

or

```
[HOOK] PostgreSQL not available — execution logging is disabled
```

n8n continues to function; only the database logging is disabled.

## Project Structure

```
n8n-dashboard-analytics/
├── hooks/
│   └── execution-hooks.js   # n8n lifecycle hooks (main source file)
├── schema.sql                # PostgreSQL table + indexes DDL
├── .env.example              # Environment variable template
├── .env                      # Your local config (gitignored)
├── package.json              # pg dependency
├── docker-compose.yml        # Alternative: run n8n via Docker
├── CLAUDE.md                 # Claude Code guidance
└── README.md
```

## Useful Queries

```sql
-- Recent executions
SELECT execution_id, workflow_name, status, duration_ms, created_at
FROM n8n_execution_logs ORDER BY created_at DESC LIMIT 10;

-- Failed executions
SELECT execution_id, workflow_name, error_message, created_at
FROM n8n_execution_logs WHERE status = 'error' ORDER BY created_at DESC;

-- Execution stats per workflow
SELECT
  workflow_name,
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE status = 'success') as success,
  COUNT(*) FILTER (WHERE status = 'error') as failed,
  ROUND(AVG(duration_ms)) as avg_duration_ms
FROM n8n_execution_logs
GROUP BY workflow_name
ORDER BY total DESC;

-- Find executions by node output
SELECT execution_id, workflow_name
FROM n8n_execution_logs
WHERE execution_data->'nodeOutputs'->>'HTTP Request' IS NOT NULL;
```

## Troubleshooting

### "Cannot find module 'pg'"

The `pg` package is not installed or not in Node's module resolution path. Run `npm install` in the project directory.

### "PostgreSQL connection failed: connection refused"

- Check PostgreSQL is running: `sudo systemctl status postgresql`
- Check it's listening on TCP: `ss -tlnp | grep 5432`
- Verify `pg_hba.conf` allows connections from `127.0.0.1`
- Verify credentials: `psql -h localhost -U n8n -d n8n`

### "relation n8n_execution_logs does not exist"

The schema hasn't been applied. Run:
```bash
psql -h localhost -U n8n -d n8n -f schema.sql
```

### Hooks not loading at all

- Verify `EXTERNAL_HOOK_FILES` is set and points to the **absolute path** of `hooks/execution-hooks.js`
- Check the file is readable: `ls -la hooks/execution-hooks.js`
- Verify the env var is exported: `echo $EXTERNAL_HOOK_FILES`

### n8n starts but no data appears in the database

- Check n8n logs for `[HOOK]` lines — they'll indicate what's happening
- Run a workflow manually and look for `[HOOK] Execution logged to PostgreSQL:`
- If you see `PostgreSQL insert failed`, check the error message for details

## Credits

Built by **[Avanai](https://avanai.io)**

**[Aemal Sayer](https://aemalsayer.com)** - CTO & Co-Founder of Avanai | n8n Ambassador

---

### Need Help with n8n or AI Agents?

If you are looking for experts in building n8n workflows and AI agents for enterprises, contact us at **[Avanai.io](https://avanai.io)**
