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
  else
    echo "  WARN: failed to import $name (may already exist or schema not ready)"
    failed=$((failed + 1))
  fi
done

echo ""
echo "=== Import complete: $imported imported, $failed failed ==="
