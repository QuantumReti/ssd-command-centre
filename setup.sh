#!/bin/bash

# Sun State Digital - Setup Script
# Initializes AWS infrastructure and prepares for deployment
# Usage: bash setup.sh

set -e

echo "🔧 Sun State Digital - Setup"
echo "=============================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI required"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl required"; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "❌ Docker required"; exit 1; }
echo "✅ All prerequisites installed"
echo ""

# Load environment
if [ ! -f .env ]; then
    echo "❌ .env file not found"
    exit 1
fi
source .env

# Validate AWS credentials
echo "Validating AWS credentials..."
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "❌ AWS credentials invalid"
    exit 1
fi
echo "✅ AWS credentials valid"
echo ""

# Create S3 bucket for Terraform state
echo "Setting up Terraform state bucket..."
if ! aws s3 ls "s3://$TERRAFORM_BUCKET" 2>/dev/null; then
    aws s3 mb "s3://$TERRAFORM_BUCKET" --region "$AWS_REGION"
    aws s3api put-bucket-versioning \
        --bucket "$TERRAFORM_BUCKET" \
        --versioning-configuration Status=Enabled
    echo "✅ Terraform state bucket created"
else
    echo "✅ Terraform state bucket exists"
fi
echo ""

# Create DynamoDB table for Terraform locks
echo "Creating DynamoDB lock table..."
if ! aws dynamodb describe-table --table-name "$TERRAFORM_DYNAMODB_TABLE" --region "$AWS_REGION" 2>/dev/null; then
    aws dynamodb create-table \
        --table-name "$TERRAFORM_DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region "$AWS_REGION"
    echo "✅ DynamoDB lock table created"
else
    echo "✅ DynamoDB lock table exists"
fi
echo ""

# Initialize Terraform
echo "Initializing Terraform..."
cd terraform
terraform init \
    -backend-config="bucket=$TERRAFORM_BUCKET" \
    -backend-config="key=ssd/terraform.tfstate" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="dynamodb_table=$TERRAFORM_DYNAMODB_TABLE"
cd ..
echo "✅ Terraform initialized"
echo ""

# Create ECR repositories
echo "Creating ECR repositories..."
for repo in gateway api n8n blog; do
    if ! aws ecr describe-repositories --repository-names "ssd-$repo" --region "$AWS_REGION" 2>/dev/null; then
        aws ecr create-repository \
            --repository-name "ssd-$repo" \
            --region "$AWS_REGION"
        echo "✅ ECR repository created: ssd-$repo"
    else
        echo "✅ ECR repository exists: ssd-$repo"
    fi
done
echo ""

# Create S3 buckets
echo "Creating S3 buckets..."
for bucket in "$S3_BLOG_BUCKET" "$S3_BACKUPS_BUCKET" "$S3_ASSETS_BUCKET"; do
    if ! aws s3 ls "s3://$bucket" 2>/dev/null; then
        aws s3 mb "s3://$bucket" --region "$AWS_REGION"
        aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled
        aws s3api put-bucket-encryption --bucket "$bucket" \
            --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
        echo "✅ S3 bucket created: $bucket"
    else
        echo "✅ S3 bucket exists: $bucket"
    fi
done
echo ""

# Create VPC and networking
echo "Creating VPC and networking infrastructure..."
cd terraform
terraform apply -auto-approve -var="aws_region=$AWS_REGION" -var="domain=$DOMAIN"
cd ..
echo "✅ VPC and networking created"
echo ""

# Configure kubectl
echo "Configuring kubectl..."
aws eks update-kubeconfig --name ssd-cluster --region "$AWS_REGION"
kubectl cluster-info
echo "✅ kubectl configured"
echo ""

# Create Kubernetes namespaces
echo "Creating Kubernetes namespaces..."
kubectl create namespace ssd || true
kubectl create namespace monitoring || true
echo "✅ Namespaces created"
echo ""

# Create secrets for database credentials
echo "Creating Kubernetes secrets..."
kubectl create secret generic postgres-credentials \
    --from-literal=username="$POSTGRES_USER" \
    --from-literal=password="$POSTGRES_PASSWORD" \
    -n ssd || true

kubectl create secret generic redis-credentials \
    --from-literal=password="$REDIS_PASSWORD" \
    -n ssd || true

kubectl create secret generic app-secrets \
    --from-literal=jwt-secret="$API_JWT_SECRET" \
    --from-literal=encryption-key="$API_ENCRYPTION_KEY" \
    -n ssd || true
echo "✅ Kubernetes secrets created"
echo ""

# Generate SSH key for EC2 access
echo "Generating SSH key pair..."
if [ ! -f ~/.ssh/ssd-deploy.pem ]; then
    aws ec2 create-key-pair --key-name ssd-deploy --region "$AWS_REGION" \
        --query 'KeyMaterial' --output text > ~/.ssh/ssd-deploy.pem
    chmod 400 ~/.ssh/ssd-deploy.pem
    echo "✅ SSH key created: ~/.ssh/ssd-deploy.pem"
else
    echo "✅ SSH key exists: ~/.ssh/ssd-deploy.pem"
fi
echo ""

# Create CloudWatch log groups
echo "Creating CloudWatch log groups..."
aws logs create-log-group --log-group-name /aws/eks/ssd-cluster 2>/dev/null || true
aws logs create-log-group --log-group-name /aws/rds/ssd-postgres 2>/dev/null || true
echo "✅ CloudWatch log groups created"
echo ""

echo "✅ SETUP COMPLETE!"
echo ""
echo "Next steps:"
echo "  1. Verify configuration: cat .env"
echo "  2. Deploy services: bash deploy-all.sh"
echo "  3. Verify deployment: bash verify-deployment.sh"
echo ""
echo "🚀 Ready for deployment!"
