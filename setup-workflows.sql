-- Set active versions for workflows
UPDATE workflow_entity SET "activeVersionId" = 'd360292c-b458-45cc-9766-35ddb6417da6' WHERE id = 'workflow-1';
UPDATE workflow_entity SET "activeVersionId" = '4877b016-1ab3-4cf2-a71d-154d1e61397d' WHERE id = 'workflow-2';
UPDATE workflow_entity SET "activeVersionId" = 'a6e6cdc8-6cbf-4691-83fc-e4d1f2f5693a' WHERE id = 'workflow-report';
UPDATE workflow_entity SET "activeVersionId" = '19609ecc-f743-4378-903e-97a9569ac75f' WHERE id = 'workflow-dosomething';

-- Publish workflows
INSERT INTO workflow_published_version ("workflowId", "publishedVersionId") VALUES
  ('workflow-1', 'd360292c-b458-45cc-9766-35ddb6417da6'),
  ('workflow-2', '4877b016-1ab3-4cf2-a71d-154d1e61397d'),
  ('workflow-report', 'a6e6cdc8-6cbf-4691-83fc-e4d1f2f5693a'),
  ('workflow-dosomething', '19609ecc-f743-4378-903e-97a9569ac75f');

-- Register webhooks
INSERT INTO webhook_entity ("webhookPath", "method", "node", "workflowId") VALUES
  ('transform', 'GET', 'webhook-node-1', 'workflow-1'),
  ('process-file', 'GET', 'webhook-node-2', 'workflow-2'),
  ('sales-report', 'GET', 'webhook-node-report', 'workflow-report'),
  ('dosomething', 'GET', 'webhook-node-dosomething', 'workflow-dosomething');
