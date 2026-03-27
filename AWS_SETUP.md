# AWS Setup Guide
## Sun State Digital — Complete AWS Configuration

**Account:** Sun State Digital AWS Account
**Primary Region:** ap-southeast-2 (Sydney)
**Owner:** Joshua (joshua@sunstatedigital.com.au)

---

## 1. IAM Roles and Policies

### Create ECS Task Execution Role

```bash
# Create role
aws iam create-role \
  --role-name ssd-ecs-task-execution \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach managed policy
aws iam attach-role-policy \
  --role-name ssd-ecs-task-execution \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Add Secrets Manager access
aws iam put-role-policy \
  --role-name ssd-ecs-task-execution \
  --policy-name SecretsManagerAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:ap-southeast-2:*:secret:ssd/*"
    }]
  }'
```

### Create ECS Task Role (Application Permissions)

```bash
aws iam create-role \
  --role-name ssd-ecs-task-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# S3 client data access
aws iam put-role-policy \
  --role-name ssd-ecs-task-role \
  --policy-name S3ClientData \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
        "Resource": [
          "arn:aws:s3:::ssd-prod-client-data",
          "arn:aws:s3:::ssd-prod-client-data/*",
          "arn:aws:s3:::ssd-client-*",
          "arn:aws:s3:::ssd-client-*/*"
        ]
      },
      {
        "Effect": "Allow",
        "Action": ["ses:SendEmail", "ses:SendRawEmail"],
        "Resource": "arn:aws:ses:ap-southeast-2:*:identity/*"
      },
      {
        "Effect": "Allow",
        "Action": ["cloudwatch:PutMetricData"],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        "Resource": "arn:aws:logs:ap-southeast-2:*:log-group:/ssd/*"
      }
    ]
  }'
```

### Create Deployment Role (CI/CD)

```bash
aws iam create-role \
  --role-name ssd-deployment-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"AWS": "arn:aws:iam::123456789:user/josh-deploy"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam put-role-policy \
  --role-name ssd-deployment-role \
  --policy-name DeploymentPermissions \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
                   "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
                   "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
                   "ecr:CompleteLayerUpload", "ecr:PutImage"],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": ["ecs:RegisterTaskDefinition", "ecs:UpdateService",
                   "ecs:DescribeServices", "ecs:DescribeTaskDefinition"],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": ["iam:PassRole"],
        "Resource": ["arn:aws:iam::*:role/ssd-ecs-task-*"]
      }
    ]
  }'
```

---

## 2. VPC Configuration

### Create VPC

```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[
    {Key=Name,Value=ssd-prod-vpc},
    {Key=Project,Value=ssd-platform},
    {Key=Environment,Value=production},
    {Key=Owner,Value=joshua@sunstatedigital.com.au}
  ]' \
  --region ap-southeast-2 \
  --query 'Vpc.VpcId' --output text)

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
```

### Subnet Layout

```
10.0.0.0/16  — ssd-prod-vpc (ap-southeast-2)

Public Subnets:
  10.0.1.0/24   — ssd-prod-public-1a  (ap-southeast-2a)
  10.0.2.0/24   — ssd-prod-public-1b  (ap-southeast-2b)
  10.0.3.0/24   — ssd-prod-public-1c  (ap-southeast-2c)

Private Subnets (ECS Tasks):
  10.0.10.0/24  — ssd-prod-private-1a (ap-southeast-2a)
  10.0.11.0/24  — ssd-prod-private-1b (ap-southeast-2b)
  10.0.12.0/24  — ssd-prod-private-1c (ap-southeast-2c)

Database Subnets (RDS/ElastiCache):
  10.0.20.0/24  — ssd-prod-db-1a     (ap-southeast-2a)
  10.0.21.0/24  — ssd-prod-db-1b     (ap-southeast-2b)
  10.0.22.0/24  — ssd-prod-db-1c     (ap-southeast-2c)
```

---

## 3. Security Groups

```bash
# ALB Security Group (internet-facing)
ALB_SG=$(aws ec2 create-security-group \
  --group-name ssd-prod-alb-sg \
  --description "SSD Production ALB" \
  --vpc-id $VPC_ID \
  --region ap-southeast-2 \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $ALB_SG \
  --ip-permissions \
    IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges='[{CidrIp=0.0.0.0/0}]' \
    IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges='[{CidrIp=0.0.0.0/0}]'

# ECS Tasks Security Group
ECS_SG=$(aws ec2 create-security-group \
  --group-name ssd-prod-ecs-sg \
  --description "SSD Production ECS Tasks" \
  --vpc-id $VPC_ID \
  --region ap-southeast-2 \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $ECS_SG \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=3000,ToPort=3000,UserIdGroupPairs=[{GroupId=$ALB_SG}]" \
    "IpProtocol=tcp,FromPort=8000,ToPort=8000,UserIdGroupPairs=[{GroupId=$ALB_SG}]"

# RDS Security Group
RDS_SG=$(aws ec2 create-security-group \
  --group-name ssd-prod-rds-sg \
  --description "SSD Production RDS" \
  --vpc-id $VPC_ID \
  --region ap-southeast-2 \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $RDS_SG \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=5432,ToPort=5432,UserIdGroupPairs=[{GroupId=$ECS_SG}]"

# Redis Security Group
REDIS_SG=$(aws ec2 create-security-group \
  --group-name ssd-prod-redis-sg \
  --description "SSD Production Redis" \
  --vpc-id $VPC_ID \
  --region ap-southeast-2 \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --group-id $REDIS_SG \
  --ip-permissions \
    "IpProtocol=tcp,FromPort=6379,ToPort=6379,UserIdGroupPairs=[{GroupId=$ECS_SG}]"

echo "Security groups created:"
echo "  ALB: $ALB_SG"
echo "  ECS: $ECS_SG"
echo "  RDS: $RDS_SG"
echo "  Redis: $REDIS_SG"
```

---

## 4. ECS Cluster Setup

```bash
# Create cluster
aws ecs create-cluster \
  --cluster-name ssd-prod-cluster \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy \
    capacityProvider=FARGATE,weight=1,base=2 \
  --settings name=containerInsights,value=enabled \
  --configuration "executeCommandConfiguration={logging=OVERRIDE,logConfiguration={cloudWatchLogGroupName=/ssd/ecs-exec,cloudWatchEncryptionEnabled=false}}" \
  --tags key=Project,value=ssd-platform key=Environment,value=production \
  --region ap-southeast-2

# Create CloudWatch log groups for services
for service in openclaw-gateway quantum-api blog-frontend; do
  aws logs create-log-group \
    --log-group-name "/ssd/${service}" \
    --region ap-southeast-2
  aws logs put-retention-policy \
    --log-group-name "/ssd/${service}" \
    --retention-in-days 30 \
    --region ap-southeast-2
  echo "Log group: /ssd/${service}"
done
```

---

## 5. ECR Repositories

```bash
# Create repositories
for service in openclaw-gateway quantum-api blog-frontend; do
  REPO_URI=$(aws ecr create-repository \
    --repository-name "ssd/${service}" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 \
    --tags Key=Project,Value=ssd-platform Key=Service,Value=$service \
    --region ap-southeast-2 \
    --query 'repository.repositoryUri' --output text)
  echo "Repository: $REPO_URI"
done

# Set lifecycle policy (keep last 10 images)
LIFECYCLE_POLICY='{
  "rules": [{
    "rulePriority": 1,
    "description": "Keep last 10 tagged images",
    "selection": {
      "tagStatus": "tagged",
      "tagPrefixList": ["v"],
      "countType": "imageCountMoreThan",
      "countNumber": 10
    },
    "action": {"type": "expire"}
  }, {
    "rulePriority": 2,
    "description": "Remove untagged after 1 day",
    "selection": {
      "tagStatus": "untagged",
      "countType": "sinceImagePushed",
      "countUnit": "days",
      "countNumber": 1
    },
    "action": {"type": "expire"}
  }]
}'

for service in openclaw-gateway quantum-api blog-frontend; do
  aws ecr put-lifecycle-policy \
    --repository-name "ssd/${service}" \
    --lifecycle-policy-text "$LIFECYCLE_POLICY" \
    --region ap-southeast-2
done
```

---

## 6. RDS Instance Setup

```bash
# DB subnet group
aws rds create-db-subnet-group \
  --db-subnet-group-name ssd-prod-db-subnet-group \
  --db-subnet-group-description "SSD Production Database Subnets" \
  --subnet-ids $DB_SUBNET_1A $DB_SUBNET_1B $DB_SUBNET_1C \
  --region ap-southeast-2

# Store master password in Secrets Manager first
DB_PASS=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)
aws secretsmanager create-secret \
  --name ssd/prod/db-master-password \
  --secret-string "$DB_PASS" \
  --region ap-southeast-2

# Create RDS instance
aws rds create-db-instance \
  --db-instance-identifier ssd-prod-db \
  --db-instance-class db.t3.medium \
  --engine postgres \
  --engine-version 15.5 \
  --master-username ssd_master \
  --master-user-password "$DB_PASS" \
  --allocated-storage 100 \
  --max-allocated-storage 500 \
  --storage-type gp3 \
  --storage-encrypted \
  --multi-az \
  --db-subnet-group-name ssd-prod-db-subnet-group \
  --vpc-security-group-ids $RDS_SG \
  --backup-retention-period 7 \
  --preferred-backup-window "02:00-03:00" \
  --preferred-maintenance-window "sun:03:00-sun:04:00" \
  --auto-minor-version-upgrade true \
  --deletion-protection \
  --copy-tags-to-snapshot \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --monitoring-interval 60 \
  --tags Key=Project,Value=ssd-platform Key=Environment,Value=production \
  --region ap-southeast-2

echo "RDS instance creating... (10-15 minutes)"
aws rds wait db-instance-available \
  --db-instance-identifier ssd-prod-db \
  --region ap-southeast-2
echo "RDS ready!"
```

---

## 7. ElastiCache Cluster

```bash
# Cache subnet group
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name ssd-prod-cache-subnet-group \
  --cache-subnet-group-description "SSD Production Cache Subnets" \
  --subnet-ids $DB_SUBNET_1A $DB_SUBNET_1B $DB_SUBNET_1C \
  --region ap-southeast-2

# Redis auth token
REDIS_TOKEN=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)
aws secretsmanager create-secret \
  --name ssd/prod/redis-auth-token \
  --secret-string "$REDIS_TOKEN" \
  --region ap-southeast-2

# Create Redis cluster
aws elasticache create-replication-group \
  --replication-group-id ssd-prod-redis \
  --description "SSD Production Redis" \
  --cache-node-type cache.t3.small \
  --engine redis \
  --engine-version "7.2" \
  --num-cache-clusters 3 \
  --multi-az-enabled \
  --automatic-failover-enabled \
  --cache-subnet-group-name ssd-prod-cache-subnet-group \
  --security-group-ids $REDIS_SG \
  --at-rest-encryption-enabled \
  --transit-encryption-enabled \
  --auth-token "$REDIS_TOKEN" \
  --snapshot-retention-limit 5 \
  --snapshot-window "01:00-02:00" \
  --tags Key=Project,Value=ssd-platform Key=Environment,Value=production \
  --region ap-southeast-2
```

---

## 8. S3 Buckets

```bash
# Create all required buckets
declare -A BUCKETS=(
  ["ssd-prod-client-data"]="private"
  ["ssd-prod-backups"]="private"
  ["ssd-prod-static"]="public-read"
  ["ssd-prod-logs"]="private"
  ["ssd-prod-deployments"]="private"
)

for BUCKET in "${!BUCKETS[@]}"; do
  aws s3api create-bucket \
    --bucket "$BUCKET" \
    --region ap-southeast-2 \
    --create-bucket-configuration LocationConstraint=ap-southeast-2

  # Block public access (for private buckets)
  if [[ "${BUCKETS[$BUCKET]}" == "private" ]]; then
    aws s3api put-public-access-block \
      --bucket "$BUCKET" \
      --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
  fi

  # Enable versioning
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled

  # Enable encryption
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET" \
    --server-side-encryption-configuration '{
      "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
    }'

  # Lifecycle for backups
  if [[ "$BUCKET" == *"backup"* ]]; then
    aws s3api put-bucket-lifecycle-configuration \
      --bucket "$BUCKET" \
      --lifecycle-configuration '{
        "Rules": [{
          "Status": "Enabled",
          "Transitions": [
            {"Days": 30, "StorageClass": "STANDARD_IA"},
            {"Days": 90, "StorageClass": "GLACIER"}
          ],
          "Expiration": {"Days": 365}
        }]
      }'
  fi

  echo "Bucket configured: $BUCKET"
done
```

---

## 9. CloudFront Distributions

```bash
# Create CloudFront distribution
aws cloudfront create-distribution \
  --distribution-config '{
    "CallerReference": "ssd-prod-'$(date +%s)'",
    "Comment": "SSD Production CDN",
    "DefaultCacheBehavior": {
      "TargetOriginId": "ssd-prod-alb",
      "ViewerProtocolPolicy": "redirect-to-https",
      "AllowedMethods": {"Quantity": 7, "Items": ["GET","HEAD","OPTIONS","PUT","PATCH","POST","DELETE"]},
      "ForwardedValues": {
        "QueryString": true,
        "Cookies": {"Forward": "all"},
        "Headers": {"Quantity": 1, "Items": ["*"]}
      },
      "MinTTL": 0,
      "DefaultTTL": 60,
      "MaxTTL": 3600,
      "Compress": true
    },
    "Origins": {
      "Quantity": 1,
      "Items": [{
        "Id": "ssd-prod-alb",
        "DomainName": "ssd-prod-alb.ap-southeast-2.elb.amazonaws.com",
        "CustomOriginConfig": {
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "https-only",
          "OriginSSLProtocols": {"Quantity": 2, "Items": ["TLSv1.2", "TLSv1.3"]}
        }
      }]
    },
    "Enabled": true,
    "HttpVersion": "http2and3",
    "PriceClass": "PriceClass_All"
  }'
```

---

## 10. Route 53 Hosted Zones

```bash
# Create hosted zone
HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
  --name ssd.cloud \
  --caller-reference "ssd-$(date +%s)" \
  --hosted-zone-config Comment="Sun State Digital production" \
  --query 'HostedZone.Id' --output text | tr -d '/hostedzone/')

echo "Hosted zone: $HOSTED_ZONE_ID"
echo "Update your domain registrar with these name servers:"
aws route53 get-hosted-zone \
  --id $HOSTED_ZONE_ID \
  --query 'DelegationSet.NameServers'

# Create health check for primary
HEALTH_CHECK_ID=$(aws route53 create-health-check \
  --caller-reference "ssd-health-$(date +%s)" \
  --health-check-config '{
    "IPAddress": "13.237.5.80",
    "Port": 443,
    "Type": "HTTPS",
    "ResourcePath": "/health",
    "RequestInterval": 30,
    "FailureThreshold": 3,
    "FullyQualifiedDomainName": "ssd.cloud"
  }' \
  --query 'HealthCheck.Id' --output text)

echo "Health check ID: $HEALTH_CHECK_ID"
```

---

## 11. Cost Explorer Tags

```bash
# Activate cost allocation tags (after resources are created with tags)
aws ce update-cost-allocation-tags-status \
  --cost-allocation-tags-status '[
    {"TagKey": "Project", "Status": "Active"},
    {"TagKey": "Environment", "Status": "Active"},
    {"TagKey": "Client", "Status": "Active"},
    {"TagKey": "Owner", "Status": "Active"}
  ]'

# Set up budget alert
aws budgets create-budget \
  --account-id 123456789 \
  --budget '{
    "BudgetName": "SSD Monthly Budget",
    "BudgetLimit": {"Amount": "800", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[{
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80.0,
      "ThresholdType": "PERCENTAGE"
    },
    "Subscribers": [{
      "SubscriptionType": "EMAIL",
      "Address": "joshua@sunstatedigital.com.au"
    }]
  }]'
```

---

## Quick Reference: Resource IDs (Update After Creation)

```
VPC:              vpc-XXXXXXXX
Subnets (public): subnet-pub-1a, subnet-pub-1b, subnet-pub-1c
Subnets (private):subnet-pri-1a, subnet-pri-1b, subnet-pri-1c
Security Groups:
  ALB:            sg-XXXXXXXX
  ECS:            sg-XXXXXXXX
  RDS:            sg-XXXXXXXX
  Redis:          sg-XXXXXXXX
ECS Cluster:      ssd-prod-cluster
RDS Instance:     ssd-prod-db
ElastiCache:      ssd-prod-redis
ALB:              ssd-prod-alb
Route 53:         HOSTED_ZONE_ID
ACM Certificate:  CERT_ARN
CloudFront:       DISTRIBUTION_ID
```

*Store these IDs in 1Password or AWS Secrets Manager for reference.*
