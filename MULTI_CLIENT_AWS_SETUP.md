# Multi-Client AWS Architecture
## Sun State Digital Production Infrastructure

**Primary Region:** ap-southeast-2 (Sydney)
**Secondary Region:** ap-southeast-1 (Singapore)
**Tertiary Region:** us-east-1 (Virginia)
**Architecture:** Multi-tenant ECS Fargate with per-client isolation

---

## Architecture Overview

```
                         ┌─────────────────────────────┐
                         │   ROUTE 53 (Global DNS)      │
                         │   Health checks + failover   │
                         └─────────────┬───────────────┘
                                       │
              ┌────────────────────────┼────────────────────────┐
              │                        │                        │
    ┌─────────▼──────────┐  ┌─────────▼──────────┐  ┌─────────▼──────────┐
    │ ap-southeast-2     │  │ ap-southeast-1     │  │ us-east-1          │
    │ Sydney (PRIMARY)   │  │ Singapore (WARM)   │  │ Virginia (COLD)    │
    │                    │  │                    │  │                    │
    │ CloudFront Origin  │  │ CloudFront Origin  │  │ S3 Static Backup   │
    │ ALB Active         │  │ ALB Standby        │  │ DR Recovery        │
    │ ECS Fargate        │  │ ECS Fargate        │  │                    │
    │ RDS Primary        │  │ RDS Read Replica   │  │ RDS Snapshot DR    │
    │ ElastiCache Primary│  │ ElastiCache Replica│  │                    │
    └────────────────────┘  └────────────────────┘  └────────────────────┘
```

---

## VPC Configuration (ap-southeast-2)

### VPC

```
VPC Name:     ssd-prod-vpc
CIDR:         10.0.0.0/16
DNS Hostnames: Enabled
DNS Resolution: Enabled
```

### Subnets

```
Public Subnets (ALB, NAT Gateway):
  ssd-prod-public-1a:   10.0.1.0/24   (ap-southeast-2a)
  ssd-prod-public-1b:   10.0.2.0/24   (ap-southeast-2b)
  ssd-prod-public-1c:   10.0.3.0/24   (ap-southeast-2c)

Private Subnets (ECS Tasks, RDS, ElastiCache):
  ssd-prod-private-1a:  10.0.10.0/24  (ap-southeast-2a)
  ssd-prod-private-1b:  10.0.11.0/24  (ap-southeast-2b)
  ssd-prod-private-1c:  10.0.12.0/24  (ap-southeast-2c)

Database Subnets (RDS only — isolated):
  ssd-prod-db-1a:       10.0.20.0/24  (ap-southeast-2a)
  ssd-prod-db-1b:       10.0.21.0/24  (ap-southeast-2b)
  ssd-prod-db-1c:       10.0.22.0/24  (ap-southeast-2c)
```

### NAT Gateway

```
ssd-prod-nat-1a:  Public subnet 1a → Private subnets
ssd-prod-nat-1b:  Public subnet 1b → HA failover
```

### Internet Gateway

```
ssd-prod-igw: Attached to ssd-prod-vpc
```

---

## Security Groups

```
sg-ssd-prod-alb:
  Inbound: 80/tcp 0.0.0.0/0, 443/tcp 0.0.0.0/0
  Outbound: All

sg-ssd-prod-ecs:
  Inbound: 3000/tcp from sg-ssd-prod-alb
           8000/tcp from sg-ssd-prod-alb
  Outbound: All

sg-ssd-prod-rds:
  Inbound: 5432/tcp from sg-ssd-prod-ecs
  Outbound: None

sg-ssd-prod-redis:
  Inbound: 6379/tcp from sg-ssd-prod-ecs
  Outbound: None

sg-ssd-prod-bastion:
  Inbound: 22/tcp from YOUR_IP/32
  Outbound: 22/tcp to sg-ssd-prod-ecs
```

---

## ECS Fargate Configuration

### Cluster

```
Cluster Name:        ssd-prod-cluster
Capacity Providers:  FARGATE, FARGATE_SPOT (cost saving)
Container Insights:  Enabled
```

### Service: openclaw-gateway

```yaml
Service Name:     ssd-openclaw-gateway
Task Family:      ssd-openclaw-gateway
Launch Type:      FARGATE
Desired Count:    2 (min: 2, max: 10)
CPU:              512 (0.5 vCPU)
Memory:           1024 MB
Subnets:          Private (all 3 AZs)
Security Group:   sg-ssd-prod-ecs
Load Balancer:    ssd-prod-alb
Target Group:     ssd-openclaw-tg (port 3000)
Health Check:     /health
Rolling Deployment:
  Min Healthy:    100%
  Max Percent:    200%
Auto Scaling:
  Metric: CPU utilization
  Target: 70%
  Scale Out Cooldown: 60s
  Scale In Cooldown:  300s
```

### Service: quantum-api

```yaml
Service Name:     ssd-quantum-api
Task Family:      ssd-quantum-api
Launch Type:      FARGATE
Desired Count:    2 (min: 2, max: 10)
CPU:              1024 (1 vCPU)
Memory:           2048 MB
Subnets:          Private (all 3 AZs)
Security Group:   sg-ssd-prod-ecs
Load Balancer:    ssd-prod-alb
Target Group:     ssd-quantum-tg (port 8000)
Health Check:     /health
Auto Scaling:
  Metric: CPU utilization + ALB request count
  Target: 65%
```

### Service: blog-frontend

```yaml
Service Name:     ssd-blog-frontend
Task Family:      ssd-blog-frontend
Launch Type:      FARGATE_SPOT (cost optimized, stateless)
Desired Count:    2 (min: 1, max: 6)
CPU:              256 (0.25 vCPU)
Memory:           512 MB
Subnets:          Private (all 3 AZs)
```

---

## Application Load Balancer

```
Name:       ssd-prod-alb
Scheme:     Internet-facing
IP Type:    IPv4
Subnets:    Public subnets (all 3 AZs)
SG:         sg-ssd-prod-alb

Listeners:
  Port 80 → Redirect to 443
  Port 443 → Forward rules (SSL cert: ACM)

Routing Rules:
  Host ssd.cloud           → ssd-dashboard-tg
  Host api.ssd.cloud       → ssd-openclaw-tg
  Host openclaw.ssd.cloud  → ssd-openclaw-tg
  Host quantum.ssd.cloud   → ssd-quantum-tg
  Host blog.ssd.cloud      → ssd-blog-tg
  Host monitor.ssd.cloud   → ssd-grafana-tg
  Default                  → ssd-blog-tg

Target Groups:
  ssd-openclaw-tg:  Port 3000, /health, threshold: 3
  ssd-quantum-tg:   Port 8000, /health, threshold: 3
  ssd-blog-tg:      Port 3000, /, threshold: 3
```

---

## RDS Multi-AZ PostgreSQL

```
Instance ID:         ssd-prod-db
Engine:              PostgreSQL 15.5
Instance Class:      db.t3.medium (2 vCPU, 4 GB RAM)
Multi-AZ:            Yes (automatic failover ~60-120s)
Storage:             100 GB gp3
Storage Autoscaling: Max 500 GB
Subnet Group:        ssd-prod-db-subnet-group
Security Group:      sg-ssd-prod-rds
Backup Retention:    7 days
Backup Window:       02:00-03:00 UTC (12 PM Sydney)
Maintenance Window:  Sun 03:00-04:00 UTC
Parameter Group:     ssd-prod-pg15-params
Monitoring:          Enhanced (1 second intervals)
Performance Insights: Enabled (7-day retention)
Encryption:          Enabled (AWS KMS)

Read Replica (Singapore):
  Instance ID:   ssd-prod-db-replica-sg
  Region:        ap-southeast-1
  Instance:      db.t3.small
  Replication:   Async (< 100ms lag typical)
```

**RDS Parameter Group Overrides:**
```
max_connections            = 200
shared_buffers             = 512MB
effective_cache_size       = 2GB
work_mem                   = 16MB
maintenance_work_mem       = 256MB
checkpoint_completion_target = 0.9
wal_buffers                = 32MB
default_statistics_target  = 100
log_min_duration_statement = 1000  (log queries > 1 second)
```

---

## ElastiCache Redis Cluster

```
Cluster ID:          ssd-prod-redis
Engine:              Redis 7.2
Node Type:           cache.t3.small (1.5 GB RAM)
Num Cache Nodes:     3 (1 primary + 2 replicas)
Multi-AZ:            Yes
Automatic Failover:  Enabled (60-second failover)
Subnet Group:        ssd-prod-cache-subnet-group
Security Group:      sg-ssd-prod-redis
Snapshot Retention:  5 days
Snapshot Window:     01:00-02:00 UTC
Encryption at Rest:  Enabled
Encryption in Transit: Enabled (TLS)
Auth Token:          REDACTED (from AWS Secrets Manager)
```

---

## S3 Configuration

### Per-Client Buckets

```
# Main bucket naming convention:
ssd-client-{client-id}-data

# For Quantum Buyers Agents:
ssd-client-quantum-buyers-data

# Bucket settings:
Versioning:       Enabled
Encryption:       SSE-S3 (AES-256)
Access:           Private (no public access)
Lifecycle:        Move to IA after 30 days, Glacier after 90 days
```

### Platform Buckets

```
ssd-prod-static:        Static assets, public read
ssd-prod-backups:       Database backups, private, Glacier after 30d
ssd-prod-logs:          Access logs, private, delete after 90d
ssd-prod-client-data:   Client files, private, versioned
ssd-prod-deployments:   ECS task definitions, Lambda code
```

---

## CloudFront CDN

```
Distribution: ssd-prod-cdn
Origins:
  - ssd-prod-alb (ALB origin)
  - ssd-prod-static.s3.ap-southeast-2.amazonaws.com (S3 origin)

Behaviors:
  /static/*     → S3 origin (cache 1 year)
  /images/*     → S3 origin (cache 1 year)
  /api/*        → ALB origin (no cache, forward headers)
  /*            → ALB origin (cache 1 minute for blog)

Price Class:    PriceClass_All (global CDN)
HTTP Version:   HTTP/2 + HTTP/3
WAF:            Enabled (AWS Managed Rules + rate limiting)
SSL Cert:       ACM wildcard *.ssd.cloud

Custom Error Pages:
  403 → /403.html
  404 → /404.html
  502 → /maintenance.html
  503 → /maintenance.html
```

---

## Route 53 Configuration

```
Hosted Zone: ssd.cloud (public)

A Records (Failover routing):
  ssd.cloud             PRIMARY   → 13.237.5.80 (Sydney)
  ssd.cloud             SECONDARY → Singapore IP

CNAME Records:
  api.ssd.cloud         → ssd-prod-alb.ap-southeast-2.elb.amazonaws.com
  openclaw.ssd.cloud    → ssd-prod-alb.ap-southeast-2.elb.amazonaws.com
  quantum.ssd.cloud     → ssd-prod-alb.ap-southeast-2.elb.amazonaws.com
  blog.ssd.cloud        → ssd-prod-alb.ap-southeast-2.elb.amazonaws.com
  monitor.ssd.cloud     → ssd-prod-alb.ap-southeast-2.elb.amazonaws.com

Health Checks:
  ssd-prod-primary: HTTPS on ssd.cloud/health (30s interval)
  ssd-prod-failover: Triggers if primary fails 3 consecutive checks
```

---

## IAM Configuration

### Roles

```
ECSTaskExecutionRole (ssd-ecs-task-execution):
  AmazonECSTaskExecutionRolePolicy
  Access to ECR, CloudWatch Logs, Secrets Manager

ECSTaskRole (ssd-ecs-task-role):
  S3 access (client buckets)
  SES send email
  Secrets Manager read
  CloudWatch metrics

RDSMonitoringRole (ssd-rds-monitoring):
  AmazonRDSEnhancedMonitoringRole

DeploymentRole (ssd-deployment-role):
  ECR push/pull
  ECS register task, update service
  S3 deployment bucket
  CloudWatch Logs
```

### Policies (Key Permissions)

```json
// ssd-client-s3-policy
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
  "Resource": "arn:aws:s3:::ssd-client-*/*"
}

// ssd-secrets-policy
{
  "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue"],
  "Resource": "arn:aws:secretsmanager:ap-southeast-2:*:secret:ssd/*"
}
```

---

## AWS Secrets Manager

All secrets stored under path prefix `ssd/`:

```
ssd/prod/db-credentials      — PostgreSQL master credentials
ssd/prod/redis-auth          — Redis auth token
ssd/prod/jwt-secret          — JWT signing key
ssd/prod/encryption-key      — Data encryption key
ssd/prod/openclaw-api-key    — OpenClaw internal API key
ssd/prod/google-oauth         — Google OAuth credentials
ssd/prod/meta-app            — Meta/Facebook app credentials
ssd/prod/ghl-api-key         — GoHighLevel API key
ssd/prod/slack-tokens        — Slack bot tokens
ssd/prod/openai-key          — OpenAI API key
ssd/prod/anthropic-key       — Anthropic API key
ssd/clients/{client-id}/*    — Per-client credentials
```

---

## Infrastructure as Code (Terraform)

### Directory Structure

```
terraform/
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── modules/
│   ├── vpc/
│   ├── ecs/
│   ├── rds/
│   ├── elasticache/
│   ├── alb/
│   ├── cloudfront/
│   └── route53/
└── environments/
    ├── prod/
    │   ├── terraform.tfvars
    │   └── backend.tf
    └── staging/
        ├── terraform.tfvars
        └── backend.tf
```

### Deploy with Terraform

```bash
cd terraform/environments/prod
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Cost Estimates Per Client Tier

### Starter Tier (~$200/month AWS cost)

```
ECS Fargate (shared):    $30/month
RDS t3.micro (shared):   $25/month
ElastiCache (shared):    $15/month
S3 (10 GB):              $0.23/month
CloudFront (100 GB):     $8.50/month
Route 53:                $0.50/month
Total AWS cost:          ~$80/month
Your charge:             $2,000/month
Margin:                  96%
```

### Growth Tier (~$400/month AWS cost)

```
ECS Fargate (dedicated): $120/month
RDS t3.small (dedicated):$50/month
ElastiCache (shared):    $20/month
S3 (50 GB):              $1.15/month
CloudFront (500 GB):     $42.50/month
Route 53:                $0.50/month
Additional services:     $50/month
Total AWS cost:          ~$285/month
Your charge:             $3,500/month
Margin:                  92%
```

### Enterprise Tier (~$1,200/month AWS cost)

```
ECS Fargate (dedicated): $300/month
RDS t3.medium (multi-AZ):$200/month
ElastiCache dedicated:   $80/month
S3 (500 GB):             $11.50/month
CloudFront (unlimited):  $200/month
Additional regions:      $300/month
WAF, Shield Advanced:    $150/month
Total AWS cost:          ~$1,240/month
Your charge:             $5,000+/month
Margin:                  75%+
```

---

## Deployment Checklist (New Client)

```
[ ] Create client database schema (onboard-client.sh)
[ ] Create S3 bucket (ssd-client-{id}-data)
[ ] Create IAM role for client
[ ] Configure DNS subdomain
[ ] Set up CloudFront distribution
[ ] Configure Secrets Manager entries
[ ] Deploy client-specific ECS task (if dedicated tier)
[ ] Set up monitoring dashboards
[ ] Configure alerts
[ ] Run smoke tests
[ ] Send welcome email
```

---

*For automated client onboarding, run: `./onboard-client.sh`*
*Full deployment: `./deploy-all.sh`*
