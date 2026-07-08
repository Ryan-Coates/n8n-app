-- Check webhook_entity vs actual nodes
SELECT we."webhookPath", we."method", we.node, we."workflowId",
       (wf.nodes::jsonb -> 0 ->> 'id') as first_node_id,
       (wf.nodes::jsonb ->> 0)::text as first_node_full
FROM webhook_entity we
JOIN workflow_entity wf ON we."workflowId" = wf.id
WHERE we."workflowId" IN ('workflow-1', 'workflow-2', 'workflow-report', 'workflow-dosomething')
LIMIT 4;
