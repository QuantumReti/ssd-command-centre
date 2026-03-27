# Exact System Snapshot
## Sun State Digital Production System Specification

**Snapshot Date:** 2026-03-18
**Server IP:** 13.237.5.80
**AWS Region:** ap-southeast-2 (Sydney)
**OS:** Ubuntu 22.04.3 LTS
**Kernel:** 5.15.0-1044-aws

---

## Hardware Specification

| Resource | Value |
|---|---|
| Instance Type | t3.medium |
| vCPUs | 2 |
| RAM | 4 GB |
| Storage | 50 GB gp3 SSD |
| Network | Up to 5 Gbps |
| EBS Throughput | 150 MB/s |
| Architecture | x86_64 |

---

## Docker Services

### Service 1: OpenClaw Gateway

```yaml
Container Name:  openclaw-gateway
Image:           123456789.dkr.ecr.ap-southeast-2.amazonaws.com/ssd/openclaw-gateway:2.1.4
Port:            3000:3000
Runtime:         Node.js 20.11.0 LTS
Framework:       Express 4.18.2
Node Env:        production
Memory Limit:    512m
Memory Reserve:  256m
CPU Limit:       0.5
Restart Policy:  unless-stopped
Health Check:    GET /health (interval: 30s, timeout: 10s, retries: 3)
Healthcheck URL: http://localhost:3000/health
Log Driver:      json-file
Log Max Size:    50m
Log Max Files:   3
```

**Environment Variables:**
```
NODE_ENV=production
PORT=3000
DATABASE_URL=postgresql://ssd_user:REDACTED@postgres:5432/ssd_production
REDIS_URL=redis://:REDACTED@redis:6379/0
JWT_SECRET=REDACTED
OPENCLAW_API_KEY=REDACTED
ENCRYPTION_KEY=REDACTED
GOOGLE_CLIENT_ID=REDACTED
GOOGLE_CLIENT_SECRET=REDACTED
META_APP_ID=REDACTED
META_APP_SECRET=REDACTED
GHL_API_KEY=REDACTED
SLACK_BOT_TOKEN=REDACTED
SLACK_WEBHOOK_URL=REDACTED
N8N_WEBHOOK_URL=REDACTED
AWS_REGION=ap-southeast-2
AWS_S3_BUCKET=ssd-prod-client-data
SMTP_HOST=email-smtp.ap-southeast-2.amazonaws.com
SMTP_PORT=587
SMTP_USER=REDACTED
SMTP_PASS=REDACTED
```

**Key Routes:**
```
GET  /health               → Health check
POST /api/v1/auth/login    → Client authentication
POST /api/v1/auth/refresh  → Token refresh
GET  /api/v1/clients       → List clients
POST /api/v1/clients       → Create client
GET  /api/v1/workflows     → List workflows
POST /api/v1/workflows/run → Trigger workflow
POST /webhooks/google      → Google webhook receiver
POST /webhooks/meta        → Meta/Facebook webhook
POST /webhooks/ghl         → GoHighLevel webhook
POST /webhooks/n8n         → n8n workflow trigger
```

---

### Service 2: Quantum Backend API

```yaml
Container Name:  quantum-api
Image:           123456789.dkr.ecr.ap-southeast-2.amazonaws.com/ssd/quantum-api:1.8.2
Port:            8000:8000
Runtime:         Python 3.11.7
Framework:       FastAPI 0.104.1 + Uvicorn 0.24.0
Workers:         4 (Uvicorn)
Memory Limit:    768m
Memory Reserve:  384m
CPU Limit:       0.75
Restart Policy:  unless-stopped
Health Check:    GET /health (interval: 30s, timeout: 10s, retries: 3)
Healthcheck URL: http://localhost:8000/health
Log Driver:      json-file
Log Max Size:    50m
Log Max Files:   3
```

**Key Endpoints:**
```
GET  /health                  → Health check + version
GET  /docs                    → Swagger UI (dev only)
GET  /redoc                   → ReDoc documentation
POST /api/v1/leads/qualify    → Lead qualification workflow
POST /api/v1/leads/enrich     → Data enrichment (OSINT)
POST /api/v1/leads/score      → Lead scoring (ML model)
GET  /api/v1/properties       → Property listings
POST /api/v1/properties/match → Property-buyer matching
POST /api/v1/reports/generate → Generate client reports
GET  /api/v1/analytics        → Platform analytics
POST /api/v1/ai/chat          → OpenAI-powered chat
POST /api/v1/ai/summarize     → Document summarization
```

**Python Packages (key):**
```
fastapi==0.104.1
uvicorn==0.24.0
sqlalchemy==2.0.23
alembic==1.12.1
psycopg2-binary==2.9.9
redis==5.0.1
openai==1.3.7
anthropic==0.7.7
pydantic==2.5.0
httpx==0.25.2
celery==5.3.6
boto3==1.33.0
```

---

### Service 3: Blog Frontend

```yaml
Container Name:  blog-frontend
Image:           123456789.dkr.ecr.ap-southeast-2.amazonaws.com/ssd/blog-frontend:1.2.0
Port:            3001:3000
Runtime:         Node.js 20.11.0 (Next.js 14.0.3)
Framework:       Next.js 14 (App Router)
Output:          Standalone
Memory Limit:    256m
Memory Reserve:  128m
CPU Limit:       0.25
Restart Policy:  unless-stopped
Health Check:    GET / (interval: 60s, timeout: 10s, retries: 3)
```

---

### Service 4: PostgreSQL 15

```yaml
Container Name:  postgres
Image:           postgres:15.5-alpine
Port:            5432 (internal only, not exposed to host)
Version:         15.5
Alpine:          3.18
Memory Limit:    512m
Memory Reserve:  256m
CPU Limit:       0.5
Restart Policy:  unless-stopped
Health Check:    pg_isready -U ssd_user -d ssd_production
```

**PostgreSQL Configuration:**
```
max_connections = 100
shared_buffers = 128MB
effective_cache_size = 512MB
work_mem = 4MB
maintenance_work_mem = 64MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
min_wal_size = 1GB
max_wal_size = 4GB
max_worker_processes = 2
max_parallel_workers_per_gather = 1
max_parallel_workers = 2
max_parallel_maintenance_workers = 1
```

**Databases:**
```
ssd_production    — Main application database
ssd_quantum       — Quantum API database
quantum_buyers    — Quantum Buyers Agents client DB
```

**Users:**
```
ssd_user          — Application user (CRUD on all DBs)
ssd_readonly      — Read-only user (monitoring)
postgres          — Admin (emergency use only)
```

---

### Service 5: Redis 7

```yaml
Container Name:  redis
Image:           redis:7.2.3-alpine
Port:            6379 (internal only)
Version:         7.2.3
Alpine:          3.18
Memory Limit:    256m
Memory Reserve:  128m
CPU Limit:       0.25
Restart Policy:  unless-stopped
Health Check:    redis-cli ping
```

**Redis Configuration:**
```
maxmemory 200mb
maxmemory-policy allkeys-lru
appendonly yes
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
requirepass REDACTED
bind 0.0.0.0
protected-mode no
```

**Redis Key Prefixes:**
```
session:*           — User sessions (TTL: 24h)
cache:api:*         — API response cache (TTL: 5min)
cache:leads:*       — Lead data cache (TTL: 1h)
queue:*             — Job queues
ratelimit:*         — Rate limiting counters (TTL: 1min)
lock:*              — Distributed locks (TTL: 30s)
```

---

### Service 6: Nginx Reverse Proxy

```yaml
Container Name:  nginx
Image:           nginx:1.25.3-alpine
Ports:           80:80, 443:443
Version:         1.25.3
Config:          /etc/nginx/nginx.conf (mounted from host)
SSL Certs:       /etc/letsencrypt (mounted from host)
Restart Policy:  unless-stopped
```

**Virtual Hosts:**
```
ssd.cloud              → dashboard (port 3000)
api.ssd.cloud          → openclaw-gateway (port 3000)
openclaw.ssd.cloud     → openclaw-gateway (port 3000)
quantum.ssd.cloud      → quantum-api (port 8000)
blog.ssd.cloud         → blog-frontend (port 3001)
monitor.ssd.cloud      → grafana (port 3002)
```

---

### Service 7: Grafana

```yaml
Container Name:  grafana
Image:           grafana/grafana:10.2.2
Port:            3002:3000
Version:         10.2.2
Memory Limit:    256m
Restart Policy:  unless-stopped
Admin User:      admin
Admin Password:  REDACTED (see .env)
```

---

### Service 8: Prometheus

```yaml
Container Name:  prometheus
Image:           prom/prometheus:v2.47.2
Port:            9090 (internal only)
Version:         2.47.2
Scrape Interval: 15s
Retention:       15 days
Memory Limit:    256m
```

---

## Networking

### Docker Networks

```
ssd-network        — Main app network (all services)
monitoring-network — Grafana + Prometheus only
```

### Host Firewall (UFW)

```
22/tcp    ALLOW   (SSH — restricted to known IPs)
80/tcp    ALLOW   (HTTP — redirects to HTTPS)
443/tcp   ALLOW   (HTTPS)
51820/udp ALLOW   (WireGuard VPN)
```

### AWS Security Groups

```
sg-ssd-prod:
  Inbound:
    22/tcp    0.0.0.0/0   (SSH — should restrict to your IP)
    80/tcp    0.0.0.0/0   (HTTP)
    443/tcp   0.0.0.0/0   (HTTPS)
  Outbound:
    All traffic 0.0.0.0/0
```

---

## Storage

### Docker Volumes

```
ssd-postgres-data    — PostgreSQL data files
ssd-redis-data       — Redis AOF and snapshots
ssd-grafana-data     — Grafana dashboards and config
ssd-prometheus-data  — Prometheus metrics store
ssd-nginx-logs       — Nginx access/error logs
```

### Host Paths

```
/opt/ssd/               — Application root
/opt/ssd/.env           — Environment variables
/opt/ssd/docker-compose.yml
/opt/ssd/nginx.conf
/opt/ssd/deploy-all.sh  (+ other scripts)
/etc/letsencrypt/       — SSL certificates
/var/log/ssd/           — Application logs
```

---

## SSL Certificates

```
Provider:   Let's Encrypt (Certbot)
Algorithm:  RSA 4096-bit
Renewal:    Auto-renew via cron (60-day expiry threshold)
Domains:    ssd.cloud, *.ssd.cloud

Cert path:  /etc/letsencrypt/live/ssd.cloud/fullchain.pem
Key path:   /etc/letsencrypt/live/ssd.cloud/privkey.pem
```

---

## Installed Software (Host)

```
docker          24.0.7
docker-compose  2.23.3
nginx           1.24.0
certbot         2.7.4
postgresql-client 15.5
redis-cli       7.2.3
nodejs          20.11.0
npm             10.2.4
awscli          2.15.0
python3         3.10.12
git             2.34.1
htop            3.2.2
curl            7.81.0
jq              1.6
tmux            3.2a
fail2ban        0.11.2
ufw             0.36
```

---

## Cron Jobs

```
# SSL certificate auto-renewal (twice daily)
0 0,12 * * * certbot renew --quiet --deploy-hook "docker exec nginx nginx -s reload"

# Daily database backup to S3 (2 AM Sydney time)
0 2 * * * /opt/ssd/backup-restore.sh backup >> /var/log/ssd/backup.log 2>&1

# Health check every 5 minutes
*/5 * * * * /opt/ssd/verify-deployment.sh --quiet >> /var/log/ssd/health.log 2>&1

# Log rotation
0 3 * * 0 /usr/sbin/logrotate /etc/logrotate.d/ssd
```

---

## System Limits

```
# /etc/security/limits.conf additions
ubuntu soft nofile 65536
ubuntu hard nofile 65536
ubuntu soft nproc 32768
ubuntu hard nproc 32768

# /etc/sysctl.conf additions
vm.swappiness=10
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
fs.file-max=2097152
```

---

## Swap File

```
Size:     4GB
File:     /swapfile
Type:     swap
Mount:    permanent (in /etc/fstab)
Priority: -2
```

---

*Snapshot accurate as of 2026-03-18. Run `./verify-deployment.sh` for current live status.*
