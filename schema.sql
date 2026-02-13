-- ============================================
-- n8n Execution Logs Schema for PostgreSQL
-- ============================================
-- Run this against your local PostgreSQL database:
--   psql -U n8n -d n8n -f schema.sql

-- Table: n8n_execution_logs
-- Stores all workflow execution logs with metadata and detailed JSON data

CREATE TABLE IF NOT EXISTS n8n_execution_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Core execution info
  execution_id TEXT NOT NULL,
  workflow_id TEXT NOT NULL,
  workflow_name TEXT NOT NULL,

  -- Execution status
  status TEXT NOT NULL CHECK (status IN ('success', 'error', 'running', 'waiting', 'canceled')),
  finished BOOLEAN DEFAULT false,

  -- Timing
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ,
  duration_ms INTEGER,

  -- Execution mode (manual, trigger, webhook, etc.)
  mode TEXT,

  -- Summary metadata (quick lookups)
  node_count INTEGER,
  error_message TEXT,

  -- Detailed execution data (JSONB for flexibility)
  execution_data JSONB,  -- Full run data, node outputs, etc.
  workflow_data JSONB,   -- Workflow definition/structure

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Unique constraint on execution_id
  CONSTRAINT unique_execution UNIQUE (execution_id)
);

-- ============================================
-- Indexes for performance
-- ============================================

CREATE INDEX IF NOT EXISTS idx_execution_logs_workflow_id ON n8n_execution_logs(workflow_id);
CREATE INDEX IF NOT EXISTS idx_execution_logs_workflow_name ON n8n_execution_logs(workflow_name);
CREATE INDEX IF NOT EXISTS idx_execution_logs_status ON n8n_execution_logs(status);
CREATE INDEX IF NOT EXISTS idx_execution_logs_created_at ON n8n_execution_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_execution_logs_finished_at ON n8n_execution_logs(finished_at DESC);

-- GIN index for JSONB queries
CREATE INDEX IF NOT EXISTS idx_execution_logs_execution_data ON n8n_execution_logs USING GIN (execution_data);

-- ============================================
-- Useful queries
-- ============================================

-- Get recent executions
-- SELECT * FROM n8n_execution_logs ORDER BY created_at DESC LIMIT 10;

-- Get failed executions
-- SELECT * FROM n8n_execution_logs WHERE status = 'error' ORDER BY created_at DESC;

-- Get executions for a specific workflow
-- SELECT * FROM n8n_execution_logs WHERE workflow_name = 'My workflow' ORDER BY created_at DESC;

-- Get execution statistics by workflow
-- SELECT
--   workflow_name,
--   COUNT(*) as total_executions,
--   COUNT(*) FILTER (WHERE status = 'success') as successful,
--   COUNT(*) FILTER (WHERE status = 'error') as failed,
--   AVG(duration_ms) as avg_duration_ms
-- FROM n8n_execution_logs
-- GROUP BY workflow_name;

-- Query JSONB data (example: find executions with specific node output)
-- SELECT * FROM n8n_execution_logs
-- WHERE execution_data->'nodeOutputs'->>'NodeName' IS NOT NULL;
