# Deployment Guide — WireGuard Push Deploy

Deployments are **manual and push-based**: a GitHub Actions workflow connects to
the server through an encrypted WireGuard VPN tunnel and runs a deploy script
over SSH. There is no polling container.

---

## Architecture

```
GitHub Actions runner  (ubuntu-latest)
       │
       │  WireGuard tunnel  UDP 51820  encrypted + preshared key
       │  Endpoint: <SERVER_PUBLIC_IP>:51820
       ▼
  wg-server container  (VPN IP 10.13.13.1)
       │  shared network namespace
       ▼
  deploy-agent container  ← Alpine sshd on port 22
       │  /var/run/docker.sock  +  ./:/repo
       ▼
  scripts/deploy.sh
    ├─ git fetch + reset --hard origin/main
    ├─ validate all workflows/*.json
    ├─ docker cp + n8n import:workflow  (per file)
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
| UDP port `51820` forwarded from router → host | WireGuard endpoint |
| Windows Firewall rule allowing UDP 51820 inbound | See step 6 below |
| Public IP (or DDNS) reachable from GitHub Actions | Set as `WG_SERVER_ENDPOINT` |

### GitHub

- All 9 secrets listed in step 5 added to the repository (or `production` environment).

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
# Full peer config (has WG_CLIENT_PRIVATE_KEY + WG_CLIENT_ADDRESS)
docker exec wg-server cat /config/peer_githubactions/peer_githubactions.conf

# Server public key (WG_SERVER_PUBLIC_KEY)
docker exec wg-server cat /config/server/publickey-server

# Preshared key (WG_PRESHARED_KEY)
docker exec wg-server cat /config/peer_githubactions/presharedkey-peer_githubactions
```

### 4. Generate an SSH key pair for GitHub Actions

> **Important:** always generate SSH keys **inside Docker**, not directly on
> Windows. Windows ssh-keygen can produce keys with CRLF line endings or a
> format that Alpine's OpenSSH rejects with `error in libcrypto: unsupported`.

```bash
docker run --rm alpine sh -c \
  "apk add -q openssh && \
   ssh-keygen -t ed25519 -N '' -q -f /tmp/dk && \
   echo '=== PRIVATE ===' && cat /tmp/dk | base64 -w0 && \
   echo '' && echo '=== PUBLIC ===' && cat /tmp/dk.pub"
```

- The `base64 -w0` output → decode and store as `DEPLOY_SSH_KEY` GitHub secret  
- The public key line → update `AUTHORIZED_KEY` in `docker-compose.yml` under
  the `deploy-agent` service, then run `docker compose up -d deploy-agent`

### 5. Add GitHub Actions secrets

Navigate to **Settings → Secrets and variables → Actions** on the repository:

| Secret | Where to get it |
|---|---|
| `WG_CLIENT_PRIVATE_KEY` | `PrivateKey` line in `peer_githubactions.conf` |
| `WG_CLIENT_ADDRESS` | `Address` line in `peer_githubactions.conf` (e.g. `10.13.13.2/32`) |
| `WG_SERVER_PUBLIC_KEY` | `publickey-server` file |
| `WG_PRESHARED_KEY` | `presharedkey-peer_githubactions` file |
| `WG_SERVER_ENDPOINT` | Your server's public `IP:51820` |
| `WG_ALLOWED_IPS` | `10.13.13.1/32` |
| `DEPLOY_HOST` | `10.13.13.1` |
| `DEPLOY_SSH_USER` | `root` |
| `DEPLOY_SSH_KEY` | The ed25519 private key from step 4 |

### 6. Open UDP 51820 in Windows Firewall

Run in an **elevated (admin) PowerShell**:

```powershell
New-NetFirewallRule -DisplayName "WireGuard VPN" -Direction Inbound `
  -Protocol UDP -LocalPort 51820 -Action Allow
```

### 7. Forward UDP 51820 on your router

Point UDP `51820` on your router/firewall to the host machine's LAN IP
(e.g. `192.168.x.x`). This allows the GitHub Actions runner to reach the
WireGuard endpoint from the internet.

---

## Triggering a Deploy

1. Go to **Actions → Deploy to Server** on GitHub.
2. Click **Run workflow**.
3. Select environment: `production`.
4. Type `deploy` in the confirmation field.
5. Click **Run workflow**.

The action steps:

| Step | What it does |
|---|---|
| Install WireGuard | `apt-get install wireguard` on the Ubuntu runner |
| Configure tunnel | Writes `/etc/wireguard/wg0.conf` from secrets using `printf` |
| Bring up tunnel | `wg-quick up wg0` |
| Verify tunnel | `wg show wg0` + ping (warning only, does not fail the job) |
| Write SSH key | `printf '%s'` into `~/.ssh/deploy_key` (no trailing newline) |
| Run deploy script | `ssh root@10.13.13.1 'DEPLOY_DIR=/repo ... bash /repo/scripts/deploy.sh'` |
| Tear down tunnel | `wg-quick down wg0` — runs even if earlier steps fail |

> **Note on ping:** the Verify tunnel step pings `10.13.13.1` but emits a
> `::warning::` annotation rather than failing if ping returns 100% loss (e.g.
> server is behind symmetric NAT and ICMP is blocked). SSH in the next step is
> the real connectivity gate.

---

## Local Testing (without GitHub Actions)

### Option A — `scripts/test-deploy-local.sh`

Runs the full deploy cycle locally via Docker. Requires the stack to be up.

**On Linux/macOS:**
```bash
bash scripts/test-deploy-local.sh
```

**On Windows (PowerShell)** — run the key steps directly:
```powershell
# Get bridge IP of wg-server
$wgIP = (docker inspect wg-server | ConvertFrom-Json).NetworkSettings.Networks."n8n-app_default".IPAddress

# Generate a temp key and test SSH
$kd = docker run --rm alpine sh -c "apk add -q openssh >/dev/null 2>&1 && ssh-keygen -t ed25519 -N '' -q -f /tmp/dk && cat /tmp/dk | base64 -w0 && echo && cat /tmp/dk.pub"
$pb64 = $kd[0].Trim()
$pub  = $kd[1].Trim()
docker exec deploy-agent sh -c "echo '$pub' >> /root/.ssh/authorized_keys"

# SSH + run deploy.sh
docker run --rm -e "DK_B64=$pb64" --network n8n-app_default alpine sh -c \
  "apk add -q openssh-client >/dev/null 2>&1 && echo `\$DK_B64 | base64 -d > /tmp/dk && chmod 600 /tmp/dk && \
   ssh -i /tmp/dk -o StrictHostKeyChecking=no -o BatchMode=yes root@$wgIP \
   'DEPLOY_DIR=/repo N8N_URL=http://n8n:5678 bash /repo/scripts/deploy.sh'"
```

### Option B — `act` (run the full GitHub Actions YAML locally)

`act` is installed via winget: `winget install nektos.act`

1. Copy `.secrets.example` → `.secrets` and fill in the real values.
2. Run:

```powershell
act workflow_dispatch -W .github/workflows/deploy.yml `
  --input environment=production --input confirm=deploy `
  --secret-file .secrets
```

> The WireGuard steps will still require the server to be reachable on UDP
> 51820. For a fully offline test use Option A above.

---

## What `scripts/deploy.sh` Does

```
git fetch origin main
git reset --hard origin/main
├─ Validate all workflows/*.json (python3 json.load)
├─ Wait for n8n /healthz (up to 60 s)
├─ docker cp <workflow>.json → n8n container /tmp/
├─ docker exec n8n n8n import:workflow --input=/tmp/<workflow>.json
└─ docker restart <n8n container>
```

Logs: `$DEPLOY_DIR/deploy.log` (default `/repo/deploy.log` in the container,
which maps to the repo root on the host).

---

## Rotating Credentials

### Rotate SSH key

1. Generate a new key pair (step 4 above).
2. Update `AUTHORIZED_KEY` in `docker-compose.yml`, run `docker compose up -d deploy-agent`.
3. Update `DEPLOY_SSH_KEY` in GitHub Actions secrets.
4. Commit and push `docker-compose.yml`.

### Rotate WireGuard keys

1. `docker compose down`
2. `docker volume rm n8n-app_wireguard_config`
3. `docker compose up -d` (new keys auto-generated)
4. Re-extract peer config (step 3 above) and update all `WG_*` secrets.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `transfer: 0 B received` in wg show | UDP 51820 not reachable | Open Windows Firewall (step 6) + forward port on router (step 7) |
| Ping `10.13.13.1` fails, action continues | Expected behind NAT | Ignore warning; SSH will confirm connectivity |
| SSH `Permission denied` | Wrong key or authorized_keys stale | Re-run step 4, update compose, restart deploy-agent |
| `Load key: error in libcrypto` | Key generated on Windows | Generate inside Docker (step 4) |
| `set: pipefail: invalid option` | CRLF in shell scripts | `.gitattributes` enforces `eol=lf` — run `git reset --hard HEAD` |
| `n8n did not become healthy` | n8n not running | `docker compose up -d` on server |
| `docker exec` fails in deploy.sh | deploy-agent can't reach n8n by hostname | Ensure deploy-agent shares wireguard's network (`network_mode: "service:wireguard"`) |

---

## Current POC Values

Generated during initial setup. **Rotate all keys before any production use.**

| Item | Value |
|---|---|
| Server public IP | `213.218.200.158` |
| WireGuard server VPN IP | `10.13.13.1` |
| WireGuard client (runner) VPN IP | `10.13.13.2` |
| WireGuard listen port | `51820/UDP` |
| n8n web UI | `http://localhost:5678` |

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
