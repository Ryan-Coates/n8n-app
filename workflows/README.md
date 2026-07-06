# N8n Workflow Exports

This directory contains exported N8n workflow definitions (JSON format) — these are the source of truth for what runs in the engine.

## Files

| File | Description |
|------|-------------|
| `workflow-1.json` | Data Transform Trigger — HTTP POST `/webhook/transform` |
| `workflow-2.json` | File Processing Trigger — HTTP POST `/webhook/process-file` |

## Importing via N8n UI

**Settings → Import workflow → select a JSON file**

## Importing via API

```bash
# Requires N8N_API_KEY (set in N8n Settings → API)
curl -X POST http://localhost:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: <key>" \
  -H "Content-Type: application/json" \
  -d @workflow-1.json
```
