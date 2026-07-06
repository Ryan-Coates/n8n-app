#!/usr/bin/env bash
set -euo pipefail

WORKFLOWS_DIR="$(dirname "$0")/../workflows"
errors=0

for f in "$WORKFLOWS_DIR"/*.json; do
  if python3 -c "import json, sys; json.load(open('$f'))" 2>/dev/null; then
    echo "OK: $f"
  else
    echo "FAIL: $f"
    ((errors++))
  fi
done

if [[ $errors -eq 0 ]]; then
  echo "All workflows valid."
else
  echo "$errors workflow(s) failed validation." >&2
  exit 1
fi
