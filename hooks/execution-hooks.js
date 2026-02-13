console.log("[HOOK FILE] execution-hooks.js loaded at:", new Date().toISOString());

// PostgreSQL configuration using pg (node-postgres)
let pool = null;
try {
  const { Pool } = require('pg');
  pool = new Pool({
    host: process.env.DB_POSTGRESDB_HOST || 'localhost',
    port: parseInt(process.env.DB_POSTGRESDB_PORT || '5432', 10),
    database: process.env.DB_POSTGRESDB_DATABASE || 'n8n',
    user: process.env.DB_POSTGRESDB_USER || 'n8n',
    password: process.env.DB_POSTGRESDB_PASSWORD,
    max: 5,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  });
} catch (error) {
  console.error("[HOOK] pg module not found — database logging disabled. Install with: npm install pg");
}

// Helper function to insert execution log into PostgreSQL
async function logToPostgres(data) {
  if (!pool) {
    return;
  }

  const query = `
    INSERT INTO n8n_execution_logs (
      execution_id, workflow_id, workflow_name, status, finished,
      started_at, finished_at, duration_ms, mode, node_count,
      error_message, execution_data, workflow_data
    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
    ON CONFLICT (execution_id) DO NOTHING
  `;

  const values = [
    data.execution_id,
    data.workflow_id,
    data.workflow_name,
    data.status,
    data.finished,
    data.started_at,
    data.finished_at,
    data.duration_ms,
    data.mode,
    data.node_count,
    data.error_message,
    JSON.stringify(data.execution_data),
    JSON.stringify(data.workflow_data),
  ];

  try {
    await pool.query(query, values);
    console.log("[HOOK] Execution logged to PostgreSQL:", data.execution_id);
  } catch (error) {
    console.error("[HOOK] PostgreSQL insert failed:", error.message);
  }
}

module.exports = {
  n8n: {
    ready: [
      async function () {
        console.log("[HOOK] n8n.ready - Server is ready!");
        if (!pool) {
          console.warn("[HOOK] PostgreSQL not available — execution logging is disabled");
          return;
        }
        try {
          const result = await pool.query('SELECT NOW()');
          console.log("[HOOK] PostgreSQL connection verified at:", result.rows[0].now);
        } catch (error) {
          console.error("[HOOK] PostgreSQL connection failed:", error.message);
        }
      },
    ],
  },
  workflow: {
    activate: [
      async function (updatedWorkflow) {
        console.log("[HOOK] workflow.activate:", updatedWorkflow?.id || updatedWorkflow?.name);
      },
    ],
    create: [
      async function (createdWorkflow) {
        console.log("[HOOK] workflow.create:", createdWorkflow?.id || createdWorkflow?.name);
      },
    ],
    update: [
      async function (updatedWorkflow) {
        console.log("[HOOK] workflow.update:", updatedWorkflow?.id || updatedWorkflow?.name);
      },
    ],
    preExecute: [
      async function (workflow, mode) {
        console.log("[HOOK] workflow.preExecute:", workflow?.name, "mode:", mode);
      },
    ],
    postExecute: [
      async function (fullRunData, workflowData, executionId) {
        // Get the execution results from all nodes
        const resultData = fullRunData?.data?.resultData?.runData || {};

        // Extract output from each node
        const nodeOutputs = {};
        for (const [nodeName, nodeRuns] of Object.entries(resultData)) {
          const lastRun = nodeRuns[nodeRuns.length - 1];
          if (lastRun?.data?.main?.[0]) {
            nodeOutputs[nodeName] = lastRun.data.main[0].map((item) => item.json);
          }
        }

        // Calculate duration
        const startedAt = fullRunData?.startedAt;
        const stoppedAt = fullRunData?.stoppedAt;
        const durationMs =
          startedAt && stoppedAt
            ? new Date(stoppedAt).getTime() - new Date(startedAt).getTime()
            : null;

        // Prepare log data
        const logData = {
          execution_id: executionId,
          workflow_id: workflowData?.id,
          workflow_name: workflowData?.name,
          status: fullRunData?.status || (fullRunData?.finished ? "success" : "error"),
          finished: fullRunData?.finished || false,
          started_at: startedAt,
          finished_at: stoppedAt,
          duration_ms: durationMs,
          mode: fullRunData?.mode,
          node_count: Object.keys(resultData).length,
          error_message: fullRunData?.data?.resultData?.error?.message || null,
          execution_data: {
            nodeOutputs,
            lastNodeExecuted: fullRunData?.data?.resultData?.lastNodeExecuted,
            runData: resultData,
          },
          workflow_data: {
            id: workflowData?.id,
            name: workflowData?.name,
            nodes: workflowData?.nodes,
            connections: workflowData?.connections,
            settings: workflowData?.settings,
          },
        };

        // Log to console
        console.log(
          "[HOOK] workflow.postExecute:",
          JSON.stringify(
            {
              executionId,
              workflowName: workflowData?.name,
              finished: fullRunData?.finished,
              status: fullRunData?.status,
              durationMs,
              nodeCount: logData.node_count,
            },
            null,
            2
          )
        );

        // Send to PostgreSQL
        await logToPostgres(logData);
      },
    ],
  },
};
