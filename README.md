# N8n App

Local N8n deployment with PostgreSQL, workflow version-control, and an automated polling-based deployment service.

## Quick Start

```bash
cp .env.example .env
# Edit .env — set a real N8N_ENCRYPTION_KEY and your GITHUB_TOKEN
docker compose up -d
```

N8n is available at **http://localhost:5678**

## Running Tests

```bash
npm install
npm test
```

## Polling Service

The `polling-service` container runs a cron-style loop that:

1. Polls the GitHub API every `POLL_INTERVAL` seconds (default 300)
2. Compares the latest commit SHA on `main` against the last-known SHA
3. On change: pulls the repo, validates workflow exports, restarts the `n8n` container

Set `GITHUB_TOKEN` in `.env` before starting the stack.

## Importing Workflows into N8n

```bash
# Via the N8n UI: Settings → Import workflow → select a JSON from workflows/
# Or via API (requires an API key set in N8n settings):
curl -X POST http://localhost:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: <key>" \
  -H "Content-Type: application/json" \
  -d @workflows/workflow-1.json
```
