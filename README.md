# n8n Execution Dashboard - Backend

An enterprise-grade observability solution for n8n workflows. This project captures all workflow executions from a locally-hosted n8n instance and stores them in a Supabase database for real-time monitoring and analytics.

## Overview

This repository contains the backend infrastructure for the n8n Execution Dashboard:

- **Dockerized n8n instance** with custom execution hooks
- **Supabase integration** for persistent storage of execution logs
- **Real-time data capture** of all workflow events (success, failure, duration, etc.)

### Frontend UI

The dashboard frontend is built separately using Replit and can be found here:

**[n8n Dashboard Analytics UI](https://github.com/avanaihq/n8n-dashboard-anatlycis-ui)**

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   n8n Instance  │────▶│  Execution Hooks │────▶│    Supabase     │
│   (Docker)      │     │  (JavaScript)    │     │   (PostgreSQL)  │
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

All this data is automatically sent to your Supabase database for analysis.

## Features

- **Execution Tracking**: Monitor all workflow executions in real-time
- **Error Detection**: Quickly identify failed workflows with error messages
- **Performance Metrics**: Track execution duration and average times
- **Historical Data**: Full execution history stored in Supabase
- **Direct Links**: Jump directly to specific workflows from the dashboard

## Prerequisites

- Docker and Docker Compose
- A [Supabase](https://supabase.com) account (free tier works)
- Node.js (for local development)

## Setup

### 1. Clone the Repository

```bash
git clone git@github.com:avanaihq/n8n-dashboard-analytics.git
cd n8n-dashboard-analytics
```

### 2. Set Up Supabase

1. Create a new Supabase project
2. Go to the SQL Editor in your Supabase dashboard
3. Run the contents of `schema.sql` to create the `n8n_execution_logs` table

### 3. Configure Environment Variables

Create a `.env` file in the project root:

```env
# n8n Configuration
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost:5678/

# Enable external hooks
N8N_EXTERNAL_HOOKS=/opt/n8n/hooks/execution-hooks.js

# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key
```

> **Note**: Use the Supabase **service role key** (not the anon key) for server-side operations.

### 4. Start n8n

```bash
docker-compose up -d
```

n8n will be available at `http://localhost:5678`

### 5. Verify Hook Integration

Check the Docker logs to confirm the hooks are loaded:

```bash
docker logs n8n
```

You should see:
```
[HOOK FILE] execution-hooks.js loaded at: ...
[HOOK] n8n.ready - Server is ready!
[HOOK] Supabase integration enabled
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
n8n-dashboard/
├── docker-compose.yml    # Docker configuration for n8n
├── hooks/
│   └── execution-hooks.js  # n8n lifecycle hooks
├── schema.sql            # Supabase table schema
├── .env                  # Environment variables (create this)
└── README.md
```

## Background

This project was built as part of a technical demonstration on enterprise-grade n8n observability. The solution addresses a common question in the n8n community: **How do you monitor and track all your workflow executions at scale?**

### Key Concepts Demonstrated

- **n8n Hooks**: Internal lifecycle events that n8n fires (not to be confused with webhooks)
- **Supabase Integration**: Using PostgreSQL for persistent, queryable execution logs
- **Real-time Observability**: Capturing execution data as it happens
- **Enterprise Patterns**: Scalable architecture for production n8n deployments

## Related Resources

- [n8n Documentation](https://docs.n8n.io/)
- [Supabase Documentation](https://supabase.com/docs)
- [Dashboard Frontend Repository](https://github.com/avanaihq/n8n-dashboard-anatlycis-ui)

## Credits

Built by **[Avanai](https://avanai.io)**

**[Aemal Sayer](https://aemalsayer.com)** - CTO & Co-Founder of Avanai | n8n Ambassador

---

### Need Help with n8n or AI Agents?

If you are looking for experts in building n8n workflows and AI agents for enterprises, contact us at **[Avanai.io](https://avanai.io)**
