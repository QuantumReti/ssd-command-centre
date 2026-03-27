#!/bin/bash

# Sun State Digital - Complete Production Deployment
# Deploys all services: Gateway, API, N8n, Blog Frontend
# Usage: bash deploy-all.sh

set -e

echo "🚀 Sun State Digital - Production Deployment"
echo "=============================================="
echo ""

# Load environment
if [ ! -f .env ]; then
    echo "❌ .env file not found. Copy .env.example and configure."
    exit 1
fi

source .env

echo "📋 Deployment Configuration:"
echo "  AWS Region: $AWS_REGION"
echo "  Domain: $DOMAIN"
echo "  Environment: production"
echo ""

# Step 1: Validate infrastructure
echo "1️⃣  Validating AWS infrastructure..."
if ! aws ec2 describe-vpcs --region $AWS_REGION > /dev/null 2>&1; then
    echo "❌ AWS credentials invalid or region incorrect"
    exit 1
fi
echo "✅ AWS credentials valid"
echo ""

# Step 2: Deploy OpenClaw Gateway
echo "2️⃣  Deploying OpenClaw Gateway..."
cd gateway
docker build -t ssd-gateway:latest .
docker tag ssd-gateway:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ssd-gateway:latest
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ssd-gateway:latest
cd ..
echo "✅ Gateway image pushed to ECR"
echo ""

# Step 3: Deploy Quantum Backend
echo "3️⃣  Deploying Quantum Backend API..."
cd quantum-api
docker build -t ssd-api:latest .
docker tag ssd-api:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ssd-api:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ssd-api:latest
cd ..
echo "✅ API image pushed to ECR"
echo ""

# Step 4: Deploy N8n
echo "4️⃣  Deploying N8n Workflow Engine..."
cd n8n
docker build -t ssd-n8n:latest .
docker tag ssd-n8n:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ssd-n8n:latest
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ssd-n8n:latest
cd ..
echo "✅ N8n image pushed to ECR"
echo ""

# Step 5: Deploy Blog Frontend
echo "5️⃣  Deploying Blog Frontend..."
cd blog-frontend
npm install
npm run build
aws s3 sync dist/ s3://$S3_BLOG_BUCKET/ --region $AWS_REGION
cd ..
echo "✅ Blog frontend deployed to S3"
echo ""

# Step 6: Deploy infrastructure
echo "6️⃣  Deploying infrastructure (Terraform)..."
cd terraform
terraform init -backend-config="bucket=$TERRAFORM_BUCKET" -backend-config="key=ssd/terraform.tfstate" -backend-config="region=$AWS_REGION"
terraform plan -out=tfplan
terraform apply tfplan
cd ..
echo "✅ Infrastructure deployed"
echo ""

# Step 7: Deploy Kubernetes manifests
echo "7️⃣  Deploying services to Kubernetes..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/gateway.yaml
kubectl apply -f k8s/api.yaml
kubectl apply -f k8s/n8n.yaml
kubectl apply -f k8s/postgres.yaml
echo "✅ Services deployed to Kubernetes"
echo ""

# Step 8: Setup SSL certificates
echo "8️⃣  Setting up SSL certificates (Let's Encrypt)..."
./scripts/setup-ssl.sh $DOMAIN
echo "✅ SSL certificates configured"
echo ""

# Step 9: Enable monitoring
echo "9️⃣  Enabling monitoring and logging..."
kubectl apply -f k8s/prometheus.yaml
kubectl apply -f k8s/grafana.yaml
echo "✅ Monitoring enabled"
echo ""

# Step 10: Verify deployment
echo "🔟 Verifying deployment..."
bash verify-deployment.sh

echo ""
echo "✅ DEPLOYMENT COMPLETE!"
echo ""
echo "System Information:"
echo "  Gateway: https://$DOMAIN/gateway"
echo "  API: https://$DOMAIN/api"
echo "  Dashboard: https://$DOMAIN/dashboard"
echo "  N8n: https://$DOMAIN/n8n"
echo "  Monitoring: https://$DOMAIN/prometheus"
echo ""
echo "Next steps:"
echo "  1. Login to dashboard with admin credentials"
echo "  2. Configure payment processing"
echo "  3. Onboard first client: bash onboard-client.sh"
echo ""
echo "🚀 Production deployment successful!"
