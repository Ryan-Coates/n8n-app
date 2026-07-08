SELECT (wf.nodes::jsonb -> 1 ->> 'id') as second_node_id,
       (wf.nodes::jsonb -> 1)::text as second_node_full
FROM workflow_entity wf
WHERE wf.id IN ('workflow-1', 'workflow-2', 'workflow-report', 'workflow-dosomething')
LIMIT 4;
