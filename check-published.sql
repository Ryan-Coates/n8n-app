SELECT w.id, w.name, w.active, w."activeVersionId", pwv."publishedVersionId" FROM workflow_entity w 
LEFT JOIN workflow_published_version pwv ON w.id = pwv."workflowId"
WHERE w.id IN ('workflow-1', 'workflow-2', 'workflow-report', 'workflow-dosomething');
