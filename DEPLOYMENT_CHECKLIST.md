# SSD Deployment Checklist

Use this checklist to verify each deployment step is complete.

## Pre-Deployment ✅

- [ ] AWS account created
- [ ] AWS credentials configured locally
- [ ] AWS account has EC2, RDS, S3, EKS permissions
- [ ] Docker installed and running
- [ ] Kubernetes (kubectl) installed
- [ ] Terraform installed (1.0+)
- [ ] Git installed
- [ ] Domain registered (ssd.cloud or custom)
- [ ] Email configured for SSL notifications
- [ ] Repository cloned: `git clone https://github.com/QuantumReti/ssd-command-centre`

## Configuration ✅

- [ ] `.env` file created from `.env.example`
- [ ] AWS_REGION set (ap-southeast-2 recommended)
- [ ] AWS_ACCOUNT_ID filled
- [ ] AWS_ACCESS_KEY_ID filled
- [ ] AWS_SECRET_ACCESS_KEY filled
- [ ] DOMAIN set (ssd.cloud or custom)
- [ ] EMAIL set (for SSL certs)
- [ ] POSTGRES_PASSWORD set (secure random)
- [ ] REDIS_PASSWORD set (secure random)
- [ ] Database credentials secure (not in git)
- [ ] Stripe keys added (if using payments)
- [ ] All required env vars set (check .env.example)

## AWS Validation ✅

- [ ] AWS credentials valid: `aws sts get-caller-identity`
- [ ] AWS region accessible: `aws ec2 describe-regions`
- [ ] VPC quota available (default is 5)
- [ ] EC2 quota available (at least 3 instances)
- [ ] RDS quota available (at least 1 database)
- [ ] EKS quota available (at least 1 cluster)
- [ ] EBS quota available (at least 10 volumes)

## Setup Phase ✅

- [ ] `bash setup.sh` executed successfully
- [ ] VPC created: `aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=ssd"`
- [ ] Subnets created: 2+ public, 2+ private
- [ ] Security groups created: gateway-sg, api-sg, rds-sg
- [ ] RDS PostgreSQL created: `aws rds describe-db-instances --db-instance-identifier ssd-postgres`
- [ ] S3 buckets created: 3 buckets (blog, backups, assets)
- [ ] EKS cluster created: `aws eks describe-cluster --name ssd-cluster`
- [ ] kubectl configured: `kubectl get nodes`
- [ ] Terraform state initialized: `terraform show` in terraform/

## Deployment Phase ✅

- [ ] `bash deploy-all.sh` executed
- [ ] Docker images built successfully
- [ ] Images pushed to ECR
- [ ] Kubernetes manifests applied
- [ ] All pods running: `kubectl get pods -n ssd`
  - [ ] gateway pod running
  - [ ] api pod running
  - [ ] n8n pod running
  - [ ] blog pod running
  - [ ] postgres pod running
  - [ ] redis pod running
- [ ] Persistent volumes mounted: `kubectl get pv -n ssd`
- [ ] Services created: `kubectl get svc -n ssd`
- [ ] Ingress configured: `kubectl get ingress -n ssd`
- [ ] SSL certificates created: `kubectl get certificate -n ssd`
- [ ] Load balancer provisioned
- [ ] DNS records created/updated
- [ ] CloudFront distribution created
- [ ] Monitoring enabled (Prometheus, Grafana)

## Verification Phase ✅

- [ ] `bash verify-deployment.sh` executed
- [ ] Gateway responds: `curl https://ssd.cloud/gateway/health`
- [ ] API responds: `curl https://ssd.cloud/api/health`
- [ ] Database connected: `psql -h <rds-endpoint> -U ssdadmin -d ssd_production`
- [ ] Redis responds: `redis-cli -h <redis-endpoint> PING`
- [ ] SSL certificates valid: `openssl s_client -connect ssd.cloud:443`
- [ ] Blog loads: `curl https://ssd.cloud/ -I`
- [ ] Backups scheduled: `aws events list-rules --name-prefix ssd`
- [ ] Monitoring dashboard accessible: `https://ssd.cloud/prometheus`
- [ ] All health checks green

## Post-Deployment ✅

- [ ] Admin user created in dashboard
- [ ] Dashboard accessible: `https://ssd.cloud/dashboard`
- [ ] Stripe API keys configured (if using payments)
- [ ] Email notifications configured
- [ ] Monitoring alerts tested
- [ ] Backup tested: create snapshot, verify restore
- [ ] Failover tested: kill pod, verify recovery
- [ ] Performance baseline recorded
- [ ] Documentation updated with deployment details
- [ ] Team trained on system access
- [ ] On-call rotation setup

## Security Review ✅

- [ ] Secrets not in git: `.env` in `.gitignore`
- [ ] VPC properly isolated: private subnets for databases
- [ ] Security groups restrictive: only necessary ports open
- [ ] RDS encryption enabled: `aws rds describe-db-instances`
- [ ] S3 versioning enabled: `aws s3api get-bucket-versioning`
- [ ] S3 encryption enabled: `aws s3api get-bucket-encryption`
- [ ] IAM roles reviewed: no overpermissioned service accounts
- [ ] Backup encryption enabled
- [ ] SSL/TLS enforced (no HTTP)
- [ ] DDoS protection enabled (AWS Shield)
- [ ] WAF rules configured (optional)

## Operations Ready ✅

- [ ] Runbooks created for common tasks
- [ ] Escalation procedures documented
- [ ] On-call team assigned
- [ ] Monitoring alerts configured
- [ ] Log aggregation setup
- [ ] Backup verification schedule created
- [ ] Disaster recovery tested
- [ ] Cost monitoring enabled
- [ ] Usage metrics baseline recorded
- [ ] Performance SLOs defined

## First Client Onboarding ✅

- [ ] `bash onboard-client.sh` tested
- [ ] Client isolation verified
- [ ] Client dashboard accessible
- [ ] Client integrations working
- [ ] Test workflows running
- [ ] Billing enabled
- [ ] Support email configured

---

## Rollback Plan

If deployment fails at any point:

1. **Stop deployment**: `Ctrl+C` on running scripts
2. **Diagnose issue**: Check logs in CloudWatch or `kubectl logs`
3. **Fix configuration**: Update `.env` or manifests
4. **Rollback infrastructure**: `terraform destroy` (if needed)
5. **Try again**: Re-run setup.sh and deploy-all.sh

To completely remove:
```bash
bash scripts/destroy-all.sh
# Removes: EKS cluster, RDS, S3, VPC, all resources
```

---

## Support

If checklist fails at any step:
1. Review error message carefully
2. Check relevant log file
3. Verify prerequisites are complete
4. Consult README_DEPLOYMENT.md troubleshooting section
5. Contact support@sunstatedigital.com.au

---

**Last Updated**: 2026-03-27
**Status**: Production Ready ✅
