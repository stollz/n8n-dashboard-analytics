# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Backend infrastructure for the n8n Execution Dashboard. Captures workflow execution data from a Dockerized n8n instance via internal lifecycle hooks and stores it in Supabase (PostgreSQL). The dashboard frontend is a separate project ([n8n-dashboard-analytics-ui](https://github.com/avanaihq/n8n-dashboard-anatlycis-ui)).

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
```

There is no build step, test suite, or linter. The hooks file runs inside the n8n Docker container as plain JavaScript (CommonJS).

## Architecture

```
n8n (Docker :5678) → hooks/execution-hooks.js → Supabase REST API → PostgreSQL
```

- **docker-compose.yml** — Runs `n8nio/n8n:latest`, mounts `./hooks` to `/opt/n8n/hooks`, loads env from `.env`
- **hooks/execution-hooks.js** — The sole source file. Exports an n8n hooks object with handlers for `n8n.ready`, `workflow.preExecute`, `workflow.postExecute`, and `workflow.create/update/activate`. The `postExecute` handler extracts node outputs, calculates duration, and POSTs structured JSON to Supabase via the REST API using `fetch`.
- **schema.sql** — DDL for the `n8n_execution_logs` table in Supabase. Includes B-tree indexes on `workflow_id`, `workflow_name`, `status`, `created_at`, `finished_at` and a GIN index on `execution_data` (JSONB). Has optional RLS policies (commented out).

## Environment Variables

Configured in `.env` (gitignored). Required:

- `SUPABASE_URL` — Supabase project URL
- `SUPABASE_SERVICE_KEY` — Supabase service role key (not anon key)
- `N8N_EXTERNAL_HOOKS=/opt/n8n/hooks/execution-hooks.js` — Tells n8n to load the hooks file

## Key Implementation Details

- The hooks file uses `module.exports` (CommonJS) with the specific structure n8n expects: `{ n8n: { ready: [...] }, workflow: { postExecute: [...], ... } }`. Each hook is an array of async functions.
- `postExecute` receives `(fullRunData, workflowData, executionId)`. Node outputs are at `fullRunData.data.resultData.runData[nodeName][lastIndex].data.main[0][*].json`.
- Supabase insertion uses the REST API directly with `fetch` (no SDK dependency), authenticating via `apikey` header and `Bearer` token.
- The `execution_data` and `workflow_data` columns are JSONB, storing full node outputs and workflow definitions respectively.
