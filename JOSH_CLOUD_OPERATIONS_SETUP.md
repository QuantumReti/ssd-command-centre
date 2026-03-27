# Josh's Cloud Operations Hub
## Executive Dashboard & Operations Configuration

**Owner:** Josh — joshua@sunstatedigital.com.au
**Purpose:** Single pane of glass for running Sun State Digital

---

## Overview

Your operations hub gives you real-time visibility and control over:
- All services and their health
- Client activity and performance
- Revenue and business metrics
- Infrastructure costs and optimization
- Alerts and incident management

---

## 1. Grafana Dashboards

### Access

```
URL:       https://monitor.ssd.cloud
Username:  admin
Password:  (from .env: GRAFANA_ADMIN_PASSWORD)
```

### Dashboard 1: Executive Overview

**URL:** https://monitor.ssd.cloud/d/executive-overview

```
Panels:
┌─────────────────┬─────────────────┬─────────────────┐
│  Total MRR      │  Active Clients │  Uptime (30d)   │
│  $15,000        │       8         │  99.97%         │
├─────────────────┼─────────────────┼─────────────────┤
│  API Requests   │  Error Rate     │  Avg Latency    │
│  2.4M / month   │  0.02%          │  142ms          │
├─────────────────┴─────────────────┴─────────────────┤
│  Revenue Trend (6 months)                            │
│  [Bar chart: Jan Feb Mar Apr May Jun]               │
├─────────────────────────────────────────────────────┤
│  Client Health Matrix                                │
│  Client      │ Status │ API Calls │ Issues          │
│  Quantum BA  │   ✅   │  125,000  │  0              │
│  ...         │   ✅   │  ...      │  ...            │
└─────────────────────────────────────────────────────┘
```

**Metrics shown:**
- Monthly Recurring Revenue (MRR)
- Number of active clients
- Platform uptime percentage (30-day rolling)
- Total API requests (30-day)
- Global error rate
- Average API response time

### Dashboard 2: System Health

**URL:** https://monitor.ssd.cloud/d/system-health

```
Panels:
- CPU usage per service (real-time)
- Memory usage per service (real-time)
- Disk I/O
- Network I/O
- Docker container count
- ECS task health (if using ECS)
- PostgreSQL connections, query times
- Redis hit rate, memory usage
- Nginx request rate, active connections
```

### Dashboard 3: Client Performance

**URL:** https://monitor.ssd.cloud/d/client-performance

```
Filter: Client dropdown (select client to view)

Panels per client:
- API requests/hour (time series)
- Workflow executions/day
- Lead processing volume
- Error count
- Response time percentiles (p50, p95, p99)
- Data storage used
- Costs attributed to this client
```

**Grafana JSON config for client dashboard:**
```json
{
  "title": "Client Performance",
  "uid": "client-performance",
  "templating": {
    "list": [{
      "name": "client",
      "type": "query",
      "query": "SELECT client_id FROM clients WHERE active = true",
      "datasource": "PostgreSQL"
    }]
  }
}
```

### Dashboard 4: Financial Dashboard

**URL:** https://monitor.ssd.cloud/d/financial

```
Panels:
- MRR trend (12 months)
- New MRR this month
- Churned MRR
- Net MRR change
- AWS cost by service
- AWS cost by client
- Revenue vs Infrastructure cost ratio
- Per-client profitability
- Projected annual revenue
```

### Dashboard 5: Infrastructure Cost

**URL:** https://monitor.ssd.cloud/d/aws-costs

```
Data Source: AWS CloudWatch Cost Explorer
Panels:
- Daily spend trend
- Spend by service (ECS, RDS, CloudFront, etc.)
- Spend by client tag
- Budget alerts (threshold: $500/day warning, $800/day critical)
- Reserved instance recommendations
- Cost optimization suggestions
```

---

## 2. Prometheus Metrics

### Prometheus Access (via SSH tunnel)

```bash
# Forward Prometheus to localhost
ssh -L 9090:localhost:9090 ssd-prod -N &

# Open in browser
open http://localhost:9090
```

### Key Prometheus Queries

```promql
# Service availability (should be 1 for all)
up{job=~"openclaw|quantum|blog"}

# Request rate per service
rate(http_requests_total[5m])

# Error rate (5xx responses)
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Database connections
pg_stat_activity_count{state="active"}

# Redis hit rate
redis_keyspace_hits_total / (redis_keyspace_hits_total + redis_keyspace_misses_total)

# Container memory usage
container_memory_usage_bytes{name=~"openclaw|quantum|blog"}

# CPU usage percentage
rate(container_cpu_usage_seconds_total[1m]) * 100
```

---

## 3. Alert Configuration

### Alert Rules (Grafana Alert Manager)

Edit at: https://monitor.ssd.cloud/alerting/list

```yaml
# Service Down
name: service_down
condition: up{job=~"openclaw|quantum|blog"} == 0
for: 1m
severity: critical
message: "{{ $labels.job }} is DOWN!"

# High Error Rate
name: high_error_rate
condition: error_rate > 0.01
for: 5m
severity: warning
message: "Error rate {{ $value }}% on {{ $labels.service }}"

# High CPU
name: high_cpu
condition: cpu_usage > 80
for: 10m
severity: warning
message: "CPU {{ $value }}% on {{ $labels.container }}"

# High Memory
name: high_memory
condition: memory_usage_percent > 85
for: 5m
severity: warning
message: "Memory {{ $value }}% on {{ $labels.container }}"

# Low Disk Space
name: low_disk
condition: disk_free_percent < 10
for: 5m
severity: critical
message: "Only {{ $value }}% disk free on {{ $labels.instance }}"

# Slow API Response
name: slow_api
condition: p95_latency_seconds > 2
for: 10m
severity: warning
message: "P95 latency {{ $value }}s on {{ $labels.service }}"

# SSL Cert Expiring
name: ssl_expiry
condition: ssl_cert_not_after - time() < 86400 * 30
severity: warning
message: "SSL cert expires in {{ $value }} days"

# High DB Connections
name: db_connections
condition: pg_connections > 80
for: 5m
severity: warning
message: "{{ $value }} DB connections active"
```

---

## 4. Slack Notification Setup

### Create Slack App

1. Go to https://api.slack.com/apps
2. Create New App → "SSD Operations"
3. Enable Incoming Webhooks
4. Create webhook for each channel:

```
#ssd-alerts        → Critical alerts, service down
#ssd-deployments   → Deploy success/fail
#ssd-clients       → New client onboarded, payments
#ssd-monitoring    → Warning level alerts
```

5. Copy webhook URLs to `.env`:

```bash
SLACK_WEBHOOK_ALERTS=https://hooks.slack.com/services/T.../B.../...
SLACK_WEBHOOK_DEPLOYMENTS=https://hooks.slack.com/services/T.../B.../...
SLACK_WEBHOOK_CLIENTS=https://hooks.slack.com/services/T.../B.../...
```

### Slack Notification Format

Alerts sent to Slack look like:

```
🚨 CRITICAL ALERT — SSD Platform

Service: openclaw-gateway
Status: DOWN
Duration: 2 minutes
Region: ap-southeast-2 (Sydney)

Last known error:
  "Error: ECONNREFUSED 10.0.10.5:5432"

Actions:
  • Check logs: ssd-logs-api
  • Restart: ssd-restart-api
  • Dashboard: https://monitor.ssd.cloud

Time: 2026-03-18 14:23:11 AEDT
```

### Grafana → Slack Integration

1. In Grafana: Alerting → Contact Points → New Contact Point
2. Type: Slack
3. Webhook URL: (from above)
4. Message format:
   ```
   {{ range .Alerts }}
   *{{ .Labels.alertname }}*
   Status: {{ .Status }}
   {{ .Annotations.description }}
   {{ end }}
   ```

---

## 5. Multi-Region Failover Setup

### Automatic Failover Configuration

Route 53 health checks trigger automatic failover:

```
Primary (Sydney):
  Health Check: HTTPS 13.237.5.80 /health every 30s
  Failure Threshold: 3 consecutive failures

Failover (Singapore):
  Activates within: 90 seconds of primary failure

Process:
1. Route 53 detects primary is failing health checks
2. DNS TTL (60 seconds) expires
3. Traffic routes to Singapore
4. PagerDuty/Slack alert fires to Josh
5. Josh investigates and fixes Sydney
6. Test Sydney recovery
7. Update Route 53 to route back to Sydney
```

### Manual Failover Commands

```bash
# Check current DNS routing
dig ssd.cloud +short

# Force failover to Singapore
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "ssd.cloud",
        "Type": "A",
        "Failover": "SECONDARY",
        "HealthCheckId": "HEALTH-CHECK-ID",
        "TTL": 60,
        "ResourceRecords": [{"Value": "SINGAPORE_IP"}]
      }
    }]
  }'

# Check failover status
aws route53 get-health-check-status --health-check-id HEALTH-CHECK-ID
```

### Recovery Procedure

```bash
# 1. Fix the issue in primary region
ssh ssd-prod
cd /opt/ssd
./deploy-all.sh

# 2. Verify primary is healthy
./verify-deployment.sh

# 3. Update Route 53 back to primary
# (Automatic if Route 53 health check passes)

# 4. Confirm traffic is routing correctly
dig ssd.cloud +short  # Should return Sydney IP

# 5. Send all-clear to Slack
curl -X POST $SLACK_WEBHOOK_ALERTS \
  -d '{"text": "✅ Primary region Sydney restored. All traffic routing normally."}'
```

---

## 6. Mobile Access (iPhone/iPad)

### Grafana Mobile App

1. Install **Grafana** app from App Store
2. Add server: https://monitor.ssd.cloud
3. Login with admin credentials
4. Pin dashboards to home screen:
   - Executive Overview
   - System Health

### Mobile Alerts

Grafana sends push notifications to phone when:
- Any critical alert fires
- Service is down for > 1 minute
- Daily summary at 8 AM AEDT

### AWS Console Mobile App

1. Install **AWS Console** from App Store
2. Login with IAM credentials
3. Set region: Asia Pacific (Sydney)
4. Bookmark: EC2, ECS, RDS

---

## 7. Operations Runbooks

### Runbook: Service Not Responding

```bash
# 1. Check service status
ssd-status

# 2. Check recent logs
ssd-logs-api  # or ssd-logs-quantum, ssd-logs-blog

# 3. Check resource usage
ssd-resources

# 4. Attempt restart
ssd-restart-api

# 5. If restart fails, redeploy
ssd-deploy-api

# 6. If still failing, check database
ssd-db  # Try connecting
\l      # List databases
\q      # Quit

# 7. Check disk space (common cause)
ssh ssd-prod "df -h"
# If full: docker system prune -a

# 8. Escalate to AWS if needed
aws ecs describe-services --cluster ssd-prod-cluster --services ssd-openclaw-gateway
```

### Runbook: High Error Rate

```bash
# 1. View error logs
ssh ssd-prod "docker logs openclaw-gateway --since 1h 2>&1 | grep ERROR | tail -50"

# 2. Check if it's database related
ssh ssd-prod "docker exec postgres pg_isready"

# 3. Check Redis
ssh ssd-prod "docker exec redis redis-cli -a $REDIS_PASSWORD ping"

# 4. Check for bad deployments (roll back if needed)
ssh ssd-prod "cd /opt/ssd && git log --oneline -5"
ssh ssd-prod "cd /opt/ssd && git checkout HEAD~1 && docker-compose up -d"

# 5. Check upstream APIs (Google, Meta, etc.)
curl -I https://www.googleapis.com/
curl -I https://graph.facebook.com/
```

### Runbook: Disk Space Warning

```bash
# Check disk usage
ssh ssd-prod "df -h"
ssh ssd-prod "du -sh /var/lib/docker/*"

# Clean Docker resources (safe)
ssh ssd-prod "docker system prune -f"
ssh ssd-prod "docker volume prune -f"

# Clean old logs
ssh ssd-prod "sudo journalctl --vacuum-time=7d"
ssh ssd-prod "sudo find /var/log -name '*.gz' -delete"

# Clear old backups (if local)
ssh ssd-prod "find /tmp -name 'ssd-backup-*' -mtime +3 -delete"
```

---

## 8. Daily Operations Checklist

### Morning Check (5 minutes)

```bash
# Run this every morning
ssd-verify

# Check overnight alerts in Slack (#ssd-alerts)
# Review Grafana executive dashboard
# Check AWS Cost Explorer for anomalies
```

### Weekly Review (30 minutes)

```
[ ] Review error rates in Grafana (weekly trend)
[ ] Check database size growth
[ ] Review AWS costs vs budget
[ ] Check SSL cert expiry dates
[ ] Review security logs for anomalies
[ ] Update client performance reports
[ ] Check backup success/failure log
[ ] Review and clear old Docker images
```

### Monthly Review (1 hour)

```
[ ] Review MRR growth
[ ] Client health review
[ ] Security audit (check IAM keys, rotate if needed)
[ ] Review and optimize AWS Reserved Instances
[ ] Update documentation if infrastructure changed
[ ] Review and update alert thresholds
[ ] Test disaster recovery procedure
```

---

## 9. Cost Optimization

### AWS Cost Explorer Tags

All resources tagged:
```
Project:     ssd-platform
Environment: prod
Client:      {client-id} (for per-client resources)
ManagedBy:   terraform
Owner:       joshua@sunstatedigital.com.au
```

### Cost Alerts

```
AWS Budget Alert 1: $500/month warning
AWS Budget Alert 2: $800/month critical
Notification: joshua@sunstatedigital.com.au + Slack

Check costs: https://console.aws.amazon.com/cost-management
```

### Quick Wins

```
1. Use FARGATE_SPOT for stateless services (70% cheaper)
2. RDS t3 burstable instances for dev/staging
3. S3 lifecycle policies (move to IA/Glacier)
4. Reserved instances for predictable baseline workload
5. Right-size ECS tasks based on actual CPU/memory usage
```

---

*Your operations hub is your primary interface to the platform. Keep Grafana bookmarked on all devices.*
