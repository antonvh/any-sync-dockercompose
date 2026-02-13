# Portainer Deployment Guide

This guide covers deploying the any-sync stack with Traefik proxy integration and anytype-cli on Portainer.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Docker Compose Deployment](#docker-compose-deployment)
4. [Network Configuration](#network-configuration)
5. [Anytype-CLI Integration](#anytype-cli-integration)
6. [External Access via Traefik](#external-access-via-traefik)
7. [Security for Public VPS](#security-for-public-vps)
8. [n8n Integration](#n8n-integration)
9. [Troubleshooting](#troubleshooting)
10. [Backup and Restore](#backup-and-restore)

---

## Prerequisites

### System Requirements

- **Docker Host**: Running Docker 20.10+ with Docker Compose 2.0+
- **Traefik**: Already running and accessible on the network (external to this stack)
- **Disk Space**: At least 50GB for persistent data (depends on usage)
- **Memory**: Minimum 4GB RAM; 8GB+ recommended for production
- **Connectivity**: All containers must reach the Traefik reverse proxy

### DNS and Firewall

If exposing services externally:

- Point DNS to your **Traefik proxy public IP** (not the Docker host)
- Open required firewall ports for any-sync P2P services **ONLY** (TCP: 1001-1006, UDP: 1011-1016)
- **NEVER expose** MongoDB (27001), Redis (6379), MinIO (9000/9001) - these contain credentials
- Use Traefik as the sole entry point for external access
- Enable firewall with default deny-all policy

### Traefik Configuration

Your external Traefik instance must:

- Support TCP proxying for P2P services
- Have a routable network connection to the Docker host (but not directly expose it)
- Use dynamic config with file provider (hot reload, no restart needed)
- Implement rate limiting for DDoS protection

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   Any-Sync Stack                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────────┐      ┌──────────────────┐   │
│  │  Configuration Gen   │      │  Infrastructure  │   │
│  │  (run once)          │      │  Services        │   │
│  │  - anyconf.sh        │      │  - MongoDB       │   │
│  │  - processing.sh     │      │  - Redis         │   │
│  │  - anytype-cli-init  │      │  - MinIO         │   │
│  └──────────────────────┘      └──────────────────┘   │
│           │                            │               │
│           └────────────┬───────────────┘               │
│                        ▼                               │
│  ┌───────────────────────────────────────────────────┐ │
│  │        Any-Sync Network Services                 │ │
│  ├───────────────────────────────────────────────────┤ │
│  │  - any-sync-coordinator (service registry)       │ │
│  │  - any-sync-node-{1,2,3} (data storage)         │ │
│  │  - any-sync-filenode (file storage)             │ │
│  │  - any-sync-consensusnode (consensus)           │ │
│  │  - anytype-cli (API server)                      │ │
│  │  - netcheck (network diagnostics)                │ │
│  └───────────────────────────────────────────────────┘ │
│           │                                             │
│           └────────────┬────────────────────────────┐  │
└────────────────────────┼────────────────────────────┘  │
                         │                                │
        ┌────────────────┴────────────────┐               │
        │                                 │               │
    ┌───▼──────────────┐      ┌──────────▼────────────┐  │
    │  Internal Network│      │  Traefik Proxy       │  │
    │  (Docker only)   │      │  (External)          │  │
    └──────────────────┘      └──────────────────────┘  │
        │                              │                 │
        └──────────────────┬───────────┘                 │
                           │                             │
                    ┌──────▼────────┐                    │
                    │ n8n Instance   │                   │
                    │ (API Client)   │                   │
                    └────────────────┘                   │
```

### Service Layers

**Internal Services (Docker network only)**:

- MongoDB, Redis, MinIO (infrastructure)
- All any-sync services (P2P networking)
- anytype-cli (HTTP API)

**External Access (via Traefik)**:

- Any-sync P2P services (TCP/QUIC routing)
- Optional metrics and diagnostics endpoints

**Private Integration (n8n)**:

- anytype-cli accessible via internal Docker network
- HTTP REST API on port 31012

---

## Docker Compose Deployment

### Step 1: Deploy via Portainer

1. **Open Portainer Dashboard**
   - Navigate to `https://your-portainer-host:9443`
   - Log in to your Portainer instance

2. **Create a New Stack**
   - Go to **Stacks** > **Add Stack**
   - Choose deployment method:
     - **Paste compose file**: Copy the contents of `docker-compose.yml`
     - **Git**: Link to your repository (recommended for updates)
     - **Upload**: Select the file from your computer

3. **Configure Stack Name**
   - Enter a name (e.g., `any-sync-network`)
   - This will be the prefix for all generated resources

### Step 2: Set Environment Variables

In the Portainer UI, you can configure variables two ways:

**Option A: Environment Variables in Portainer UI**

1. Under "Environment variables", add each variable:
   - `STORAGE_DIR` (default: `./storage`)
   - `EXTERNAL_LISTEN_HOST` (default: `127.0.0.1`)
   - `TRAEFIK_DOMAIN` (e.g., `any-sync.example.com`)
   - Any version overrides (e.g., `ANY_SYNC_NODE_VERSION=prod`)

**Option B: Use .env.override File**

1. Create a `.env.override` file in the stack directory with custom values:

   ```env
   STORAGE_DIR=/data/any-sync-storage
   EXTERNAL_LISTEN_HOST=192.168.1.100
   ANYTYPE_BOT_NAME=my-bot
   ANYTYPE_LOG_LEVEL=DEBUG
   ```

2. The stack will use both `.env.default` (base) and `.env.override` (overrides)

### Step 3: Deploy the Stack

1. Click **Deploy the stack**
2. Monitor progress in the Portainer logs
3. Wait for all services to reach "healthy" status (typically 2-5 minutes)

### Step 4: Verify Deployment

1. **Check Service Health**
   - Go to **Containers**
   - Verify all containers are running with healthy status:
     - ✅ `generateconfig-anyconf`
     - ✅ `generateconfig-processing`
     - ✅ `mongo-1`
     - ✅ `redis`
     - ✅ `minio`
     - ✅ `any-sync-coordinator`
     - ✅ `any-sync-node-1`, `any-sync-node-2`, `any-sync-node-3`
     - ✅ `any-sync-filenode`
     - ✅ `any-sync-consensusnode`
     - ✅ `anytype-cli`
     - ✅ `netcheck`

2. **Check Logs**
   - Select the `anytype-cli` container
   - View logs to get the API key:

     ```
     INFO: [anytype-cli-init] API Key (save this for n8n): eyJ...
     Use this in n8n:
       - Base URL: http://any-type-cli:31012
       - API Key: eyJ...
     ```

---

## Network Configuration

### Internal Docker Network

All services communicate via the default Docker Compose network:

| Service | Internal Address | Port | Purpose |
|---------|------------------|------|---------|
| MongoDB | `mongo-1:27001` | 27001 | Database |
| Redis | `redis:6379` | 6379 | Cache |
| MinIO | `minio:9000` | 9000 | S3 Storage |
| Coordinator | `any-sync-coordinator:1004` | 1004 | Service registry |
| Nodes 1-3 | `any-sync-node-{1,3}:100{1,3}` | 1001-1003 | Data storage |
| FileNode | `any-sync-filenode:1005` | 1005 | File storage |
| ConsensusNode | `any-sync-consensusnode:1006` | 1006 | Consensus |
| anytype-cli | `anytype-cli:31012` | 31012 | API server |

### External Connectivity

#### For Local Development

All internal ports are bound to `127.0.0.1`, accessible only from the Docker host:

```bash
# From the Docker host
curl http://127.0.0.1:31012/api/v1/account.info

# From another machine (not accessible)
curl http://192.168.1.100:31012/api/v1/account.info  # ❌ Connection refused
```

#### For Remote Access

To allow external clients to reach any-sync services, configure Traefik for TCP/QUIC routing (see [External Access via Traefik](#external-access-via-traefik)).

### Multi-IP Configuration

To bind services to multiple network interfaces:

1. Update `.env.override`:

   ```env
   EXTERNAL_LISTEN_HOSTS=192.168.1.100 10.0.0.50
   ```

2. The any-sync services will advertise all IPs to the network

3. Restart the stack:

   ```bash
   docker-compose up -d
   ```

---

## Anytype-CLI Integration

### Initialization Process

On first deployment, the anytype-cli service:

1. **Creates a bot account**
   - Uses the name from `ANYTYPE_BOT_NAME` env var (default: `any-sync-bot`)
   - Network configuration automatically loaded from coordinator

2. **Generates an API key**
   - Named from `ANYTYPE_API_KEY_NAME` env var (default: `n8n-integration`)
   - Stored in Docker volume for persistence

3. **Starts the HTTP API server**
   - Listens on port from `ANYTYPE_API_PORT` env var (default: 31012)
   - Internally only (bound to `127.0.0.1`)

### Retrieving the API Key

After deployment, retrieve the API key from container logs:

**Via Portainer UI**:

1. Go to **Containers**
2. Select `anytype-cli`
3. Click **Logs**
4. Search for "API Key (save this for n8n):"
5. Copy the token value

**Via Docker CLI**:

```bash
docker logs <stack-name>_anytype-cli_1 | grep "API Key"
```

### Manual API Key Reset

If you need to regenerate the API key:

1. Delete the volume: `docker volume rm <stack-name>_anytype-cli-config`
2. Restart the stack: `docker-compose up -d anytype-cli`
3. Retrieve the new key from logs

### Configuration Options

| Env Variable | Default | Description |
|--------------|---------|-------------|
| `ANYTYPE_BOT_NAME` | `any-sync-bot` | Bot account name |
| `ANYTYPE_API_KEY_NAME` | `n8n-integration` | API key identifier |
| `ANYTYPE_API_PORT` | `31012` | HTTP server port |
| `ANYTYPE_LOG_LEVEL` | `ERROR` | Logging level (ERROR, WARN, INFO, DEBUG) |

---

## External Access via Traefik

### Port Exposure Overview

**Required Ports for External Clients**:

| Port Range | Protocol | Service | Notes |
|------------|----------|---------|-------|
| 1001-1003 | TCP | Tree Nodes | Required for P2P network |
| 1011-1013 | UDP | Tree Nodes QUIC | Required for P2P network |
| 1004 | TCP | Coordinator | Bootstrap service |
| 1014 | UDP | Coordinator QUIC | Bootstrap service |
| 1005 | TCP | FileNode | File storage |
| 1015 | UDP | FileNode QUIC | File storage |
| 1006 | TCP | ConsensusNode | Consensus |
| 1016 | UDP | ConsensusNode QUIC | Consensus |

**DO NOT Expose** (contain credentials/sensitive data):

- MongoDB (27001) ❌
- Redis (6379) ❌
- MinIO (9000, 9001) ❌
- anytype-cli (31012 - internal only) ❌

### Traefik Dynamic Configuration (File Provider)

Use dynamic config with file provider for zero-downtime updates (no Traefik restart needed).

**1. Configure Traefik Static Config** (`traefik.yml`):

```yaml
entryPoints:
  tcp-p2p:
    address: ":6000-6100"

providers:
  file:
    filename: /etc/traefik/dynamic.yml
    watch: true          # 🔥 Auto-reload on changes (no restart!)

log:
  level: INFO
```

**2. Create Dynamic Config** (`/etc/traefik/dynamic.yml`):

```yaml
routers:
  coordinator:
    entryPoints: ["tcp-p2p"]
    rule: "HostSNI(`coordinator.example.com`)"
    service: coordinator
    tls:
      passthrough: true

  node-1:
    entryPoints: ["tcp-p2p"]
    rule: "HostSNI(`node-1.example.com`)"
    service: node-1
    tls:
      passthrough: true

  node-2:
    entryPoints: ["tcp-p2p"]
    rule: "HostSNI(`node-2.example.com`)"
    service: node-2
    tls:
      passthrough: true

  node-3:
    entryPoints: ["tcp-p2p"]
    rule: "HostSNI(`node-3.example.com`)"
    service: node-3
    tls:
      passthrough: true

  filenode:
    entryPoints: ["tcp-p2p"]
    rule: "HostSNI(`filenode.example.com`)"
    service: filenode
    tls:
      passthrough: true

  consensusnode:
    entryPoints: ["tcp-p2p"]
    rule: "HostSNI(`consensusnode.example.com`)"
    service: consensusnode
    tls:
      passthrough: true

services:
  coordinator:
    loadBalancer:
      servers:
        - address: "192.168.1.100:1004"  # Docker host IP

  node-1:
    loadBalancer:
      servers:
        - address: "192.168.1.100:1001"

  node-2:
    loadBalancer:
      servers:
        - address: "192.168.1.100:1002"

  node-3:
    loadBalancer:
      servers:
        - address: "192.168.1.100:1003"

  filenode:
    loadBalancer:
      servers:
        - address: "192.168.1.100:1005"

  consensusnode:
    loadBalancer:
      servers:
        - address: "192.168.1.100:1006"
```

**3. Verify Hot-Reload**:

Edit the config and Traefik reloads automatically:

```bash
# No restart needed! Just edit the file:
nano /etc/traefik/dynamic.yml

# Check logs for reload confirmation
docker logs <traefik> | grep -i "dynamic"
```

**Benefits**: ✅ No downtime ✅ Instant updates ✅ Version control friendly

### DNS Configuration

For clients to connect to your any-sync network, configure DNS to point to **Traefik** (not Docker host):

**Wildcard DNS (Recommended)**:

```bash
# In your DNS provider, point to TRAEFIK public IP (not Docker host!)
*.example.com  A  203.0.113.50    # <- Traefik public IP
```

**Individual A Records**:

```bash
coordinator.example.com    A  203.0.113.50    # <- Traefik public IP
node-1.example.com         A  203.0.113.50
node-2.example.com         A  203.0.113.50
node-3.example.com         A  203.0.113.50
filenode.example.com       A  203.0.113.50
consensusnode.example.com  A  203.0.113.50
```

Replace `203.0.113.50` with your actual Traefik proxy's public IP address.

**Important**: DNS records should point to Traefik's public IP, not the Docker host's IP. This adds a critical layer of isolation.

### Firewall Configuration

**These ports MUST be open** (required for any-sync network):

```bash
# TCP P2P ports (1001-1006)
sudo ufw allow 1001:1006/tcp comment "Any-sync TCP"

# UDP QUIC ports (1011-1016)
sudo ufw allow 1011:1016/udp comment "Any-sync QUIC"
```

**NEVER OPEN these ports** (security critical):

```bash
# MongoDB - contains credentials and internal data
# sudo ufw allow 27001  ❌ DO NOT OPEN

# Redis - in-memory cache with sensitive data
# sudo ufw allow 6379   ❌ DO NOT OPEN

# MinIO - direct S3 access, contains credentials
# sudo ufw allow 9000   ❌ DO NOT OPEN
# sudo ufw allow 9001   ❌ DO NOT OPEN
```

---

## Security for Public VPS

When hosting on a public VPS, implement these critical practices:

### Network Isolation (Firewall-First)

```bash
# Start with deny-all policy
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH only from specific IPs
sudo ufw allow from 203.0.113.0/24 to any port 22  # Replace with your admin IP

# Allow Traefik P2P proxy (only this!)
sudo ufw allow 6000:6100/tcp comment "Traefik P2P proxy"

# HTTPS for Traefik dashboard
sudo ufw allow 443/tcp comment "HTTPS"

# Enable firewall
sudo ufw enable

# Verify rules
sudo ufw status numbered
```

### DDoS Protection & Rate Limiting

Add rate limiting in Traefik's `dynamic.yml`:

```yaml
middlewares:
  rate-limit:
    rateLimit:
      average: 100      # 100 requests/sec per IP
      burst: 500        # Allow bursts up to 500
      period: 1s

routers:
  coordinator:
    middlewares:
      - rate-limit
    entryPoints: ["tcp-p2p"]
    rule: "HostSNI(`coordinator.example.com`)"
    service: coordinator
    tls:
      passthrough: true
```

### Credential Management

```bash
# Generate strong MinIO credentials
AWS_ACCESS_KEY_ID=$(openssl rand -base64 32)
AWS_SECRET_ACCESS_KEY=$(openssl rand -base64 32)

# Store in .env.override (never commit!)
grep -q AWS_ACCESS_KEY_ID .env.override || \
  echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> .env.override
```

### TLS/HTTPS (Let's Encrypt)

```yaml
# traefik.yml
certificateResolvers:
  letsencrypt:
    acme:
      email: admin@example.com
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: http

# dynamic.yml
routers:
  coordinator:
    tls:
      certResolver: letsencrypt      # Auto-renew certificates
      domains:
        - main: coordinator.example.com
    entryPoints: ["tcp-p2p"]
    rule: "HostSNI(`coordinator.example.com`)"
    service: coordinator
```

### Logging & Monitoring

```yaml
# traefik.yml
accessLog:
  filePath: /var/log/traefik/access.log
  format: json

log:
  level: INFO        # For security monitoring
```

### Security Checklist

- [ ] UFW firewall: deny-all by default
- [ ] Only expose Traefik proxy ports (6000-6100)
- [ ] Never expose MongoDB (27001), Redis (6379), MinIO (9000/9001)
- [ ] Rate limiting enabled
- [ ] TLS certificates (Let's Encrypt)
- [ ] Access logging enabled
- [ ] Strong credentials in .env.override
- [ ] .env.override added to .gitignore
- [ ] Monthly log review
- [ ] Quarterly credential rotation
- [ ] Encrypted offline backup of API keys

---

## n8n Integration

### Network Communication

The n8n instance connects to anytype-cli via the internal Docker network:

- **Protocol**: HTTP REST
- **Host**: `anytype-cli` (or `<stack-name>_anytype-cli_1`)
- **Port**: `31012` (or custom if changed)
- **Authentication**: Bearer token (API key from logs)

### n8n Configuration Setup

#### If n8n is on the Same Docker Network

1. In n8n, create a new HTTP request node
2. Configure:
   - **Method**: GET/POST (depending on endpoint)
   - **URL**: `http://anytype-cli:31012/api/v1/<endpoint>`
   - **Headers**:
     - `Authorization`: `Bearer <your-api-key>`
     - `Content-Type`: `application/json`

#### If n8n is External or on a Different Network

1. Verify network connectivity from n8n to Portainer Docker host
2. Use the Docker host IP:
   - **URL**: `http://<docker-host-ip>:31012/api/v1/<endpoint>`
   - Requires port 31012 to be publicly accessible (modify docker-compose.yml)

### Example Workflow: Create Object

```json
{
  "name": "Create Object in Anytype",
  "nodes": [
    {
      "parameters": {
        "url": "http://anytype-cli:31012/api/v1/object.create",
        "method": "POST",
        "headers": {
          "Authorization": "Bearer {{ $env.ANYTYPE_API_KEY }}",
          "Content-Type": "application/json"
        },
        "body": {
          "spaceId": "{{ $json.spaceId }}",
          "type": "ot/document",
          "details": {
            "name": "{{ $json.name }}"
          }
        }
      },
      "name": "Create Object"
    }
  ]
}
```

### Common API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/account.info` | GET | Get account information |
| `/api/v1/space.list` | GET | List spaces |
| `/api/v1/object.create` | POST | Create new object |
| `/api/v1/object.get` | GET | Retrieve object |
| `/api/v1/object.update` | POST | Update object |
| `/api/v1/object.delete` | POST | Delete object |

See [Anytype Developer Portal](https://developers.anytype.io) for complete API documentation.

---

## Troubleshooting

### Common Issues

#### 1. anytype-cli Container Keeps Restarting

**Symptoms**: Container restarts every 10-30 seconds

**Causes & Solutions**:

- Check logs: `docker logs <stack>_anytype-cli_1`
- Common causes:
  - Network config not generated: Ensure `generateconfig-processing` completed successfully
  - Missing dependencies: Verify coordinator is healthy
  - Port already in use: Check `netstat -tlnp | grep 31012`

**Fix**:

```bash
# View detailed logs
docker logs -f <stack>_anytype-cli_1

# Restart specific service
docker-compose -p <stack> restart anytype-cli

# Rebuild if needed
docker-compose -p <stack> up -d --force-recreate anytype-cli
```

#### 2. MongoDB Fails to Initialize

**Symptoms**: `mongo-1` container exits or stays unhealthy

**Solution**:

```bash
# Verify MongoDB is running
docker exec <stack>_mongo-1_1 mongosh --port 27001 --eval "rs.status()"

# Force replica set initialization
docker exec <stack>_mongo-1_1 mongosh --port 27001 --eval \
  "rs.initiate({_id:'rs0', members:[{_id:0, host:'mongo-1:27001'}]})"
```

#### 3. Anytype-CLI API Not Responding

**Symptoms**: Health check fails, n8n cannot connect

**Diagnosis**:

```bash
# Test API from Docker host
curl -v http://127.0.0.1:31012/api/v1/account.info \
  -H "Authorization: Bearer test"

# View anytype-cli logs
docker logs <stack>_anytype-cli_1

# Verify port binding
docker port <stack>_anytype-cli_1
```

**Solutions**:

1. Check API key in authorization header
2. Verify anytype-cli service has internet access for initial setup
3. Ensure network config was generated: `ls storage/docker-generateconfig/nodesProcessed.yml`

#### 4. n8n Cannot Connect to anytype-cli

**Symptoms**: HTTP 503 or connection timeout from n8n

**Checks**:

1. Are n8n and any-sync on the same Docker network?

   ```bash
   docker network ls
   docker network inspect <network-name> | grep -A 20 Containers
   ```

2. Verify service name resolution from n8n container:

   ```bash
   docker exec <n8n-container> nslookup anytype-cli
   ```

3. Test connectivity:

   ```bash
   docker exec <n8n-container> curl -v http://anytype-cli:31012/api/v1/account.info
   ```

**Solution**: Add n8n to the same network as any-sync:

```yaml
# In n8n docker-compose or Portainer settings
networks:
  - any-sync-network

networks:
  any-sync-network:
    external: true
    name: <stack-name>_default
```

#### 5. Services Cannot Reach Coordinator

**Symptoms**: Nodes/filenode/consensus containers exit with network errors

**Check**:

```bash
# Verify coordinator is healthy
docker ps | grep coordinator

# Test connectivity from a node
docker exec <stack>_any-sync-node-1_1 \
  nc -zv any-sync-coordinator 1004
```

**Solutions**:

1. Ensure MongoDB and Redis are healthy first
2. Check coordinator logs: `docker logs <stack>_any-sync-coordinator_1`
3. Verify dependencies are correct in docker-compose.yml

### Viewing Logs

**Via Portainer**:

1. Navigate to **Containers**
2. Select the container
3. Click **Logs** at the top
4. Use search/filter for error messages

**Via Docker CLI**:

```bash
# View recent logs
docker logs <container-id>

# Follow logs in real-time
docker logs -f <container-id>

# Last 100 lines
docker logs --tail 100 <container-id>

# With timestamps
docker logs --timestamps <container-id>
```

---

## Backup and Restore

### Backup Strategy

All persistent data is stored in Docker volumes. Create regular backups:

```bash
# List all volumes for the stack
docker volume ls | grep <stack-name>

# Volumes created:
# - any-sync-node-1, any-sync-node-2, any-sync-node-3
# - storage (parent directory for all data)
# - anytype-cli-config, anytype-cli-home
```

### Full Stack Backup

**Via Host Filesystem**:

```bash
# Stop the stack
docker-compose -p <stack> down

# Backup storage directory
tar -czf any-sync-backup-$(date +%Y%m%d).tar.gz \
  ./storage \
  ./.env.override

# Restart
docker-compose -p <stack> up -d
```

**Via Docker Volumes**:

```bash
# Backup each volume
docker run --rm \
  -v <stack>_storage:/data \
  -v /backup:/backup \
  alpine tar czf /backup/storage.tar.gz -C /data .
```

### Credential Backup

**Critical**: Backup anytype-cli credentials separately:

```bash
# Backup API key and config
docker volume inspect <stack>_anytype-cli-config
# Note the mount point, then:
sudo tar -czf anytype-cli-backup.tar.gz <mount-point>/root/.anytype/
```

### Restore Procedure

1. **Stop the stack**:

   ```bash
   docker-compose -p <stack> down
   ```

2. **Restore volumes**:

   ```bash
   # Remove current volumes
   docker volume rm <stack>_storage

   # Restore from backup
   tar -xzf any-sync-backup-20240213.tar.gz
   ```

3. **Restart**:

   ```bash
   docker-compose -p <stack> up -d
   ```

4. **Verify health**:

   ```bash
   docker-compose -p <stack> ps
   ```

---

## Updating Services

### Minor Updates (Patch Versions)

Most updates are rolled out via version tags (e.g., `prod`, `stage`):

```bash
# Update .env.override with new version
ANY_SYNC_NODE_VERSION=prod
ANY_SYNC_COORDINATOR_VERSION=prod

# Pull new images and restart
docker-compose -p <stack> up -d --pull always
```

### Major Updates

For breaking changes, consult the [README.md](README.md) and [CHANGELOG.md](CHANGELOG.md) for migration guidance.

### Rolling Back

```bash
# If an update causes issues, revert to previous version
# Edit .env.override with previous version number
ANY_SYNC_NODE_VERSION=<previous-version>

# Restart with old images
docker-compose -p <stack> up -d
```

---

## Support and Resources

- **Any-sync Documentation**: <https://github.com/anyproto/any-sync>
- **Anytype Developer Portal**: <https://developers.anytype.io>
- **Portainer Documentation**: <https://docs.portainer.io>
- **Traefik Documentation**: <https://doc.traefik.io/traefik/>
- **Docker Compose Reference**: <https://docs.docker.com/compose/compose-file/>

---

**Last Updated**: 2026-02-13
