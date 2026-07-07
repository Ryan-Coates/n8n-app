# Deployment Guide — WireGuard Push Deploy

This document describes how the n8n-app stack is deployed. Deployments are
**manual and push-based**: a GitHub Actions workflow connects to the server
through an encrypted WireGuard VPN tunnel and runs a deploy script over SSH.
There is no polling container.

---

## Architecture

```
GitHub Actions runner
       │
       │  WireGuard tunnel (UDP 51820, encrypted)
       │  Endpoint: <SERVER_PUBLIC_IP>:51820
       ▼
  wg-server container (10.13.13.1)
       │  shared network namespace
       ▼
  deploy-agent container  ← sshd on port 22
       │  docker.sock + ./:/repo bind mounts
       ▼
  scripts/deploy.sh
    ├─ git fetch + reset --hard origin/main
    ├─ validate workflow JSON
    ├─ docker cp + n8n import:workflow (per file)
    └─ docker restart n8n
```

The server's SSH port is **never exposed to the internet**. All deploy traffic
travels inside the WireGuard tunnel.

---

## Prerequisites

### Server

| Requirement | Notes |
|---|---|
| Docker Desktop / Docker Engine + Compose v2 | Stack runs in Docker |
| Port `51820/UDP` forwarded to the host | WireGuard endpoint |
| Public IP (or DDNS) reachable from GitHub Actions | Set as `WG_SERVER_ENDPOINT` |

### GitHub

- A GitHub Actions environment named **`production`** on the repository.
- All 9 secrets listed below added to that environment.

---

## First-Time Server Setup

### 1. Clone the repository

```bash
git clone https://github.com/Ryan-Coates/n8n-app.git ~/n8n-app
cd ~/n8n-app
```

### 2. Start the stack

```bash
docker compose up -d
```

On first boot, `linuxserver/wireguard` auto-generates:

- Server private/public key pair
- Peer config for `githubactions` at `10.13.13.2`
- A preshared key

### 3. Extract the generated WireGuard values

```bash
# Peer config (contains WG_CLIENT_PRIVATE_KEY, WG_CLIENT_ADDRESS)
docker exec wg-server cat /config/peer_githubactions/peer_githubactions.conf

# Server public key (WG_SERVER_PUBLIC_KEY)
docker exec wg-server cat /config/server/publickey-server

# Preshared key (WG_PRESHARED_KEY)
docker exec wg-server cat /config/peer_githubactions/presharedkey-peer_githubactions
```

### 4. Generate an SSH key pair for GitHub Actions

Run this **inside Docker** to avoid platform-specific key format issues:

```bash
docker run --rm alpine sh -c \
  "apk add -q openssh && \
   ssh-keygen -t ed25519 -N '' -q -f /tmp/dk && \
   echo '=== PRIVATE ===' && cat /tmp/dk && \
   echo '=== PUBLIC ===' && cat /tmp/dk.pub"
```

- Copy the **private key** → `DEPLOY_SSH_KEY` GitHub secret
- Copy the **public key** → update `AUTHORIZED_KEY` in `docker-compose.yml` under the `deploy-agent` service, then run `docker compose up -d deploy-agent`

### 5. Add GitHub Actions secrets

Navigate to **Settings → Secrets and variables → Actions** on the repository,
then add all secrets to the **`production`** environment:

| Secret | Where to get it |
|---|---|
| `WG_CLIENT_PRIVATE_KEY` | `PrivateKey` field in `peer_githubactions.conf` |
| `WG_CLIENT_ADDRESS` | `Address` field in `peer_githubactions.conf` (e.g. `10.13.13.2/32`) |
| `WG_SERVER_PUBLIC_KEY` | `publickey-server` file |
| `WG_PRESHARED_KEY` | `presharedkey-peer_githubactions` file |
| `WG_SERVER_ENDPOINT` | Your server's public IP and WireGuard port, e.g. `1.2.3.4:51820` |
| `WG_ALLOWED_IPS` | `10.13.13.1/32` (only route traffic to the server VPN IP) |
| `DEPLOY_HOST` | `10.13.13.1` (server's WireGuard VPN IP) |
| `DEPLOY_SSH_USER` | `root` (user inside the deploy-agent container) |
| `DEPLOY_SSH_KEY` | The ed25519 private key generated in step 4 |

### 6. Forward port 51820/UDP on your router

Point UDP port `51820` on your router/firewall to the host machine running
Docker. This allows the GitHub Actions runner to reach the WireGuard endpoint.

---

## Triggering a Deploy

1. Go to **Actions → Deploy to Server** in the GitHub repository.
2. Click **Run workflow**.
3. Select environment: `production`.
4. Type `deploy` in the confirmation field.
5. Click **Run workflow**.

The action will:
1. Install WireGuard on the Ubuntu runner
2. Bring up the VPN tunnel using the secrets above
3. Ping `10.13.13.1` to verify tunnel connectivity
4. SSH to `root@10.13.13.1` via the tunnel
5. Run `DEPLOY_DIR=/repo N8N_URL=http://n8n:5678 bash /repo/scripts/deploy.sh`
6. Tear down the tunnel (`if: always()`)

---

## What `scripts/deploy.sh` Does

```
git fetch origin main
git reset --hard origin/main
├── Validate all workflows/*.json
├── Wait for n8n /healthz to respond
├── docker cp <workflow>.json → n8n container
├── docker exec n8n n8n import:workflow --input=/tmp/<workflow>.json
└── docker restart <n8n container>
```

Logs are written to `$DEPLOY_DIR/deploy.log` on the server.

---

## Rotating Credentials

### Rotate SSH key

1. Generate a new key pair (see step 4 above).
2. Update `AUTHORIZED_KEY` in `docker-compose.yml` and run `docker compose up -d deploy-agent`.
3. Update `DEPLOY_SSH_KEY` in GitHub Actions secrets.
4. Commit and push the updated `docker-compose.yml`.

### Rotate WireGuard keys

1. Stop the stack: `docker compose down`
2. Delete the wireguard config volume: `docker volume rm n8n-app_wireguard_config`
3. Start again: `docker compose up -d`
4. Re-extract the new peer config (step 3 above).
5. Update all `WG_*` secrets in GitHub Actions.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| WireGuard tunnel doesn't come up | Port 51820/UDP not forwarded | Check router port forwarding |
| `ping 10.13.13.1` fails in action | Firewall blocking WireGuard | Ensure UDP 51820 is open inbound |
| SSH permission denied | Wrong key or authorized_keys not updated | Re-run step 4 and update compose |
| `n8n did not become healthy` | n8n not running or unhealthy | Run `docker compose up -d` on server |
| `Load key: error in libcrypto` | Key generated on Windows (CRLF) | Always generate keys inside Docker (Alpine) |

---

## Current POC Values

These values are the ones generated during the initial setup of this POC.
**Rotate all keys before using in production.**

| Item | Value |
|---|---|
| Server public IP | `213.218.200.158` |
| WireGuard server VPN IP | `10.13.13.1` |
| WireGuard client (runner) VPN IP | `10.13.13.2` |
| WireGuard listen port | `51820/UDP` |
| n8n web UI | `http://localhost:5678` |
