# n8n Execution Dashboard - Backend

An enterprise-grade observability solution for n8n workflows. This project captures all workflow executions from a locally-hosted n8n instance and stores them in a local PostgreSQL database for real-time monitoring and analytics.

## Overview

This repository contains the backend infrastructure for the n8n Execution Dashboard:

- **n8n instance** with custom execution hooks
- **Local PostgreSQL** for persistent storage of execution logs
- **Real-time data capture** of all workflow events (success, failure, duration, etc.)

### Frontend UI

The dashboard frontend is built separately using Replit and can be found here:

**[n8n Dashboard Analytics UI](https://github.com/avanaihq/n8n-dashboard-anatlycis-ui)**

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   n8n Instance  │────▶│  Execution Hooks │────▶│   PostgreSQL    │
│                 │     │  (JavaScript)    │     │   (Local)       │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                                                          ▼
                                                 ┌─────────────────┐
                                                 │  Dashboard UI   │
                                                 │   (Replit)      │
                                                 └─────────────────┘
```

## How It Works

This project uses **n8n Hooks** - a powerful feature that allows you to intercept workflow events. Unlike webhooks, these are internal lifecycle hooks that n8n calls automatically:

1. **`workflow.postExecute`** - Triggered after every workflow execution
2. **`workflow.preExecute`** - Triggered before workflow execution
3. **`workflow.create/update/activate`** - Triggered on workflow changes
4. **`n8n.ready`** - Triggered when the n8n server starts

When a workflow executes, the hook captures:
- Execution ID and status (success/error)
- Workflow metadata (ID, name)
- Timing information (start, end, duration)
- Node outputs and execution data
- Error messages (if any)

All this data is automatically inserted into your local PostgreSQL database for analysis.

## Features

- **Execution Tracking**: Monitor all workflow executions in real-time
- **Error Detection**: Quickly identify failed workflows with error messages
- **Performance Metrics**: Track execution duration and average times
- **Historical Data**: Full execution history stored in PostgreSQL
- **Direct Links**: Jump directly to specific workflows from the dashboard

## Prerequisites

- A running n8n instance with the `pg` npm package available
- PostgreSQL database (local)

## Setup

### 1. Clone the Repository

```bash
git clone git@github.com:avanaihq/n8n-dashboard-analytics.git
cd n8n-dashboard-analytics
```

### 2. Set Up PostgreSQL

Run the schema against your local PostgreSQL database:

```bash
psql -U n8n -d n8n -f schema.sql
```

### 3. Configure Environment Variables

Create a `.env` file in the project root (see `.env.example`):

```env
# n8n Configuration
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost:5678/

# Enable external hooks
N8N_EXTERNAL_HOOKS=/opt/n8n/hooks/execution-hooks.js

# PostgreSQL Configuration
DB_POSTGRESDB_HOST=localhost
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=your-password-here
```

### 4. Start n8n

Start your n8n instance with the hooks file loaded. Ensure the `N8N_EXTERNAL_HOOKS` env var points to the hooks file.

n8n will be available at `http://localhost:5678`

### 5. Verify Hook Integration

Check the n8n logs to confirm the hooks are loaded. You should see:
```
[HOOK FILE] execution-hooks.js loaded at: ...
[HOOK] n8n.ready - Server is ready!
[HOOK] PostgreSQL connection verified at: ...
```

## Database Schema

The `n8n_execution_logs` table captures:

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `execution_id` | TEXT | n8n execution ID |
| `workflow_id` | TEXT | Workflow ID |
| `workflow_name` | TEXT | Workflow name |
| `status` | TEXT | success, error, running, waiting, canceled |
| `finished` | BOOLEAN | Execution completed |
| `started_at` | TIMESTAMPTZ | Start timestamp |
| `finished_at` | TIMESTAMPTZ | End timestamp |
| `duration_ms` | INTEGER | Execution duration in milliseconds |
| `mode` | TEXT | manual, trigger, webhook, etc. |
| `node_count` | INTEGER | Number of nodes executed |
| `error_message` | TEXT | Error details (if failed) |
| `execution_data` | JSONB | Full execution data and node outputs |
| `workflow_data` | JSONB | Workflow definition |

## Project Structure

```
n8n-dashboard-analytics/
├── docker-compose.yml       # Docker configuration for n8n
├── hooks/
│   └── execution-hooks.js   # n8n lifecycle hooks
├── schema.sql               # PostgreSQL table schema
├── .env.example              # Environment variable template
├── .env                      # Environment variables (create this)
└── README.md
```

## Background

This project was built as part of a technical demonstration on enterprise-grade n8n observability. The solution addresses a common question in the n8n community: **How do you monitor and track all your workflow executions at scale?**

### Key Concepts Demonstrated

- **n8n Hooks**: Internal lifecycle events that n8n fires (not to be confused with webhooks)
- **PostgreSQL Integration**: Using a local PostgreSQL database for persistent, queryable execution logs
- **Real-time Observability**: Capturing execution data as it happens
- **Enterprise Patterns**: Scalable architecture for production n8n deployments

## Related Resources

- [n8n Documentation](https://docs.n8n.io/)
- [node-postgres (pg) Documentation](https://node-postgres.com/)
- [Dashboard Frontend Repository](https://github.com/avanaihq/n8n-dashboard-anatlycis-ui)

## Credits

Built by **[Avanai](https://avanai.io)**

**[Aemal Sayer](https://aemalsayer.com)** - CTO & Co-Founder of Avanai | n8n Ambassador

---

### Need Help with n8n or AI Agents?

If you are looking for experts in building n8n workflows and AI agents for enterprises, contact us at **[Avanai.io](https://avanai.io)**
