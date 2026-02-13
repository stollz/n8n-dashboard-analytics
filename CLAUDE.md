# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Backend infrastructure for the n8n Execution Dashboard. Captures workflow execution data from an n8n instance via internal lifecycle hooks and stores it in a local PostgreSQL database using the `pg` (node-postgres) package. The dashboard frontend is a separate project ([n8n-dashboard-analytics-ui](https://github.com/avanaihq/n8n-dashboard-anatlycis-ui)).

## Commands

```bash
# Start n8n container
docker-compose up -d

# Stop n8n container
docker-compose down

# View hook logs (verify hooks are loaded and executions are captured)
docker logs n8n

# Follow logs in real-time
docker logs -f n8n

# Restart after hook changes (hooks are volume-mounted, restart picks up changes)
docker-compose restart n8n

# Run schema against local PostgreSQL
psql -U n8n -d n8n -f schema.sql
```

There is no build step, test suite, or linter. The hooks file runs inside the n8n Docker container as plain JavaScript (CommonJS).

## Architecture

```
n8n (:5678) → hooks/execution-hooks.js → pg.Pool → PostgreSQL (local)
```

- **docker-compose.yml** — Runs `n8nio/n8n:latest`, mounts `./hooks` to `/opt/n8n/hooks`, loads env from `.env`
- **hooks/execution-hooks.js** — The sole source file. Exports an n8n hooks object with handlers for `n8n.ready`, `workflow.preExecute`, `workflow.postExecute`, and `workflow.create/update/activate`. The `postExecute` handler extracts node outputs, calculates duration, and inserts structured data into PostgreSQL via parameterized queries using `pg.Pool`.
- **schema.sql** — DDL for the `n8n_execution_logs` table. Includes B-tree indexes on `workflow_id`, `workflow_name`, `status`, `created_at`, `finished_at` and a GIN index on `execution_data` (JSONB).

## Environment Variables

Configured in `.env` (gitignored). Required:

- `DB_POSTGRESDB_HOST` — PostgreSQL host (default: `localhost`)
- `DB_POSTGRESDB_PORT` — PostgreSQL port (default: `5432`)
- `DB_POSTGRESDB_DATABASE` — Database name (default: `n8n`)
- `DB_POSTGRESDB_USER` — Database user (default: `n8n`)
- `DB_POSTGRESDB_PASSWORD` — Database password
- `EXTERNAL_HOOK_FILES=/opt/n8n/hooks/execution-hooks.js` — Tells n8n to load the hooks file

## Key Implementation Details

- The hooks file uses `module.exports` (CommonJS) with the specific structure n8n expects: `{ n8n: { ready: [...] }, workflow: { postExecute: [...], ... } }`. Each hook is an array of async functions.
- `postExecute` receives `(fullRunData, workflowData, executionId)`. Node outputs are at `fullRunData.data.resultData.runData[nodeName][lastIndex].data.main[0][*].json`.
- PostgreSQL insertion uses `pg.Pool` with parameterized queries (`$1..$13`) and `ON CONFLICT (execution_id) DO NOTHING` for idempotency.
- The `execution_data` and `workflow_data` columns are JSONB, storing full node outputs and workflow definitions respectively. Values are `JSON.stringify()`-ed before insertion.
- The `n8n.ready` hook verifies database connectivity with a `SELECT NOW()` query on startup.
