#!/bin/sh
set -e

echo "=== N8n Workflow Importer ==="
echo "Waiting for N8n to be ready..."

# Belt-and-suspenders wait — n8n healthcheck should already be satisfied
# via depends_on, but this guards against any race on first schema init.
until wget -qO- http://n8n:5678/healthz > /dev/null 2>&1; do
  echo "  N8n not ready yet, retrying in 3s..."
  sleep 3
done

echo "N8n is ready. Starting workflow import..."
echo ""

imported=0
published=0
failed=0

for f in /workflows/*.json; do
  # Skip the catalog file if present
  case "$f" in
    *catalog*) continue ;;
  esac

  name=$(basename "$f")
  echo "Importing: $name"

  if n8n import:workflow --input="$f" 2>&1; then
    echo "  OK: $name"
    imported=$((imported + 1))

    # Extract the workflow ID from the JSON and publish it so webhooks register
    wf_id=$(node -e "const fs=require('fs');try{const wf=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));if(!wf.id){process.stderr.write('Missing top-level workflow id in '+process.argv[1]+'\n');process.exit(1);}process.stdout.write(wf.id);}catch(err){process.stderr.write('Failed to parse workflow file '+process.argv[1]+': '+err.message+'\n');process.exit(1);}" "$f")
    if [ -n "$wf_id" ]; then
      echo "  Publishing workflow ID: $wf_id"
      if n8n publish:workflow --id="$wf_id" 2>&1; then
        echo "  Published: $wf_id"
        published=$((published + 1))
      else
        echo "  WARN: failed to publish $wf_id"
      fi
    fi
  else
    echo "  WARN: failed to import $name (may already exist or schema not ready)"
    failed=$((failed + 1))
  fi
done

echo ""
echo "=== Import complete: $imported imported, $published published, $failed failed ==="
