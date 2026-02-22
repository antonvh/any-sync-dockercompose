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
- Use the Docker provider for label-based routing
- Define TCP/UDP entrypoints for ports 1001-1006 and 1011-1016
- Implement rate limiting for DDoS protection

---

## Architecture Overview

An anysync instance serves as a sync host
An anytype-cli instance serves as an automation interface bot
Access to anytype-cli for n8n via an internal docker network.


## Docker Compose via Portainer

1. **Open Portainer Dashboard**
   - Log in to your Portainer instance

2. **Create a New Stack**
   - Go to **Stacks** > **Add Stack**
   - Choose deployment method:
     - **Paste compose file**: Copy the contents of `docker-compose.anytype-cli-portainer.yml`

3. **Configure Stack Name**
   - Enter a name (e.g., `any-sync-network`)
   - This will be the prefix for all generated resources

4. **Set Environment Variables**
   - Click 'load from .env file'
   - Upload .env.default or default.env
   - Change these settings:
     - CONFIG_DIR -> "/data/anytype/config"
     - STORAGE_DIR -> "/data/anytype/storage"
     - ANY_SYNC_DOMAIN -> anytype.yourdomain.com
     - ANY_SYNC_NODE_VERSION=latest
     - ANY_SYNC_FILENODE_VERSION=latest
     - ANY_SYNC_COORDINATOR_VERSION=latest
     - ANY_SYNC_CONSENSUSNODE_VERSION=latest


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

To allow external clients to reach any-sync services, configure Traefik for TCP/QUIC routing (see [External Access via Traefik](#external-access-via-traefik)).

### Multi-IP Configuration

To bind services to multiple network interfaces:

1. Update `.env.override`:

   ```env
   EXTERNAL_LISTEN_HOSTS=192.168.1.100 10.0.0.50
   ```

1. The any-sync services will advertise all IPs to the network

2. Restart the stack:

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

- Stored under `${CONFIG_DIR}/anytype-cli` for persistence

1. **Starts the HTTP API server**
   - Listens on port from `ANYTYPE_API_PORT` env var (default: 31012)

- Internally only (Docker network, not published to host)

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

1. Delete the config data under `${CONFIG_DIR}/anytype-cli`
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

### Traefik Static Configuration (required)

This stack uses Docker labels for routing, so only the static entrypoints are needed in Traefik.

**1. Configure Traefik Static Config** (`traefik.yml`):

```yaml
entryPoints:
  anytype-tcp-1001:
    address: ":1001/tcp"
  anytype-tcp-1002:
    address: ":1002/tcp"
  anytype-tcp-1003:
    address: ":1003/tcp"
  anytype-tcp-1004:
    address: ":1004/tcp"
  anytype-tcp-1005:
    address: ":1005/tcp"
  anytype-tcp-1006:
    address: ":1006/tcp"

  anytype-udp-1011:
    address: ":1011/udp"
  anytype-udp-1012:
    address: ":1012/udp"
  anytype-udp-1013:
    address: ":1013/udp"
  anytype-udp-1014:
    address: ":1014/udp"
  anytype-udp-1015:
    address: ":1015/udp"
  anytype-udp-1016:
    address: ":1016/udp"

```

Routing is defined by Docker labels in the compose file (no `dynamic.yml` needed).

### DNS Configuration

For clients to connect to your any-sync network, configure DNS to point to **Traefik** (not Docker host):

**Single A Record**:

```bash
# Point the domain used in ANY_SYNC_DOMAIN to Traefik's public IP
anytype.example.com  A  203.0.113.50
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

# Allow Any-Sync P2P ports only
sudo ufw allow 1001:1006/tcp comment "Any-Sync TCP"
sudo ufw allow 1011:1016/udp comment "Any-Sync QUIC"

# HTTPS for Traefik dashboard
sudo ufw allow 443/tcp comment "HTTPS"

# Enable firewall
sudo ufw enable

# Verify rules
sudo ufw status numbered
```

### DDoS Protection & Rate Limiting

For TCP/UDP entrypoints, prefer OS-level firewall rules and rate limiting at the edge. HTTP middlewares in Traefik do not apply to TCP/UDP routers.

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
```

TLS routing is configured by Docker labels in the compose file (no `dynamic.yml` needed).

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
- [ ] Only expose Any-Sync P2P ports (1001-1006/tcp, 1011-1016/udp)
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

Use n8n on the `bridge` network to reach Anytype CLI:

- **URL**: `http://anytype-cli:31012/api/v1/<endpoint>`
- **Auth**: `Authorization: Bearer <api-key>` (from anytype-cli logs)

If n8n runs elsewhere, attach it to the `bridge` network or explicitly publish `ANYTYPE_API_PORT` on the host.

---

## Troubleshooting

Quick checks:

- `docker compose ps` for health status
- `docker logs <stack>_anytype-cli_1` for API key and startup errors
- `docker exec <n8n-container> curl -v http://anytype-cli:31012/api/v1/account.info` to verify n8n connectivity
- `docker exec <stack>_mongo-1_1 mongosh --port 27001 --eval "rs.status()"` for Mongo replica set

---

## Backup and Restore

### Backup Strategy

All persistent data lives under `STORAGE_DIR` and `CONFIG_DIR`.

### Full Stack Backup

**Via Host Filesystem**:

```bash
# Stop the stack
docker-compose -p <stack> down

# Backup storage and config directories
tar -czf any-sync-backup-$(date +%Y%m%d).tar.gz \
  "$STORAGE_DIR" \
  "$CONFIG_DIR" \
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

**Critical**: Backup Anytype CLI credentials under `${CONFIG_DIR}/anytype-cli`.

### Restore Procedure

1. **Stop the stack**:

   ```bash
   docker-compose -p <stack> down
   ```

2. **Restore volumes**:

   ```bash

# Restore from backup

   tar -xzf any-sync-backup-20240213.tar.gz

   ```

3. **Restart**:

   ```bash
   docker-compose -p <stack> up -d
   ```

1. **Verify health**:

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
