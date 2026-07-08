SELECT "workflowId", "versionId" FROM workflow_history WHERE "workflowId" IN ('workflow-1', 'workflow-2', 'workflow-report', 'workflow-dosomething') ORDER BY "createdAt" DESC;
