INSERT INTO webhook_entity ("webhookPath", "method", "node", "workflowId")
VALUES ('transform', 'GET', 'webhook-node-1', 'workflow-1')
ON CONFLICT ("webhookPath", "method") DO UPDATE SET 
  "workflowId" = EXCLUDED."workflowId",
  "node" = EXCLUDED."node";
