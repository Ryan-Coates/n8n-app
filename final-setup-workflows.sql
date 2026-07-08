-- Set active versions for workflows with latest imports
UPDATE workflow_entity SET "activeVersionId" = 'ddde03b6-9099-453a-b1e3-eba8529745f0' WHERE id = 'workflow-1';
UPDATE workflow_entity SET "activeVersionId" = '23d0a3a9-8719-46ea-9cc8-13b70496c2b6' WHERE id = 'workflow-2';
UPDATE workflow_entity SET "activeVersionId" = '573e26b5-1bfc-4bcf-adba-937ed6a7583d' WHERE id = 'workflow-report';
UPDATE workflow_entity SET "activeVersionId" = '14f8d236-f5de-45ca-a456-80e2b27173c0' WHERE id = 'workflow-dosomething';

-- Set active flag
UPDATE workflow_entity SET active = true WHERE id IN ('workflow-1', 'workflow-2', 'workflow-report', 'workflow-dosomething');

-- Publish workflows
INSERT INTO workflow_published_version ("workflowId", "publishedVersionId") VALUES
  ('workflow-1', 'ddde03b6-9099-453a-b1e3-eba8529745f0'),
  ('workflow-2', '23d0a3a9-8719-46ea-9cc8-13b70496c2b6'),
  ('workflow-report', '573e26b5-1bfc-4bcf-adba-937ed6a7583d'),
  ('workflow-dosomething', '14f8d236-f5de-45ca-a456-80e2b27173c0')
ON CONFLICT ("workflowId") DO UPDATE SET "publishedVersionId" = EXCLUDED."publishedVersionId";

-- Register webhooks
INSERT INTO webhook_entity ("webhookPath", "method", "node", "workflowId") VALUES
  ('transform', 'GET', 'webhook-node-1', 'workflow-1'),
  ('process-file', 'GET', 'webhook-node-2', 'workflow-2'),
  ('sales-report', 'GET', 'webhook-node-report', 'workflow-report'),
  ('dosomething', 'GET', 'webhook-node-dosomething', 'workflow-dosomething')
ON CONFLICT ("webhookPath", "method") DO UPDATE SET "workflowId" = EXCLUDED."workflowId";
