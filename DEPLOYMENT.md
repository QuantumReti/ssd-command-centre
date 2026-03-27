# Detailed Deployment Guide
## Sun State Digital Platform — AWS Production Deployment

**Architecture:** AWS ECS Fargate + RDS Multi-AZ + ElastiCache
**Estimated deployment time:** 45-90 minutes (first time)
**Subsequent deployments:** 5-10 minutes via `deploy-all.sh`

---

## Architecture Decision Records

### ADR-001: ECS Fargate over EC2 Auto Scaling Groups

**Decision:** Use ECS Fargate for container orchestration
**Rationale:**
- No EC2 instance management overhead
- Pay only for actual container runtime
- Automatic scaling without cluster management
- Built-in integration with IAM, CloudWatch, ECR

### ADR-002: RDS Multi-AZ over Aurora

**Decision:** Use RDS PostgreSQL 15 Multi-AZ
**Rationale:**
- Known PostgreSQL compatibility
- Simpler pricing model
- Multi-AZ provides 99.95% uptime
- Aurora would be overkill for current scale

### ADR-003: Single ECR Registry per Service

**Decision:** Separate ECR repository per service
**Rationale:**
- Independent deployment of each service
- Per-service access control
- Cleaner lifecycle management

---

## Prerequisites

Before deploying, ensure you have:

```bash
# Required tools
aws --version          # AWS CLI v2+
docker --version       # Docker 20+
docker-compose --version  # v2+
terraform --version    # v1.5+ (optional, for IaC)
jq --version           # JSON processor

# AWS authentication
aws sts get-caller-identity  # Should show your account

# Required AWS permissions
# - ECS (CreateCluster, CreateService, RegisterTaskDefinition)
# - ECR (CreateRepository, PutImage)
# - RDS (CreateDBInstance, ModifyDBInstance)
# - ElastiCache (CreateCacheCluster)
# - ALB (CreateLoadBalancer, CreateTargetGroup, CreateListener)
# - Route 53 (ChangeResourceRecordSets)
# - ACM (RequestCertificate)
# - VPC (CreateVpc, CreateSubnet, CreateSecurityGroup)
# - IAM (CreateRole, AttachRolePolicy)
# - S3 (CreateBucket, PutBucketPolicy)
# - CloudFront (CreateDistribution)
# - Secrets Manager (CreateSecret, PutSecretValue)
```

---

## Step 1: VPC Setup

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=ssd-prod-vpc},{Key=Project,Value=ssd-platform}]' \
  --region ap-southeast-2 \
  --query 'Vpc.VpcId' --output text)

echo "VPC: $VPC_ID"

# Enable DNS
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support

# Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=ssd-prod-igw}]' \
  --region ap-southeast-2 \
  --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# Create subnets (3 AZs each)
for az in a b c; do
  # Public subnet
  aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block "10.0.$((${az/a/1}${az/b/2}${az/c/3})).0/24" \
    --availability-zone "ap-southeast-2${az}" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ssd-prod-public-1${az}}]" \
    --region ap-southeast-2

  # Private subnet
  aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block "10.0.$((10 + ${az/a/0}${az/b/1}${az/c/2})).0/24" \
    --availability-zone "ap-southeast-2${az}" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=ssd-prod-private-1${az}}]" \
    --region ap-southeast-2
done

echo "VPC setup complete. VPC ID: $VPC_ID"
```

---

## Step 2: ECS Cluster Creation

```bash
# Create ECS cluster
aws ecs create-cluster \
  --cluster-name ssd-prod-cluster \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy \
    capacityProvider=FARGATE,weight=1,base=1 \
  --settings name=containerInsights,value=enabled \
  --tags key=Project,value=ssd-platform key=Environment,value=production \
  --region ap-southeast-2

# Create ECR repositories
for service in openclaw-gateway quantum-api blog-frontend; do
  aws ecr create-repository \
    --repository-name "ssd/${service}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --region ap-southeast-2
  echo "ECR repo created: ssd/${service}"
done

# Create log groups
for service in openclaw-gateway quantum-api blog-frontend nginx; do
  aws logs create-log-group \
    --log-group-name "/ssd/${service}" \
    --retention-in-days 30 \
    --region ap-southeast-2
done
```

---

## Step 3: RDS PostgreSQL Setup

```bash
# Create DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name ssd-prod-db-subnet-group \
  --db-subnet-group-description "SSD production DB subnets" \
  --subnet-ids subnet-db-1a subnet-db-1b subnet-db-1c \
  --region ap-southeast-2

# Create parameter group
aws rds create-db-parameter-group \
  --db-parameter-group-name ssd-prod-pg15-params \
  --db-parameter-group-family postgres15 \
  --description "SSD optimized PostgreSQL 15 params" \
  --region ap-southeast-2

# Apply performance parameters
aws rds modify-db-parameter-group \
  --db-parameter-group-name ssd-prod-pg15-params \
  --parameters \
    "ParameterName=max_connections,ParameterValue=200,ApplyMethod=pending-reboot" \
    "ParameterName=shared_buffers,ParameterValue={DBInstanceClassMemory/4},ApplyMethod=pending-reboot" \
    "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate" \
  --region ap-southeast-2

# Create RDS instance (Multi-AZ)
aws rds create-db-instance \
  --db-instance-identifier ssd-prod-db \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 15.5 \
  --master-username ssd_admin \
  --master-user-password "$(openssl rand -base64 32)" \
  --allocated-storage 100 \
  --storage-type gp3 \
  --storage-encrypted \
  --multi-az \
  --db-subnet-group-name ssd-prod-db-subnet-group \
  --vpc-security-group-ids sg-ssd-prod-rds \
  --db-parameter-group-name ssd-prod-pg15-params \
  --backup-retention-period 7 \
  --preferred-backup-window "02:00-03:00" \
  --preferred-maintenance-window "sun:03:00-sun:04:00" \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --monitoring-interval 1 \
  --monitoring-role-arn arn:aws:iam::123456789:role/rds-monitoring-role \
  --deletion-protection \
  --tags Key=Project,Value=ssd-platform Key=Environment,Value=production \
  --region ap-southeast-2

echo "RDS creating... (~10 minutes)"
aws rds wait db-instance-available --db-instance-identifier ssd-prod-db --region ap-southeast-2
echo "RDS ready!"
```

---

## Step 4: ElastiCache Setup

```bash
# Create cache subnet group
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name ssd-prod-cache-subnet-group \
  --cache-subnet-group-description "SSD ElastiCache subnets" \
  --subnet-ids subnet-private-1a subnet-private-1b subnet-private-1c \
  --region ap-southeast-2

# Create Redis replication group
aws elasticache create-replication-group \
  --replication-group-id ssd-prod-redis \
  --replication-group-description "SSD production Redis cluster" \
  --cache-node-type cache.t3.small \
  --engine redis \
  --engine-version 7.2 \
  --num-cache-clusters 3 \
  --multi-az-enabled \
  --automatic-failover-enabled \
  --cache-subnet-group-name ssd-prod-cache-subnet-group \
  --security-group-ids sg-ssd-prod-redis \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled \
  --auth-token "$(openssl rand -base64 32)" \
  --snapshot-retention-limit 5 \
  --snapshot-window "01:00-02:00" \
  --tags Key=Project,Value=ssd-platform Key=Environment,Value=production \
  --region ap-southeast-2

echo "ElastiCache creating... (~5 minutes)"
```

---

## Step 5: ALB Configuration

```bash
# Create ALB
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name ssd-prod-alb \
  --type application \
  --scheme internet-facing \
  --ip-address-type ipv4 \
  --subnets subnet-public-1a subnet-public-1b subnet-public-1c \
  --security-groups sg-ssd-prod-alb \
  --tags Key=Project,Value=ssd-platform \
  --region ap-southeast-2 \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Create target groups
for service in openclaw quantum blog; do
  PORT=$([ "$service" == "openclaw" ] && echo "3000" || [ "$service" == "quantum" ] && echo "8000" || echo "3000")
  HEALTH=$([ "$service" == "blog" ] && echo "/" || echo "/health")

  TG_ARN=$(aws elbv2 create-target-group \
    --name "ssd-${service}-tg" \
    --protocol HTTP \
    --port $PORT \
    --vpc-id $VPC_ID \
    --health-check-protocol HTTP \
    --health-check-path $HEALTH \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 10 \
    --healthy-threshold-count 3 \
    --unhealthy-threshold-count 3 \
    --target-type ip \
    --region ap-southeast-2 \
    --query 'TargetGroups[0].TargetGroupArn' --output text)

  echo "Target group ssd-${service}-tg: $TG_ARN"
done

# Create HTTPS listener (requires SSL cert from ACM)
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTPS \
  --port 443 \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
  --certificates CertificateArn=$ACM_CERT_ARN \
  --default-actions Type=forward,TargetGroupArn=$BLOG_TG_ARN \
  --region ap-southeast-2

# HTTP → HTTPS redirect
aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP \
  --port 80 \
  --default-actions \
    Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}' \
  --region ap-southeast-2
```

---

## Step 6: Route 53 Setup

```bash
# Create hosted zone (if not exists)
HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
  --name ssd.cloud \
  --caller-reference "ssd-$(date +%s)" \
  --query 'HostedZone.Id' --output text | tr -d '/hostedzone/')

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names ssd-prod-alb \
  --region ap-southeast-2 \
  --query 'LoadBalancers[0].DNSName' --output text)

ALB_ZONE=$(aws elbv2 describe-load-balancers \
  --names ssd-prod-alb \
  --region ap-southeast-2 \
  --query 'LoadBalancers[0].CanonicalHostedZoneId' --output text)

# Create A records for all subdomains
for subdomain in "" "api" "openclaw" "quantum" "blog" "monitor"; do
  NAME="${subdomain:+$subdomain.}ssd.cloud"
  aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch "{
      \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"${NAME}\",
          \"Type\": \"A\",
          \"AliasTarget\": {
            \"HostedZoneId\": \"${ALB_ZONE}\",
            \"DNSName\": \"${ALB_DNS}\",
            \"EvaluateTargetHealth\": true
          }
        }
      }]
    }"
  echo "DNS record set: $NAME → $ALB_DNS"
done
```

---

## Step 7: SSL Certificates (ACM)

```bash
# Request wildcard certificate
CERT_ARN=$(aws acm request-certificate \
  --domain-name "ssd.cloud" \
  --subject-alternative-names "*.ssd.cloud" \
  --validation-method DNS \
  --region ap-southeast-2 \
  --query 'CertificateArn' --output text)

echo "Certificate requested: $CERT_ARN"
echo "Complete DNS validation in Route 53 console"
echo "Or use: aws acm describe-certificate --certificate-arn $CERT_ARN"

# Wait for validation (after adding DNS records)
aws acm wait certificate-validated \
  --certificate-arn $CERT_ARN \
  --region ap-southeast-2

echo "Certificate validated!"
```

---

## Step 8: Initial Data Seeding

```bash
# Connect to RDS and create databases/users
RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier ssd-prod-db \
  --region ap-southeast-2 \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $RDS_ENDPOINT -U ssd_admin -d postgres << 'EOF'
-- Create databases
CREATE DATABASE ssd_production;
CREATE DATABASE ssd_quantum;

-- Create application user
CREATE USER ssd_user WITH PASSWORD 'YOUR_APP_PASSWORD';

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE ssd_production TO ssd_user;
GRANT ALL PRIVILEGES ON DATABASE ssd_quantum TO ssd_user;

-- Create read-only user for monitoring
CREATE USER ssd_readonly WITH PASSWORD 'YOUR_READONLY_PASSWORD';
GRANT CONNECT ON DATABASE ssd_production TO ssd_readonly;
GRANT USAGE ON SCHEMA public TO ssd_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ssd_readonly;

\q
EOF

echo "Database users and permissions set up"

# Run migrations
docker-compose run --rm quantum-api python -m alembic upgrade head
echo "Migrations complete"
```

---

## Step 9: Deploy Application

```bash
# Build and push all images
./deploy-all.sh

# Verify everything is running
./verify-deployment.sh
```

---

## Post-Deployment Verification

```bash
# Check all services respond
curl -sf https://ssd.cloud/health && echo "Dashboard: OK" || echo "Dashboard: FAIL"
curl -sf https://api.ssd.cloud/health && echo "API: OK" || echo "API: FAIL"
curl -sf https://quantum.ssd.cloud/health && echo "Quantum: OK" || echo "Quantum: FAIL"
curl -sf https://blog.ssd.cloud && echo "Blog: OK" || echo "Blog: FAIL"
curl -sf https://monitor.ssd.cloud && echo "Monitor: OK" || echo "Monitor: FAIL"

# Check SSL
echo | openssl s_client -connect api.ssd.cloud:443 2>/dev/null | \
  openssl x509 -noout -dates

# Check DNS propagation
dig ssd.cloud +short
dig api.ssd.cloud +short
```

---

## Rollback Procedure

```bash
# Option 1: Roll back ECS to previous task definition
PREVIOUS_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition ssd-openclaw-gateway:PREVIOUS_REVISION \
  --region ap-southeast-2 \
  --query 'taskDefinition.taskDefinitionArn' --output text)

aws ecs update-service \
  --cluster ssd-prod-cluster \
  --service ssd-openclaw-gateway \
  --task-definition $PREVIOUS_TASK_DEF \
  --region ap-southeast-2

# Option 2: Roll back docker-compose on server
ssh ssd-prod "cd /opt/ssd && git checkout HEAD~1 docker-compose.yml && docker-compose up -d"

# Option 3: Restore from last backup
ssh ssd-prod "/opt/ssd/backup-restore.sh restore"
```

---

*For daily operations after deployment, see `JOSH_CLOUD_OPERATIONS_SETUP.md`.*
*For adding clients, see `CLIENT_ONBOARDING_SYSTEM.md` and `onboard-client.sh`.*
