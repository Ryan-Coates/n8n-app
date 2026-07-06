#!/usr/bin/env bash
set -euo pipefail

# Export all workflows from a running N8n instance to the workflows/ directory.
N8N_URL="${N8N_URL:-http://localhost:5678}"
OUTPUT_DIR="$(dirname "$0")/../workflows"

mkdir -p "$OUTPUT_DIR"

echo "Exporting workflows from $N8N_URL ..."

curl -sf "${N8N_URL}/api/v1/workflows" \
  -H "X-N8N-API-KEY: ${N8N_API_KEY:?N8N_API_KEY env var is required}" \
  | python3 -c "
import json, sys, os

data = json.load(sys.stdin)
workflows = data.get('data', [])

for wf in workflows:
    slug = wf['name'].lower().replace(' ', '-').replace('/', '-')
    out_path = os.path.join('${OUTPUT_DIR}', f'{slug}.json')
    with open(out_path, 'w') as f:
        json.dump(wf, f, indent=2)
    print(f'Exported: {out_path}')

print(f'Done — {len(workflows)} workflow(s) exported.')
"
