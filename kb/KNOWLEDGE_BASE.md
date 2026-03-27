# Technical Knowledge Base
## Sun State Digital Platform

**Last updated:** 2026-03-18
**Platform version:** 2.0.0

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [API Reference](#api-reference)
3. [Database Schema](#database-schema)
4. [Common Operations](#common-operations)
5. [Troubleshooting](#troubleshooting)
6. [FAQ](#faq)
7. [Glossary](#glossary)

---

## 1. Architecture Overview

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                 SSD PLATFORM v2.0                            │
│                                                              │
│  External Traffic                                            │
│       │                                                      │
│       ▼                                                      │
│  CloudFront (CDN + WAF)                                     │
│       │                                                      │
│       ▼                                                      │
│  ALB (Application Load Balancer)                            │
│       │                                                      │
│  ┌────┴────────────────────────────────┐                    │
│  │         NGINX Reverse Proxy          │                    │
│  │  (SSL termination, routing, rate    │                    │
│  │   limiting, security headers)       │                    │
│  └───┬─────────────┬──────────┬────────┘                    │
│      │             │          │                              │
│      ▼             ▼          ▼                              │
│  OpenClaw      Quantum     Blog                             │
│  Gateway       Backend     Frontend                          │
│  (Node.js)     (Python)    (Next.js)                        │
│  Port 3000     Port 8000   Port 3001                        │
│      │             │                                         │
│      └──────┬──────┘                                        │
│             │                                                │
│       ┌─────┴─────┐                                         │
│       ▼           ▼                                          │
│  PostgreSQL     Redis                                        │
│  Port 5432      Port 6379                                   │
│                                                              │
│  Monitoring: Grafana (3002) + Prometheus (9090)             │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow

**Inbound Lead (example: Facebook Lead Ad):**
```
1. Meta sends webhook → POST /webhooks/meta
2. Nginx routes to OpenClaw Gateway
3. OpenClaw validates webhook signature
4. OpenClaw forwards to Quantum API: POST /api/v1/webhooks/meta
5. Quantum enriches lead data (external APIs)
6. Quantum scores lead (ML model)
7. Quantum pushes to GHL pipeline
8. Quantum triggers notification (Slack to client)
9. All events logged to PostgreSQL
10. Metrics pushed to Prometheus
```

---

## 2. API Reference

### OpenClaw Gateway (Port 3000)

#### Base URL: `https://api.ssd.cloud`

**Authentication:**
- Bearer token (JWT): `Authorization: Bearer <token>`
- API Key: `X-API-Key: sk-ocl-<key>`

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | /health | None | Health check |
| POST | /api/v1/auth/login | None | Login, returns JWT |
| POST | /api/v1/auth/refresh | Bearer | Refresh access token |
| GET | /api/v1/clients | Bearer/Admin | List all clients |
| POST | /api/v1/clients | Bearer/Admin | Create client |
| GET | /api/v1/clients/:id | Bearer | Get client |
| PUT | /api/v1/clients/:id | Bearer/Admin | Update client |
| DELETE | /api/v1/clients/:id | Bearer/Owner | Delete client |
| GET | /api/v1/workflows | API Key | List workflows |
| POST | /api/v1/workflows/run | API Key | Run workflow |
| POST | /api/v1/leads/qualify | API Key | Qualify lead |
| POST | /api/v1/leads/enrich | API Key | Enrich lead data |
| POST | /webhooks/google | Internal | Google webhook |
| POST | /webhooks/meta | HMAC | Facebook/Meta webhook |
| POST | /webhooks/ghl | HMAC | GoHighLevel webhook |
| POST | /webhooks/n8n | API Key | n8n trigger |

**Example: Qualify a lead**
```bash
curl -X POST https://api.ssd.cloud/api/v1/leads/qualify \
  -H "X-API-Key: sk-ocl-your-key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "John Smith",
    "email": "john@example.com",
    "phone": "+61412345678",
    "source": "facebook_lead_ad",
    "client_id": "quantum-buyers"
  }'
```

**Response:**
```json
{
  "lead_id": "lead_abc123",
  "score": 78,
  "tier": "warm",
  "enriched": {
    "email_valid": true,
    "phone_valid": true,
    "linkedin": "linkedin.com/in/johnsmith"
  },
  "actions_taken": ["ghl_contact_created", "nurture_sequence_started"],
  "processing_time_ms": 1240
}
```

---

### Quantum Backend API (Port 8000)

#### Base URL: `https://quantum.ssd.cloud`

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | /health | None | Health + DB check |
| GET | /docs | None | Swagger UI |
| POST | /api/v1/leads/qualify | API Key | Lead qualification |
| POST | /api/v1/leads/enrich | API Key | Data enrichment |
| POST | /api/v1/leads/score | API Key | Lead scoring (ML) |
| GET | /api/v1/properties | API Key | Property search |
| POST | /api/v1/properties/match | API Key | Buyer-property match |
| POST | /api/v1/reports/generate | API Key | Generate report |
| GET | /api/v1/analytics | Bearer | Platform analytics |
| POST | /api/v1/ai/chat | API Key | AI chat (GPT/Claude) |
| POST | /api/v1/ai/summarize | API Key | Document summarization |

**Health check response:**
```json
{
  "status": "healthy",
  "version": "1.8.2",
  "database": "connected",
  "redis": "connected",
  "openai": "connected",
  "uptime_seconds": 86400
}
```

---

## 3. Database Schema

### Main Tables (ssd_production)

```sql
-- Clients table
CREATE TABLE clients (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       VARCHAR(100) UNIQUE NOT NULL,
  client_name     VARCHAR(255) NOT NULL,
  email           VARCHAR(255) NOT NULL,
  tier            VARCHAR(50) DEFAULT 'starter',
  status          VARCHAR(50) DEFAULT 'active',
  api_key_hash    VARCHAR(255),
  s3_bucket       VARCHAR(255),
  config          JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Leads table
CREATE TABLE leads (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID REFERENCES clients(id),
  lead_data       JSONB NOT NULL,
  source          VARCHAR(100),
  score           INTEGER DEFAULT 0,
  tier            VARCHAR(50) DEFAULT 'cold',
  status          VARCHAR(50) DEFAULT 'new',
  enriched_data   JSONB DEFAULT '{}',
  processed_at    TIMESTAMPTZ DEFAULT NOW(),
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- API Keys table
CREATE TABLE api_keys (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID REFERENCES clients(id),
  key_hash        VARCHAR(255) NOT NULL,
  key_prefix      VARCHAR(20) NOT NULL,
  name            VARCHAR(255),
  permissions     TEXT[] DEFAULT ARRAY['read'],
  expires_at      TIMESTAMPTZ,
  last_used_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Workflows table
CREATE TABLE workflows (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID REFERENCES clients(id),
  name            VARCHAR(255) NOT NULL,
  type            VARCHAR(100),
  config          JSONB DEFAULT '{}',
  n8n_workflow_id VARCHAR(100),
  active          BOOLEAN DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Events/Audit log
CREATE TABLE events (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID REFERENCES clients(id),
  event_type      VARCHAR(100) NOT NULL,
  event_data      JSONB DEFAULT '{}',
  ip_address      INET,
  user_agent      TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_leads_client_id ON leads(client_id);
CREATE INDEX idx_leads_created_at ON leads(created_at DESC);
CREATE INDEX idx_leads_score ON leads(score DESC);
CREATE INDEX idx_events_client_id ON events(client_id);
CREATE INDEX idx_events_created_at ON events(created_at DESC);
CREATE INDEX idx_api_keys_hash ON api_keys(key_hash);
```

---

## 4. Common Operations

### Restart a Service

```bash
# Restart specific service
docker restart openclaw-gateway
docker restart quantum-api
docker restart blog-frontend

# Restart all services
cd /opt/ssd && docker-compose restart

# Restart with rebuild (after code changes)
cd /opt/ssd && docker-compose up -d --no-deps openclaw-gateway
```

### View Logs

```bash
# Live tail (last 100 lines, then live)
docker logs -f openclaw-gateway --tail=100

# View last hour of logs
docker logs --since 1h openclaw-gateway

# View logs with timestamps
docker logs -t openclaw-gateway --since 30m

# Filter for errors only
docker logs openclaw-gateway --since 1h 2>&1 | grep -E "ERROR|WARN|error|warn"

# All services at once
cd /opt/ssd && docker-compose logs -f --tail=50
```

### Scale a Service (ECS)

```bash
# Scale OpenClaw Gateway to 4 tasks
aws ecs update-service \
  --cluster ssd-prod-cluster \
  --service ssd-openclaw-gateway \
  --desired-count 4 \
  --region ap-southeast-2

# Check scaling status
aws ecs describe-services \
  --cluster ssd-prod-cluster \
  --services ssd-openclaw-gateway \
  --region ap-southeast-2 \
  --query 'services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount}'
```

### Add a New Client

```bash
# Automated (recommended)
cd /opt/ssd && ./onboard-client.sh

# Manual steps (if needed)
# 1. Create database schema
docker exec -it postgres psql -U ssd_user -d ssd_production << 'EOF'
INSERT INTO clients (client_id, client_name, email, tier)
VALUES ('new-client-id', 'Client Name', 'client@example.com', 'starter');
EOF

# 2. Generate API key
openssl rand -hex 32  # Save this!

# 3. Create S3 bucket
aws s3 mb s3://ssd-client-new-client-id-data --region ap-southeast-2
```

### Database Operations

```bash
# Connect to production database
docker exec -it postgres psql -U ssd_user -d ssd_production

# Common queries
\l          # List all databases
\dt         # List all tables
\d clients  # Describe clients table
\q          # Quit

# View clients
SELECT client_id, client_name, tier, status, created_at FROM clients ORDER BY created_at DESC;

# View recent leads
SELECT lead_data->>'email', score, tier, created_at FROM leads
WHERE client_id = 'CLIENT_UUID'
ORDER BY created_at DESC LIMIT 10;

# Count leads by tier
SELECT tier, COUNT(*) FROM leads
WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY tier;
```

### Check SSL Certificates

```bash
# Check expiry
sudo certbot certificates

# Manual check
openssl x509 -enddate -noout -in /etc/letsencrypt/live/ssd.cloud/cert.pem

# Force renewal
sudo certbot renew --force-renewal
sudo docker exec nginx nginx -s reload
```

### View Resource Usage

```bash
# Docker stats
docker stats --no-stream

# Disk usage
df -h
du -sh /var/lib/docker/volumes/*

# Memory
free -h

# CPU and processes
top -bn1 | head -20
```

---

## 5. Troubleshooting

### Service Not Starting

**Symptom:** `docker-compose up -d` completes but service not running

**Step 1 — Check status:**
```bash
docker-compose ps
docker logs openclaw-gateway --tail=50
```

**Step 2 — Common causes:**

| Error | Cause | Fix |
|---|---|---|
| `ECONNREFUSED 5432` | PostgreSQL not ready | Wait longer, check postgres container |
| `ECONNREFUSED 6379` | Redis not ready | Check redis container |
| `JWT_SECRET is undefined` | Missing env var | Check .env file |
| `Cannot find module` | Missing npm packages | Rebuild image |
| `Permission denied` | File permission issue | `chown -R ubuntu:ubuntu /opt/ssd` |
| `Address already in use` | Port conflict | `lsof -i :3000` then kill |

**Step 3 — Force clean restart:**
```bash
docker-compose down --remove-orphans
docker-compose up -d
```

---

### Database Connection Failed

**Symptom:** Service starts but immediately fails health check

**Check 1 — Is PostgreSQL running?**
```bash
docker ps | grep postgres
docker logs postgres --tail=20
docker exec postgres pg_isready -U ssd_user
```

**Check 2 — Can service reach database?**
```bash
docker exec openclaw-gateway nslookup postgres  # DNS
docker exec openclaw-gateway nc -zv postgres 5432  # TCP
```

**Check 3 — Credentials correct?**
```bash
docker exec postgres psql -U ssd_user -d ssd_production -c "SELECT 1;"
# Enter password from .env: POSTGRES_PASSWORD
```

**Check 4 — Database exists?**
```bash
docker exec postgres psql -U postgres -c "\l"
```

**Fix: Create database if missing:**
```bash
docker exec postgres psql -U postgres << 'EOF'
CREATE DATABASE ssd_production OWNER ssd_user;
CREATE DATABASE ssd_quantum OWNER ssd_user;
GRANT ALL PRIVILEGES ON DATABASE ssd_production TO ssd_user;
GRANT ALL PRIVILEGES ON DATABASE ssd_quantum TO ssd_user;
EOF
```

---

### Redis Connection Timeout

**Symptom:** API requests slow, 504 timeouts

**Check 1 — Is Redis running?**
```bash
docker ps | grep redis
docker exec redis redis-cli -a "$REDIS_PASSWORD" ping
# Should return: PONG
```

**Check 2 — Redis memory:**
```bash
docker exec redis redis-cli -a "$REDIS_PASSWORD" info memory | grep used_memory_human
docker exec redis redis-cli -a "$REDIS_PASSWORD" info memory | grep maxmemory_human
```

**Check 3 — Redis slow log:**
```bash
docker exec redis redis-cli -a "$REDIS_PASSWORD" slowlog get 10
```

**Fix: Clear Redis if full:**
```bash
# WARNING: This deletes all cached data (sessions will be lost)
docker exec redis redis-cli -a "$REDIS_PASSWORD" FLUSHALL
```

---

### SSL Certificate Issues

**Symptom:** Browser shows "Your connection is not secure"

**Check 1 — Certificate valid?**
```bash
curl -vI https://ssd.cloud 2>&1 | grep -A10 "SSL certificate"
```

**Check 2 — Certificate expiry:**
```bash
echo | openssl s_client -connect ssd.cloud:443 2>/dev/null | \
  openssl x509 -noout -dates
```

**Fix: Renew certificate:**
```bash
sudo certbot renew
sudo docker exec nginx nginx -s reload
# Or restart nginx
docker-compose restart nginx
```

**Fix: Wildcard cert for all subdomains:**
```bash
sudo certbot certonly \
  --dns-route53 \
  -d ssd.cloud \
  -d "*.ssd.cloud" \
  --email joshua@sunstatedigital.com.au \
  --agree-tos
```

---

### High Memory Usage

**Symptom:** Containers using more memory than expected

**Check:**
```bash
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

**Common causes:**
1. **Memory leak in Node.js** — restart container
   ```bash
   docker restart openclaw-gateway
   ```

2. **Redis too large** — check TTLs
   ```bash
   docker exec redis redis-cli -a "$REDIS_PASSWORD" info memory
   docker exec redis redis-cli -a "$REDIS_PASSWORD" dbsize
   ```

3. **PostgreSQL shared_buffers** — adjust config
   ```bash
   docker exec postgres psql -U postgres -c "SHOW shared_buffers;"
   ```

---

### Deployment Fails

**Symptom:** `./deploy-all.sh` exits with error

**Common errors:**

```bash
# Error: "disk full"
docker system prune -a  # Remove unused images/containers

# Error: "ECR auth failed"
aws ecr get-login-password --region ap-southeast-2 | \
  docker login --username AWS --password-stdin \
  123456789.dkr.ecr.ap-southeast-2.amazonaws.com

# Error: "docker-compose.yml invalid"
docker-compose -f /opt/ssd/docker-compose.yml config  # Shows errors

# Error: "port already in use"
sudo lsof -i :3000  # Find what's using port 3000
sudo kill -9 PID    # Kill it
```

---

## 6. FAQ

**Q: How do I add a new client quickly?**
A: Run `./onboard-client.sh` — fully automated, takes 5 minutes.

**Q: How do I check if all services are working?**
A: Run `./verify-deployment.sh` — shows green/red for each service.

**Q: The site is slow — what should I check first?**
A:
1. `ssd-resources` — check CPU/memory
2. Grafana → system-health — look for bottlenecks
3. `docker stats --no-stream` — per-container usage
4. Check Redis hit rate (should be > 90%)

**Q: A webhook isn't firing — how do I debug?**
A:
1. Check OpenClaw logs: `ssd-logs-api | grep webhook`
2. Verify webhook URL in the platform (Meta/GHL settings)
3. Check HMAC signature is matching
4. Test manually: `curl -X POST https://api.ssd.cloud/webhooks/test`

**Q: How do I roll back a bad deployment?**
A:
```bash
# On server
cd /opt/ssd
git log --oneline -5  # Find last good commit
git checkout COMMIT_HASH docker-compose.yml
docker-compose up -d
```

**Q: How do I view what's in the database?**
A:
```bash
ssd-db
# Then run SQL queries
# \dt to list tables
# SELECT * FROM clients;
```

**Q: How do I rotate API keys for a client?**
A:
```bash
ssh ssd-prod
cd /opt/ssd
NEW_KEY=$(openssl rand -hex 32)
# Update in database and notify client
docker exec -it postgres psql -U ssd_user -d ssd_production \
  -c "UPDATE api_keys SET key_hash = encode(digest('${NEW_KEY}', 'sha256'), 'hex') WHERE client_id = 'CLIENT_ID';"
echo "New key: sk-ocl-${NEW_KEY}"
```

**Q: Where are backups stored?**
A: `s3://ssd-prod-backups/backups/YYYYMMDD/`

**Q: How do I restore from a backup?**
A: `./backup-restore.sh restore` — prompts you to choose a date.

---

## 7. Glossary

| Term | Definition |
|---|---|
| OpenClaw Gateway | SSD's API gateway service (Node.js). Handles auth, routing, webhooks |
| Quantum Backend | Python FastAPI service. Lead qualification, enrichment, AI processing |
| ECR | Amazon Elastic Container Registry — stores Docker images |
| ECS Fargate | AWS serverless containers — runs Docker without managing servers |
| ALB | Application Load Balancer — distributes traffic across ECS tasks |
| GHL | GoHighLevel — CRM platform used by clients |
| Lead Enrichment | Adding data to a lead (LinkedIn, property data, company info) |
| Lead Scoring | 0-100 score indicating lead quality/intent |
| Hot Lead | Score 80-100 — immediate action required |
| Warm Lead | Score 50-79 — automated nurture sequence |
| Cold Lead | Score 0-49 — long-term drip |
| n8n | Open-source workflow automation (like Zapier) |
| Webhook | HTTP callback — external system posts data to SSD |
| HMAC | Hash-based Message Authentication Code — webhook security |
| JWT | JSON Web Token — authentication token |
| Redis TTL | Time-To-Live — how long a key stays in Redis cache |
| ECS Service | Auto-managed group of ECS tasks with desired count |
| Task Definition | Blueprint for an ECS task (image, CPU, memory, env vars) |
| Alembic | Python database migration tool (used by Quantum API) |
| Multi-AZ | Multiple Availability Zones — for RDS/ElastiCache HA |
| VPC | Virtual Private Cloud — isolated AWS network |
| Security Group | AWS virtual firewall |

---

*For deployment procedures, see `DEPLOYMENT.md`. For security, see `SECURITY.md`.*
*For operations/monitoring, see `monitoring.md`.*
