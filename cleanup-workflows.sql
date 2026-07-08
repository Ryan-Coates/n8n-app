DELETE FROM workflow_published_version WHERE "workflowId" IN ('workflow-1', 'workflow-2', 'workflow-report', 'workflow-dosomething');
DELETE FROM webhook_entity WHERE "workflowId" IN ('workflow-1', 'workflow-2', 'workflow-report', 'workflow-dosomething');
