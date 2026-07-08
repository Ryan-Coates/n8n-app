DELETE FROM webhook_entity WHERE workflowId IN ('workflow-1', 'workflow-2', 'workflow-report', 'workflow-dosomething');
INSERT INTO webhook_entity ("webhookPath", "method", "node", "workflowId") 
VALUES 
  ('transform', 'GET', 'webhook-node-1', 'workflow-1'),
  ('process-file', 'GET', 'webhook-node-2', 'workflow-2'),
  ('sales-report', 'GET', 'webhook-node-report', 'workflow-report'),
  ('dosomething', 'GET', 'webhook-node-dosomething', 'workflow-dosomething');
