#!/usr/bin/env bash
set -euo pipefail

# ── deploy.sh ─────────────────────────────────────────────────────────────────
# Server-side deploy script invoked over SSH by the GitHub Actions deploy
# workflow. Pulls the latest main, validates workflow JSON, reimports into
# n8n, and restarts the container if needed.
#
# Assumes this script lives at ~/n8n-app/scripts/deploy.sh on the server and
# the docker-compose stack is running in ~/n8n-app/.
# ─────────────────────────────────────────────────────────────────────────────

REPO_DIR="${DEPLOY_DIR:-$HOME/n8n-app}"
N8N_URL="${N8N_URL:-http://localhost:5678}"
LOG_FILE="${DEPLOY_DIR:-$HOME/n8n-app}/deploy.log"

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG_FILE"
}

# ── 1. Pull latest ────────────────────────────────────────────────────────────
log "=== Deploy started ==="
log "Pulling latest from origin/main ..."
cd "$REPO_DIR"
git fetch origin main
git reset --hard origin/main
log "Now at: $(git rev-parse HEAD)"

# ── 2. Validate workflow JSON ─────────────────────────────────────────────────
log "Validating workflow JSON ..."
errors=0
for f in "${REPO_DIR}/workflows/"*.json; do
  if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
    log "  OK: $(basename "$f")"
  else
    log "  ERROR: invalid JSON — $f"
    errors=$((errors + 1))
  fi
done

if [[ $errors -gt 0 ]]; then
  log "Validation failed with $errors error(s). Aborting deploy."
  exit 1
fi
log "All workflows validated OK."

# ── 3. Reimport workflows into n8n ────────────────────────────────────────────
log "Waiting for n8n to be healthy ..."
attempts=0
until curl -sf "${N8N_URL}/healthz" > /dev/null 2>&1; do
  attempts=$((attempts + 1))
  if [[ $attempts -ge 30 ]]; then
    log "ERROR: n8n did not become healthy within 60s — aborting."
    exit 1
  fi
  sleep 2
done

log "n8n healthy. Importing workflows ..."
container=$(docker ps -qf "name=n8n-app-n8n" 2>/dev/null | head -1)
if [[ -z "$container" ]]; then
  log "ERROR: Could not find running n8n container."
  exit 1
fi

imported=0
for f in "${REPO_DIR}/workflows/"*.json; do
  name=$(basename "$f")
  docker cp "$f" "${container}:/tmp/${name}"
  if docker exec "$container" n8n import:workflow --input="/tmp/${name}" 2>&1 | \
       tee -a "$LOG_FILE" | grep -q "Successfully imported"; then
    log "  Imported: $name"
    imported=$((imported + 1))
  else
    log "  WARN: import may have failed for $name — check logs above"
  fi
done
log "Workflow import complete: $imported file(s) processed."

# ── 4. Restart n8n to pick up changes ────────────────────────────────────────
log "Restarting n8n container ..."
docker restart "$container"
log "n8n restarted (container: $container)."

log "=== Deploy complete ==="
