#!/usr/bin/env bash
# ── scripts/setup-cloudflare-tunnel.sh ───────────────────────────────────────
# One-stop script for:
#   1. Validating the cloudflared container is running and connected
#   2. Testing SSH connectivity locally (Docker bridge — no CF credentials needed)
#   3. Testing SSH connectivity through the real Cloudflare tunnel
#      (requires CF_ACCESS_CLIENT_ID + CF_ACCESS_CLIENT_SECRET env vars)
#   4. Running a full deploy dry-run through the tunnel
#
# Usage:
#   # Local validation only (no Cloudflare Access creds needed):
#   bash scripts/setup-cloudflare-tunnel.sh --local
#
#   # Full tunnel test:
#   CF_ACCESS_CLIENT_ID=xxx CF_ACCESS_CLIENT_SECRET=yyy \
#     CF_TUNNEL_HOSTNAME=n8n-ssh.example.com \
#     bash scripts/setup-cloudflare-tunnel.sh --tunnel
#
#   # Full deploy dry-run through tunnel:
#   CF_ACCESS_CLIENT_ID=xxx CF_ACCESS_CLIENT_SECRET=yyy \
#     CF_TUNNEL_HOSTNAME=n8n-ssh.example.com \
#     bash scripts/setup-cloudflare-tunnel.sh --deploy
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC}  $*"; }

MODE="${1:---local}"

echo "=== Cloudflare Tunnel Setup Validation (mode: $MODE) ==="
echo ""

# ── 1. Container checks ───────────────────────────────────────────────────────
info "Checking containers..."

CF_STATE=$(docker inspect cf-tunnel --format "{{.State.Status}}" 2>/dev/null || echo "missing")
if [[ "$CF_STATE" == "running" ]]; then
  ok "cf-tunnel container is running"
else
  fail "cf-tunnel not running (state: $CF_STATE) — run: docker compose up -d cloudflared"
fi

DA_STATE=$(docker inspect deploy-agent --format "{{.State.Status}}" 2>/dev/null || echo "missing")
if [[ "$DA_STATE" == "running" ]]; then
  ok "deploy-agent container is running"
else
  fail "deploy-agent not running — run: docker compose up -d"
fi

N8N_HEALTH=$(docker inspect n8n-app-n8n-1 --format "{{.State.Health.Status}}" 2>/dev/null || echo "not found")
if [[ "$N8N_HEALTH" == "healthy" ]]; then
  ok "n8n is healthy"
else
  warn "n8n health: $N8N_HEALTH (deploy will wait for /healthz)"
fi

echo ""

# ── 2. Tunnel connectivity check ──────────────────────────────────────────────
info "Checking cloudflared tunnel status..."
TUNNEL_LOG=$(docker logs cf-tunnel --tail 10 2>&1)
if echo "$TUNNEL_LOG" | grep -q "Registered tunnel connection"; then
  ok "Tunnel is registered and connected to Cloudflare"
elif echo "$TUNNEL_LOG" | grep -q "Running"; then
  ok "Tunnel appears connected"
else
  warn "Could not confirm tunnel registration — recent logs:"
  docker logs cf-tunnel --tail 5 2>&1 | sed 's/^/         /'
fi

echo ""

# ── 3. Authorized keys check ──────────────────────────────────────────────────
info "Checking deploy-agent SSH config..."
AUTHKEYS=$(docker exec deploy-agent cat /root/.ssh/authorized_keys 2>/dev/null || echo "")
if [[ -n "$AUTHKEYS" ]]; then
  ok "authorized_keys: ${AUTHKEYS:0:50}..."
else
  fail "authorized_keys is empty — check AUTHORIZED_KEY in docker-compose.yml"
fi

echo ""

# ── 4. Local SSH test (Docker bridge — no Cloudflare creds needed) ───────────
if [[ "$MODE" == "--local" || "$MODE" == "--tunnel" || "$MODE" == "--deploy" ]]; then
  info "Testing SSH via Docker bridge (local only)..."

  CF_BRIDGE_IP=$(docker inspect cf-tunnel 2>/dev/null \
    | python3 -c "import sys,json; nets=json.load(sys.stdin)[0]['NetworkSettings']['Networks']; print(list(nets.values())[0]['IPAddress'])" 2>/dev/null || echo "")

  if [[ -z "$CF_BRIDGE_IP" ]]; then
    warn "Could not determine cf-tunnel bridge IP — skipping local SSH test"
  else
    info "cf-tunnel bridge IP: $CF_BRIDGE_IP"

    # Generate a temporary test key inside Docker
    TMPKEY=$(docker run --rm alpine sh -c \
      "apk add -q openssh >/dev/null 2>&1 && \
       ssh-keygen -t ed25519 -N '' -q -f /tmp/dk && \
       cat /tmp/dk | base64 -w0 && echo && cat /tmp/dk.pub")
    TMP_B64=$(echo "$TMPKEY" | head -1)
    TMP_PUB=$(echo "$TMPKEY" | tail -1)

    docker exec deploy-agent sh -c "echo '${TMP_PUB}' >> /root/.ssh/authorized_keys"

    SSH_RESULT=$(docker run --rm \
      -e "DK_B64=${TMP_B64}" \
      --network n8n-app_default \
      alpine sh -c \
      "apk add -q openssh-client >/dev/null 2>&1 && \
       echo \$DK_B64 | base64 -d > /tmp/dk && chmod 600 /tmp/dk && \
       ssh -i /tmp/dk -o StrictHostKeyChecking=no -o BatchMode=yes \
           -o ConnectTimeout=5 root@${CF_BRIDGE_IP} 'echo SSH_OK; whoami'" 2>&1 || echo "FAILED")

    # Clean up temp key
    docker exec deploy-agent sh -c \
      "grep -v '${TMP_PUB:10:30}' /root/.ssh/authorized_keys > /tmp/ak && \
       mv /tmp/ak /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" 2>/dev/null || true

    if echo "$SSH_RESULT" | grep -q "SSH_OK"; then
      ok "Local SSH test passed (root@${CF_BRIDGE_IP})"
    else
      fail "Local SSH failed: $SSH_RESULT"
    fi
  fi
fi

echo ""

# ── 5. Tunnel SSH test (via real Cloudflare tunnel) ───────────────────────────
if [[ "$MODE" == "--tunnel" || "$MODE" == "--deploy" ]]; then
  CF_TUNNEL_HOSTNAME="${CF_TUNNEL_HOSTNAME:?CF_TUNNEL_HOSTNAME env var required for --tunnel mode}"
  CF_ACCESS_CLIENT_ID="${CF_ACCESS_CLIENT_ID:?CF_ACCESS_CLIENT_ID env var required}"
  CF_ACCESS_CLIENT_SECRET="${CF_ACCESS_CLIENT_SECRET:?CF_ACCESS_CLIENT_SECRET env var required}"
  DEPLOY_SSH_KEY="${DEPLOY_SSH_KEY:-}"

  info "Testing SSH through Cloudflare tunnel: $CF_TUNNEL_HOSTNAME"

  # cloudflared must be installed locally for this test
  if ! command -v cloudflared &>/dev/null; then
    warn "cloudflared not found locally — install with: winget install cloudflare.cloudflared"
    warn "Skipping tunnel SSH test"
  else
    cloudflared version | head -1

    KEY_FILE=$(mktemp)
    if [[ -n "$DEPLOY_SSH_KEY" ]]; then
      printf '%s' "$DEPLOY_SSH_KEY" > "$KEY_FILE"
      chmod 600 "$KEY_FILE"
    else
      warn "DEPLOY_SSH_KEY not set — tunnel test will use existing ~/.ssh keys"
      rm "$KEY_FILE"
      KEY_FILE=""
    fi

    KEY_OPT=""
    [[ -n "$KEY_FILE" ]] && KEY_OPT="-i $KEY_FILE"

    TUNNEL_RESULT=$(CLOUDFLARE_ACCESS_CLIENT_ID="$CF_ACCESS_CLIENT_ID" \
      CLOUDFLARE_ACCESS_CLIENT_SECRET="$CF_ACCESS_CLIENT_SECRET" \
      ssh -o "ProxyCommand=cloudflared access ssh --hostname $CF_TUNNEL_HOSTNAME" \
          -o StrictHostKeyChecking=no \
          -o BatchMode=yes \
          -o ConnectTimeout=15 \
          $KEY_OPT \
          root@"$CF_TUNNEL_HOSTNAME" \
          'echo TUNNEL_SSH_OK; hostname' 2>&1 || echo "FAILED")

    [[ -n "$KEY_FILE" ]] && rm -f "$KEY_FILE"

    if echo "$TUNNEL_RESULT" | grep -q "TUNNEL_SSH_OK"; then
      ok "Tunnel SSH test PASSED — connected to: $(echo "$TUNNEL_RESULT" | grep -v TUNNEL_SSH_OK | head -1)"
    else
      fail "Tunnel SSH failed:\n$TUNNEL_RESULT"
    fi
  fi

  echo ""
fi

# ── 6. Full deploy through tunnel ─────────────────────────────────────────────
if [[ "$MODE" == "--deploy" ]]; then
  CF_TUNNEL_HOSTNAME="${CF_TUNNEL_HOSTNAME:?required}"
  info "Running full deploy.sh through Cloudflare tunnel..."

  CLOUDFLARE_ACCESS_CLIENT_ID="$CF_ACCESS_CLIENT_ID" \
  CLOUDFLARE_ACCESS_CLIENT_SECRET="$CF_ACCESS_CLIENT_SECRET" \
  ssh -o "ProxyCommand=cloudflared access ssh --hostname $CF_TUNNEL_HOSTNAME" \
      -o StrictHostKeyChecking=no \
      -o BatchMode=yes \
      -o ConnectTimeout=30 \
      root@"$CF_TUNNEL_HOSTNAME" \
      'DEPLOY_DIR=/repo N8N_URL=http://n8n:5678 bash /repo/scripts/deploy.sh' || \
    fail "Deploy script failed"

  echo ""
  ok "Full deploy through Cloudflare tunnel PASSED"
fi

echo ""
echo "=== Validation complete ==="
