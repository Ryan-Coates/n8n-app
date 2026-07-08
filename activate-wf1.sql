UPDATE workflow_entity SET active = true, "activeVersionId" = '5e713f32-d68b-4b1b-aeaf-b1ce8acebe46' WHERE id = 'workflow-1';

INSERT INTO workflow_published_version ("workflowId", "publishedVersionId") 
VALUES ('workflow-1', '5e713f32-d68b-4b1b-aeaf-b1ce8acebe46')
ON CONFLICT ("workflowId") DO UPDATE SET "publishedVersionId" = EXCLUDED."publishedVersionId";
