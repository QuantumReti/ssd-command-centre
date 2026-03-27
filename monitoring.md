# Monitoring Guide
## Sun State Digital Platform Operations

**Grafana:** https://monitor.ssd.cloud
**Prometheus:** Internal (access via SSH tunnel)
**Server:** 13.237.5.80

---

## 1. Grafana Setup

### Initial Access

```
URL:      https://monitor.ssd.cloud
Username: admin
Password: (GRAFANA_ADMIN_PASSWORD from .env)
```

### Data Sources

Configured in Grafana → Configuration → Data Sources:

| Name | Type | URL | Status |
|---|---|---|---|
| Prometheus | Prometheus | http://prometheus:9090 | Default |
| PostgreSQL | PostgreSQL | postgres:5432/ssd_production | Secondary |

### Dashboard Inventory

| Dashboard | UID | Description |
|---|---|---|
| Executive Overview | `executive-overview` | MRR, clients, uptime |
| System Health | `system-health` | CPU, memory, disk |
| Service Health | `service-health` | All 3 services |
| Client Performance | `client-performance` | Per-client metrics |
| Financial | `financial` | Revenue, costs |
| AWS Costs | `aws-costs` | CloudWatch cost data |

### Access Dashboard URLs Directly

```
https://monitor.ssd.cloud/d/executive-overview
https://monitor.ssd.cloud/d/system-health
https://monitor.ssd.cloud/d/service-health
https://monitor.ssd.cloud/d/client-performance
```

---

## 2. Prometheus Metrics

### Access Prometheus (SSH Tunnel)

```bash
# Forward Prometheus to localhost
ssh -L 9090:localhost:9090 ssd-prod -N &
open http://localhost:9090
```

### Key Metrics

#### Service Availability
```promql
# Is service up? (1 = yes, 0 = no)
up{job=~"openclaw|quantum|blog"}

# Uptime percentage (30 day)
avg_over_time(up{job="openclaw-gateway"}[30d]) * 100
```

#### Request Metrics
```promql
# Request rate per service (req/s)
rate(http_requests_total[5m])

# Request rate by status code
rate(http_requests_total{status=~"5.."}[5m])

# 5xx error rate percentage
rate(http_requests_total{status=~"5.."}[5m]) /
rate(http_requests_total[5m]) * 100
```

#### Latency
```promql
# P50 latency
histogram_quantile(0.50, rate(http_request_duration_seconds_bucket[5m]))

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# P99 latency
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

#### Container Resources
```promql
# CPU usage per container (%)
rate(container_cpu_usage_seconds_total[1m]) * 100

# Memory usage per container
container_memory_usage_bytes{name=~"openclaw.*|quantum.*|blog.*"}

# Memory usage percentage
container_memory_usage_bytes / container_spec_memory_limit_bytes * 100
```

#### Database
```promql
# PostgreSQL active connections
pg_stat_activity_count{state="active"}

# PostgreSQL transactions per second
rate(pg_stat_database_xact_commit[5m]) +
rate(pg_stat_database_xact_rollback[5m])

# Query execution time
pg_stat_statements_mean_exec_time_ms
```

#### Redis
```promql
# Redis hit rate
redis_keyspace_hits_total /
(redis_keyspace_hits_total + redis_keyspace_misses_total) * 100

# Redis memory usage
redis_memory_used_bytes

# Redis connected clients
redis_connected_clients
```

---

## 3. Alert Rules

### Grafana Alert Configuration

Navigate to: Grafana → Alerting → Alert Rules

#### Critical Alerts (Immediate action required)

**Service Down**
```yaml
Name:       service_down
Condition:  up == 0
For:        1 minute
Severity:   critical
Message:    "{{ $labels.job }} is DOWN. Immediate action required."
Channels:   Slack #ssd-alerts, Email joshua@sunstatedigital.com.au
```

**Very High Error Rate**
```yaml
Name:       critical_error_rate
Condition:  error_rate_percent > 5
For:        3 minutes
Severity:   critical
Message:    "Error rate {{ $value }}% on {{ $labels.service }}"
Channels:   Slack #ssd-alerts, Email
```

**Disk Full**
```yaml
Name:       disk_critical
Condition:  disk_free_percent < 5
For:        1 minute
Severity:   critical
Message:    "Only {{ $value }}% disk free — system may fail"
Channels:   Slack #ssd-alerts, Email
```

**Database Connection Failure**
```yaml
Name:       db_connection_failed
Condition:  pg_up == 0
For:        1 minute
Severity:   critical
Message:    "PostgreSQL is unreachable"
Channels:   Slack #ssd-alerts, Email
```

#### Warning Alerts (Action needed within hours)

**High Error Rate**
```yaml
Name:       high_error_rate
Condition:  error_rate_percent > 1
For:        5 minutes
Severity:   warning
Message:    "Error rate {{ $value }}% on {{ $labels.service }}"
Channels:   Slack #ssd-monitoring
```

**High CPU**
```yaml
Name:       high_cpu
Condition:  cpu_usage_percent > 80
For:        10 minutes
Severity:   warning
Message:    "CPU {{ $value }}% on {{ $labels.container }}"
Channels:   Slack #ssd-monitoring
```

**High Memory**
```yaml
Name:       high_memory
Condition:  memory_usage_percent > 85
For:        5 minutes
Severity:   warning
Message:    "Memory {{ $value }}% on {{ $labels.container }}"
Channels:   Slack #ssd-monitoring
```

**High Disk Usage**
```yaml
Name:       disk_warning
Condition:  disk_used_percent > 80
For:        5 minutes
Severity:   warning
Message:    "Disk {{ $value }}% used on {{ $labels.instance }}"
Channels:   Slack #ssd-monitoring
```

**Slow API Response**
```yaml
Name:       slow_api_p95
Condition:  p95_latency_seconds > 2
For:        10 minutes
Severity:   warning
Message:    "P95 latency {{ $value }}s exceeds 2s threshold"
Channels:   Slack #ssd-monitoring
```

**High DB Connections**
```yaml
Name:       db_connections_high
Condition:  pg_active_connections > 80
For:        5 minutes
Severity:   warning
Message:    "{{ $value }} active DB connections (max 100)"
Channels:   Slack #ssd-monitoring
```

**Redis Memory High**
```yaml
Name:       redis_memory
Condition:  redis_memory_used_bytes > 180000000
For:        5 minutes
Severity:   warning
Message:    "Redis using {{ $value | humanize }}B of 200MB limit"
Channels:   Slack #ssd-monitoring
```

#### Informational Alerts

**SSL Certificate Expiry**
```yaml
Name:       ssl_expiry_30d
Condition:  ssl_cert_not_after - time() < 86400 * 30
For:        1 hour
Severity:   info
Message:    "SSL cert for {{ $labels.domain }} expires in {{ $value | humanizeDuration }}"
Channels:   Slack #ssd-monitoring, Email
```

**Backup Failure**
```yaml
Name:       backup_not_run
Condition:  time() - last_backup_timestamp > 86400 * 1.5
For:        1 hour
Severity:   warning
Message:    "No successful backup in last 36 hours"
Channels:   Slack #ssd-alerts, Email
```

---

## 4. Slack Integration

### Contact Points Setup

In Grafana → Alerting → Contact Points:

**Critical Contact Point (ssd-critical):**
```json
{
  "name": "ssd-critical",
  "type": "slack",
  "settings": {
    "url": "SLACK_WEBHOOK_ALERTS",
    "channel": "#ssd-alerts",
    "username": "SSD Alert Bot",
    "icon_emoji": ":rotating_light:",
    "title": "{{ .GroupLabels.alertname }}",
    "text": "{{ range .Alerts }}\n*Status:* {{ .Status }}\n*Severity:* {{ .Labels.severity }}\n{{ .Annotations.description }}\n{{ end }}"
  }
}
```

**Warning Contact Point (ssd-warning):**
```json
{
  "name": "ssd-warning",
  "type": "slack",
  "settings": {
    "url": "SLACK_WEBHOOK_ALERTS",
    "channel": "#ssd-monitoring",
    "username": "SSD Monitor Bot",
    "icon_emoji": ":warning:"
  }
}
```

### Notification Policy

```
Default policy:
  Contact: ssd-warning
  Group wait: 30s
  Group interval: 5m
  Repeat interval: 4h

Specific policies:
  severity=critical → ssd-critical (repeat: 1h)
  severity=warning  → ssd-warning  (repeat: 4h)
  alertname=service_down → ssd-critical (repeat: 30m)
```

---

## 5. CloudWatch Log Aggregation

### Log Groups

```
/ssd/openclaw-gateway    — OpenClaw logs (retention: 30 days)
/ssd/quantum-api         — Quantum API logs (retention: 30 days)
/ssd/blog-frontend       — Blog logs (retention: 14 days)
/ssd/nginx-access        — Nginx access logs (retention: 90 days)
/ssd/nginx-error         — Nginx error logs (retention: 30 days)
/ssd/postgres            — PostgreSQL logs (retention: 30 days)
```

### View Logs via CLI

```bash
# View recent OpenClaw errors
aws logs filter-log-events \
  --log-group-name /ssd/openclaw-gateway \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s000) \
  --region ap-southeast-2

# View all logs from last 15 minutes
aws logs filter-log-events \
  --log-group-name /ssd/openclaw-gateway \
  --start-time $(date -d '15 minutes ago' +%s000) \
  --region ap-southeast-2 \
  --output text | tail -50

# Live tail logs
aws logs tail /ssd/openclaw-gateway --follow --region ap-southeast-2
```

---

## 6. Alert Runbooks

### Runbook: Service Down

```bash
# 1. Confirm the alert
curl -sf https://api.ssd.cloud/health || echo "DOWN"
curl -sf https://quantum.ssd.cloud/health || echo "DOWN"

# 2. Check container status
ssd-status
# or: ssh ssd-prod "docker-compose ps"

# 3. Check recent logs for the failed service
ssd-logs-api   # for openclaw
ssd-logs-quantum  # for quantum

# 4. Restart the service
ssd-restart-api   # or ssd-restart-quantum

# 5. If restart fails, check disk space
ssh ssd-prod "df -h"
# If full: docker system prune -f

# 6. If disk is fine, check memory
ssh ssd-prod "free -h"
# If OOM: may need to restart all or increase swap

# 7. If nothing works, redeploy
ssd-deploy

# 8. Notify Slack when resolved
# (happens automatically when verify-deployment.sh passes)
```

### Runbook: High Error Rate

```bash
# 1. Identify which service and endpoint
# Check Grafana: monitor.ssd.cloud/d/service-health

# 2. View error logs
ssh ssd-prod "docker logs openclaw-gateway --since 1h 2>&1 | grep -E 'ERROR|WARN' | tail -50"

# 3. Check if it's a downstream issue
curl -I https://www.googleapis.com/  # Google
curl -I https://graph.facebook.com/  # Meta

# 4. Check database health
ssh ssd-prod "docker exec postgres pg_isready -U ssd_user"

# 5. Check if it was triggered by a deploy
ssh ssd-prod "cd /opt/ssd && git log --oneline -5"

# 6. Roll back if needed
ssh ssd-prod "cd /opt/ssd && git stash && docker-compose up -d"
```

### Runbook: High CPU/Memory

```bash
# 1. Identify the container
ssh ssd-prod "docker stats --no-stream"

# 2. Check what's using CPU
ssh ssd-prod "docker exec openclaw-gateway top -bn1 | head -20"

# 3. Check for memory leaks
ssh ssd-prod "docker stats --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}'"

# 4. Restart container (usually fixes memory leaks temporarily)
ssh ssd-prod "docker restart openclaw-gateway"

# 5. If recurring, scale up or optimize code
# Scale up: change memory_limit in docker-compose.yml
# Optimize: check for N+1 queries, caching issues
```

### Runbook: Disk Space Warning

```bash
# 1. Check what's using space
ssh ssd-prod "du -sh /* 2>/dev/null | sort -rh | head -10"
ssh ssd-prod "du -sh /var/lib/docker/* 2>/dev/null | sort -rh"

# 2. Clean Docker resources
ssh ssd-prod "docker system prune -f"
ssh ssd-prod "docker image prune -a --filter 'until=24h' -f"
ssh ssd-prod "docker volume prune -f"

# 3. Clean old logs
ssh ssd-prod "sudo journalctl --vacuum-time=7d"
ssh ssd-prod "sudo find /var/log -name '*.gz' -delete"
ssh ssd-prod "find /var/log/ssd -name '*.log' -mtime +30 -delete"

# 4. If using local backups, clean them
ssh ssd-prod "find /tmp -name 'ssd-backup-*' -mtime +1 -delete"
```

### Runbook: SSL Certificate Expiry

```bash
# Check current cert expiry
ssh ssd-prod "certbot certificates"
ssh ssd-prod "openssl x509 -enddate -noout -in /etc/letsencrypt/live/ssd.cloud/cert.pem"

# Renew manually if auto-renewal failed
ssh ssd-prod "certbot renew --dry-run"  # Test first
ssh ssd-prod "certbot renew"
ssh ssd-prod "docker exec nginx nginx -s reload"

# Verify cert is loaded
curl -vI https://ssd.cloud 2>&1 | grep -A5 'SSL certificate'
```

---

## 7. Daily/Weekly Review

### Morning Check (2 minutes)

```bash
# Run this from MacBook
ssd-verify
# Review Grafana executive dashboard
# Check #ssd-alerts Slack channel
```

### Key Metrics to Review Weekly

| Metric | Target | Location |
|---|---|---|
| Uptime | > 99.9% | Grafana: service-health |
| Error rate (avg) | < 0.1% | Grafana: service-health |
| P95 latency | < 500ms | Grafana: service-health |
| Disk used | < 70% | Grafana: system-health |
| DB connections (avg) | < 50 | Grafana: system-health |
| Redis hit rate | > 90% | Grafana: system-health |
| Backup success | 100% | /var/log/ssd/backup.log |

---

*For incident response, see `SECURITY.md`. For deployment issues, see `deploy-all.sh` and `kb/KNOWLEDGE_BASE.md`.*
