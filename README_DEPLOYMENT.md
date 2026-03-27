# Sun State Digital - Deployment Guide

Complete guide for deploying the SSD command centre platform to production.

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Deployment Steps](#deployment-steps)
4. [Verification](#verification)
5. [Troubleshooting](#troubleshooting)
6. [Monitoring & Ops](#monitoring--ops)

---

## Prerequisites

### Required
- AWS account with EC2, RDS, S3, CloudFront, ACM permissions
- Docker & Docker Compose installed locally
- kubectl configured for EKS cluster
- Terraform >= 1.0
- Git
- Bash 4+

### Recommended
- AWS CLI configured with credentials
- SSH key pair for EC2 access
- Domain registered (Route 53 or external)

### Credentials
Gather these before starting:
- AWS Access Key & Secret
- AWS Account ID
- Domain name (or use ssd.cloud)
- Email for SSL certificates

---

## Architecture Overview

### High-Level
```
┌────────────────────────────────────────────────────┐
│           Client Applications                       │
│  (Web, Mobile, Integrations)                       │
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│  CloudFront CDN (SSL/TLS, Caching, DDoS)         │
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│  Application Load Balancer (Routing)              │
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│  EKS Kubernetes Cluster (Auto-scaling)           │
│  ┌──────────────────────────────────────────┐   │
│  │ Gateway (OpenClaw) - Auth & Routing      │   │
│  │ API (Quantum) - Client Management        │   │
│  │ N8n - Workflow Automation                │   │
│  │ Blog - Public Frontend                   │   │
│  └──────────────────────────────────────────┘   │
└────────────────────┬─────────────────────────────┘
                     │
         ┌───────────┼───────────┐
         │           │           │
    ┌────▼──┐   ┌───▼──┐   ┌──▼────┐
    │  RDS  │   │Redis │   │  S3   │
    │Postgres│  │Cache │   │Backups│
    └────────┘   └──────┘   └───────┘
```

### Services
- **OpenClaw Gateway**: Authentication, routing, client isolation
- **Quantum API**: Client management, workflow orchestration
- **N8n**: Workflow automation engine
- **Blog**: Public-facing website
- **PostgreSQL**: Primary database
- **Redis**: Caching & sessions
- **S3**: Static assets & backups

### Infrastructure
- **EKS Cluster**: 2-3 nodes, auto-scaling 1-10
- **RDS PostgreSQL**: Multi-AZ, automated backups
- **Redis ElastiCache**: High availability
- **S3 Buckets**: Versioning, lifecycle policies
- **CloudFront**: Global CDN, SSL termination
- **Route 53**: DNS, health checks
- **CloudWatch**: Logs, metrics, alarms

---

## Deployment Steps

### Step 1: Prepare Environment

```bash
# Clone repository
git clone https://github.com/QuantumReti/ssd-command-centre
cd ssd-command-centre

# Copy environment template
cp .env.example .env

# Edit with your configuration
nano .env
# Fill in: AWS credentials, domain, database passwords, etc.

# Verify AWS credentials
aws sts get-caller-identity
```

### Step 2: Run Setup Script

```bash
bash setup.sh

# This will:
# - Validate AWS credentials
# - Create VPC and networking
# - Create security groups
# - Create RDS instance
# - Create S3 buckets
# - Initialize Terraform state
# - Setup Kubernetes cluster
```

Expected output:
```
✅ AWS credentials validated
✅ VPC created (vpc-xxxxx)
✅ Security groups configured
✅ RDS PostgreSQL created
✅ S3 buckets created
✅ EKS cluster created
✅ kubectl configured
```

### Step 3: Deploy Services

```bash
bash deploy-all.sh

# This will:
# - Build Docker images
# - Push to ECR
# - Deploy Kubernetes manifests
# - Setup SSL certificates
# - Configure load balancers
# - Enable monitoring
```

Monitor the deployment:
```bash
kubectl get pods -n ssd
kubectl logs -f svc/gateway -n ssd
kubectl logs -f svc/api -n ssd
```

Expected output (after 5-10 min):
```
NAME                     READY   STATUS    RESTARTS
gateway-7f4c8b9         1/1     Running   0
api-5d9e2c1             1/1     Running   0
n8n-9b3f1a2             1/1     Running   0
blog-7e2d4a5            1/1     Running   0
postgres-0              1/1     Running   0
redis-6                 1/1     Running   0
```

### Step 4: Verify Deployment

```bash
bash verify-deployment.sh

# Checks:
# - Gateway responding
# - API healthy
# - Database connected
# - SSL certificates valid
# - Backups scheduled
# - Monitoring enabled
```

Expected output:
```
✅ Gateway: HEALTHY (Response: 200ms)
✅ API: RESPONDING (200ms average)
✅ PostgreSQL: CONNECTED (5 connections)
✅ Redis: HEALTHY
✅ SSL Certificates: VALID (expires 2026-05-27)
✅ Backups: SCHEDULED (daily at 2 UTC)
✅ Monitoring: ENABLED (Prometheus, Grafana)
```

---

## Verification

### Access Services

After deployment, access:
- **Dashboard**: https://ssd.cloud/dashboard (login with admin)
- **API Docs**: https://ssd.cloud/api/docs
- **N8n**: https://ssd.cloud/n8n
- **Blog**: https://ssd.cloud
- **Monitoring**: https://ssd.cloud/prometheus

### Run Health Checks

```bash
# Gateway
curl https://ssd.cloud/gateway/health

# API
curl https://ssd.cloud/api/health

# N8n
curl https://ssd.cloud/n8n/healthz

# Blog
curl https://ssd.cloud/ -I
```

### Check Logs

```bash
# All pods
kubectl logs -n ssd -l app=gateway --tail=50

# Specific pod
kubectl logs -n ssd gateway-7f4c8b9 -f

# Events
kubectl get events -n ssd --sort-by='.lastTimestamp'
```

---

## Troubleshooting

### Pod CrashLoopBackOff

```bash
# Check pod logs
kubectl logs -n ssd <pod-name>

# Check resource limits
kubectl describe pod -n ssd <pod-name>

# Check events
kubectl get events -n ssd --sort-by='.lastTimestamp'
```

Common causes:
- Insufficient memory/CPU
- Database connection failed
- Missing environment variables
- Invalid configuration

Solution:
```bash
# Increase resources in k8s/deployment.yaml
kubectl set resources deployment gateway -n ssd --limits=cpu=1000m,memory=1Gi

# Redeploy
kubectl rollout restart deployment/gateway -n ssd
```

### Database Connection Failed

```bash
# Check RDS status
aws rds describe-db-instances --db-instance-identifier ssd-postgres

# Check security group rules
aws ec2 describe-security-groups --filters Name=group-name,Values=ssd-rds-sg

# Test connectivity
psql -h <rds-endpoint> -U ssdadmin -d ssd_production
```

### SSL Certificate Issues

```bash
# Check certificate status
kubectl get certificate -n ssd

# View certificate details
kubectl describe certificate -n ssd ssd-tls

# Force renewal
kubectl delete secret ssd-tls -n ssd
kubectl delete certificate ssd-tls -n ssd
```

### High Latency/Errors

```bash
# Check CloudWatch logs
aws logs tail /aws/eks/ssd-cluster --follow

# Check ALB target health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...

# Scale up
kubectl scale deployment gateway --replicas=3 -n ssd
```

---

## Monitoring & Ops

### Dashboard Access
- **Prometheus**: https://ssd.cloud/prometheus
- **Grafana**: https://ssd.cloud/grafana
- **AWS CloudWatch**: AWS Console

### Key Metrics
- Request latency (API, Gateway)
- Error rates
- Database connections
- CPU/Memory usage
- Disk space
- Network throughput

### Alarms
Configured for:
- High error rate (>1%)
- API latency (>1s)
- Database CPU (>80%)
- Disk space (>80%)
- Pod restarts (>3 in 5min)

### Backup & Restore

```bash
# Manual backup
aws rds create-db-snapshot --db-instance-identifier ssd-postgres --db-snapshot-identifier ssd-backup-$(date +%s)

# List backups
aws rds describe-db-snapshots --db-instance-identifier ssd-postgres

# Restore from backup
bash scripts/restore-from-snapshot.sh ssd-backup-1234567890
```

### Scaling

```bash
# Scale deployments manually
kubectl scale deployment gateway --replicas=5 -n ssd

# Check auto-scaling status
kubectl get hpa -n ssd

# View scaling events
kubectl get events -n ssd | grep HorizontalPodAutoscaler
```

---

## Next Steps

1. **Onboard first client**: `bash onboard-client.sh`
2. **Configure billing**: Add Stripe API keys in dashboard
3. **Setup monitoring alerts**: Configure email/Slack notifications
4. **Test failover**: Kill a pod, verify recovery
5. **Schedule backups**: Verify daily backup completion

---

**Status: ✅ PRODUCTION READY**

Deploy with confidence. 🚀
