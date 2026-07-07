#!/usr/bin/env bash
# ── scripts/test-deploy-local.sh ─────────────────────────────────────────────
# Simulates the GitHub Actions deploy workflow locally:
#   1. Verifies WireGuard server + deploy-agent are running
#   2. SSHes into deploy-agent via the Docker bridge IP (same as over the tunnel)
#   3. Runs deploy.sh end-to-end
#
# Usage:
#   bash scripts/test-deploy-local.sh
#
# Requires: docker, the stack running (docker compose up -d)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

echo "=== Local deploy test (mirrors GitHub Actions workflow) ==="

# ── 1. Check wg-server is running ─────────────────────────────────────────
if docker inspect wg-server --format "{{.State.Status}}" 2>/dev/null | grep -q running; then
  ok "wg-server is running"
else
  fail "wg-server not running — run: docker compose up -d wireguard"
fi

# ── 2. Check deploy-agent is running ──────────────────────────────────────
if docker inspect deploy-agent --format "{{.State.Status}}" 2>/dev/null | grep -q running; then
  ok "deploy-agent is running"
else
  fail "deploy-agent not running — run: docker compose up -d"
fi

# ── 3. Verify sshd + authorized_keys ──────────────────────────────────────
AUTHKEYS=$(docker exec deploy-agent cat /root/.ssh/authorized_keys 2>/dev/null || echo "")
if [[ -n "$AUTHKEYS" ]]; then
  ok "authorized_keys populated: ${AUTHKEYS:0:40}..."
else
  fail "authorized_keys is empty in deploy-agent"
fi

# ── 4. Get the WireGuard container bridge IP ──────────────────────────────
WG_BRIDGE_IP=$(docker inspect wg-server \
  --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
  | head -1)

if [[ -z "$WG_BRIDGE_IP" ]]; then
  fail "Could not determine wg-server bridge IP"
fi
ok "wg-server bridge IP: ${WG_BRIDGE_IP}"

# ── 5. Generate a throw-away key, inject it, and test SSH ─────────────────
echo "Generating temporary test SSH key..."
TMPKEY=$(docker run --rm alpine sh -c \
  "apk add -q openssh >/dev/null 2>&1 && \
   ssh-keygen -t ed25519 -N '' -q -f /tmp/dk && \
   cat /tmp/dk | base64 -w0 && echo '' && cat /tmp/dk.pub")

PRIV_B64=$(echo "$TMPKEY" | head -1)
PUB_KEY=$(echo "$TMPKEY" | tail -1)

# Inject temp public key
docker exec deploy-agent sh -c \
  "echo '${PUB_KEY}' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
ok "Temporary public key injected"

# SSH test
echo "Testing SSH connectivity..."
SSH_RESULT=$(docker run --rm \
  -e "DK_B64=${PRIV_B64}" \
  --network n8n-app_default \
  alpine sh -c \
  "apk add -q openssh-client >/dev/null 2>&1 && \
   echo \$DK_B64 | base64 -d > /tmp/dk && chmod 600 /tmp/dk && \
   ssh -i /tmp/dk \
     -o StrictHostKeyChecking=no \
     -o BatchMode=yes \
     -o ConnectTimeout=5 \
     root@${WG_BRIDGE_IP} 'echo SSH_OK'" 2>&1 || echo "SSH_FAILED")

# Remove temp key
docker exec deploy-agent sh -c \
  "grep -v '${PUB_KEY:10:30}' /root/.ssh/authorized_keys > /tmp/ak && \
   mv /tmp/ak /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" 2>/dev/null || true

if echo "$SSH_RESULT" | grep -q "SSH_OK"; then
  ok "SSH connection successful"
else
  fail "SSH failed: ${SSH_RESULT}"
fi

# ── 6. Run deploy.sh via SSH ───────────────────────────────────────────────
echo ""
echo "=== Running deploy.sh (mirrors GitHub Actions step) ==="

docker run --rm \
  -e "DK_B64=${PRIV_B64}" \
  --network n8n-app_default \
  alpine sh -c \
  "apk add -q openssh-client >/dev/null 2>&1 && \
   echo \$DK_B64 | base64 -d > /tmp/dk && chmod 600 /tmp/dk && \
   ssh -i /tmp/dk \
     -o StrictHostKeyChecking=no \
     -o BatchMode=yes \
     -o ConnectTimeout=10 \
     root@${WG_BRIDGE_IP} \
     'DEPLOY_DIR=/repo N8N_URL=http://n8n:5678 bash /repo/scripts/deploy.sh'" || true

echo ""
ok "Local deploy test complete."
echo ""
echo "To run the actual GitHub Actions workflow:"
echo "  act workflow_dispatch -W .github/workflows/deploy.yml \\"
echo "    --input environment=production --input confirm=deploy \\"
echo "    --secret-file .secrets"
