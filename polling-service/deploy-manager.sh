#!/usr/bin/env bash
set -euo pipefail

# ── deploy-manager.sh ─────────────────────────────────────────────────────────
# Polls GitHub for changes to the main branch of n8n-app and manages local
# N8n deployment: pull → validate → restart on change.
# ─────────────────────────────────────────────────────────────────────────────

# ── Configuration ─────────────────────────────────────────────────────────────
GITHUB_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN env var is required}"
GITHUB_OWNER="${GITHUB_OWNER:-Ryan-Coates}"
GITHUB_REPO="${GITHUB_REPO:-n8n-app}"
N8N_URL="${N8N_URL:-http://n8n:5678}"
POLL_INTERVAL="${POLL_INTERVAL:-300}"
STATE_FILE="/tmp/last_known_sha"
LOG_FILE="/var/log/deploy-manager.log"
REPO_DIR="${REPO_DIR:-/repo}"

# ── Logging ───────────────────────────────────────────────────────────────────
log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" | tee -a "$LOG_FILE"
}

# ── GitHub API ────────────────────────────────────────────────────────────────
get_latest_sha() {
  curl -sf \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/commits/main" \
    | grep '"sha"' | head -1 | awk -F'"' '{print $4}'
}

# ── Deployment steps ──────────────────────────────────────────────────────────
pull_latest() {
  log "Pulling latest from origin/main ..."
  cd "$REPO_DIR"
  git fetch origin main
  git reset --hard origin/main
}

validate_workflows() {
  log "Validating workflow JSON exports ..."
  local errors=0
  for f in "${REPO_DIR}/workflows/"*.json; do
    if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
      log "  OK: $f"
    else
      log "  ERROR: invalid JSON — $f"
      ((errors++))
    fi
  done
  if [[ $errors -gt 0 ]]; then
    log "Validation failed with $errors error(s). Aborting deploy."
    return 1
  fi
  log "All workflows validated OK."
}

restart_n8n() {
  log "Restarting N8n ..."
  if command -v docker &>/dev/null; then
    # Locate the n8n container by name pattern (works without compose plugin)
    local container
    container=$(docker ps -qf "name=n8n-app-n8n" 2>/dev/null | head -1)
    if [[ -n "$container" ]]; then
      docker restart "$container" \
        && log "N8n restarted successfully (container: $container)." \
        || log "WARNING: N8n restart failed — check Docker logs."
    else
      log "WARNING: Could not find running n8n container to restart."
    fi
  else
    log "WARNING: docker CLI not available; skipping restart."
  fi
}

deploy() {
  local sha="$1"
  log "=== Deploy triggered for SHA: ${sha} ==="
  pull_latest
  if validate_workflows; then
    restart_n8n
    echo "$sha" > "$STATE_FILE"
    log "=== Deploy complete for SHA: ${sha} ==="
  else
    log "=== Deploy aborted for SHA: ${sha} ==="
  fi
}

# ── Main polling loop ─────────────────────────────────────────────────────────
log "Deploy manager started. Owner=${GITHUB_OWNER} Repo=${GITHUB_REPO} Interval=${POLL_INTERVAL}s"

while true; do
  LATEST_SHA=$(get_latest_sha 2>/dev/null || echo "")

  if [[ -z "$LATEST_SHA" ]]; then
    log "WARNING: Could not fetch latest SHA (network or token issue). Retrying in ${POLL_INTERVAL}s ..."
  else
    LAST_KNOWN=""
    [[ -f "$STATE_FILE" ]] && LAST_KNOWN=$(cat "$STATE_FILE")

    if [[ "$LATEST_SHA" != "$LAST_KNOWN" ]]; then
      log "Change detected: ${LAST_KNOWN:-none} → ${LATEST_SHA}"
      deploy "$LATEST_SHA"
    else
      log "No changes (SHA: ${LATEST_SHA})"
    fi
  fi

  sleep "$POLL_INTERVAL"
done
