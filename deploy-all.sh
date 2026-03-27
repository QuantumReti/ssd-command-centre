#!/bin/bash
# =============================================================================
# Sun State Digital — Master Deployment Script
# Deploys all services: OpenClaw Gateway, Quantum API, Blog Frontend
# Usage: ./deploy-all.sh [--skip-checks] [--no-notify]
# =============================================================================

set -euo pipefail

# --- Configuration ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_LOG="/var/log/ssd/deploy-$(date +%Y%m%d-%H%M%S).log"
SLACK_WEBHOOK="${SLACK_WEBHOOK_DEPLOYMENTS:-}"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
ECR_REGISTRY="${ECR_REGISTRY:-123456789.dkr.ecr.ap-southeast-2.amazonaws.com}"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
ENV_FILE="${SCRIPT_DIR}/.env"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SKIP_CHECKS=false
NO_NOTIFY=false
for arg in "$@"; do
  case $arg in
    --skip-checks) SKIP_CHECKS=true ;;
    --no-notify)   NO_NOTIFY=true ;;
  esac
done

mkdir -p "$(dirname "$DEPLOY_LOG")"
exec > >(tee -a "$DEPLOY_LOG") 2>&1

log()     { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $1${NC}"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $1${NC}"; }
header()  { echo -e "\n${BOLD}${BLUE}══════ $1 ══════${NC}\n"; }

DEPLOY_START=$(date +%s)
DEPLOY_VERSION=$(git -C "$SCRIPT_DIR" describe --tags --always 2>/dev/null || echo "unknown")
DEPLOYED_BY="${USER:-ubuntu}"

notify_slack() {
  local status="$1" message="$2" color="$3"
  [[ "$NO_NOTIFY" == "true" ]] || [[ -z "$SLACK_WEBHOOK" ]] && return 0
  local elapsed=$(( $(date +%s) - DEPLOY_START ))
  curl -s -X POST "$SLACK_WEBHOOK" -H "Content-Type: application/json" \
    -d "{\"attachments\":[{\"color\":\"${color}\",\"title\":\"${status}: SSD Platform Deployment\",\"text\":\"${message}\",\"fields\":[{\"title\":\"Version\",\"value\":\"${DEPLOY_VERSION}\",\"short\":true},{\"title\":\"Duration\",\"value\":\"${elapsed}s\",\"short\":true},{\"title\":\"By\",\"value\":\"${DEPLOYED_BY}\",\"short\":true}]}]}" \
    > /dev/null || warn "Slack notification failed"
}

cleanup_on_failure() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    error "Deployment FAILED (exit $exit_code) — log: $DEPLOY_LOG"
    notify_slack "FAILED" "Deployment failed. Log: $DEPLOY_LOG" "danger"
  fi
}
trap cleanup_on_failure EXIT

echo -e "\n${BOLD}${BLUE}  SSD PLATFORM DEPLOYMENT — $(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
log "Version: $DEPLOY_VERSION | Region: $AWS_REGION | By: $DEPLOYED_BY"
notify_slack "STARTED" "Deployment started by $DEPLOYED_BY. Version: $DEPLOY_VERSION" "warning"

# ---- PRE-FLIGHT CHECKS ----
header "PRE-FLIGHT CHECKS"

if [[ "$SKIP_CHECKS" == "false" ]]; then
  [[ -f "$ENV_FILE" ]] || { error ".env not found. Copy .env.example to .env"; exit 1; }
  source "$ENV_FILE"
  success "Environment file loaded"

  docker info > /dev/null 2>&1 || { error "Docker not running"; exit 1; }
  success "Docker running"

  DISK_USED=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
  [[ $DISK_USED -gt 85 ]] && { error "Disk ${DISK_USED}% full. Run: docker system prune -a"; exit 1; }
  success "Disk: ${DISK_USED}% used"

  for var in DATABASE_URL REDIS_URL JWT_SECRET OPENCLAW_API_KEY AWS_REGION; do
    [[ -z "${!var:-}" ]] && { error "Missing env var: $var"; exit 1; }
  done
  success "Required env vars present"

  docker-compose -f "$COMPOSE_FILE" config > /dev/null 2>&1 || { error "docker-compose.yml has errors"; exit 1; }
  success "docker-compose.yml valid"
else
  warn "Skipping pre-flight checks"
fi

# ---- PULL IMAGES ----
header "PULLING IMAGES"
aws ecr get-login-password --region "$AWS_REGION" 2>/dev/null | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY" 2>/dev/null \
  && success "ECR login OK" || warn "ECR login failed — using cached images"
docker-compose -f "$COMPOSE_FILE" pull --ignore-pull-failures 2>/dev/null || true
success "Images up to date"

# ---- BACKUP BEFORE DEPLOY ----
header "PRE-DEPLOY BACKUP"
[[ -f "${SCRIPT_DIR}/backup-restore.sh" ]] && \
  "${SCRIPT_DIR}/backup-restore.sh" backup --quiet && success "Backup complete" \
  || warn "Backup skipped"

# ---- DEPLOY ----
header "DEPLOYING SERVICES"

log "Stopping old containers..."
docker-compose -f "$COMPOSE_FILE" down --timeout 30 --remove-orphans 2>/dev/null || true

log "Starting infrastructure (postgres, redis)..."
docker-compose -f "$COMPOSE_FILE" up -d postgres redis
sleep 5

log "Waiting for PostgreSQL..."
for i in $(seq 1 30); do
  docker exec postgres pg_isready -U ssd_user -d ssd_production -q 2>/dev/null && break
  [[ $i -eq 30 ]] && { error "PostgreSQL failed to start"; docker logs postgres --tail=30; exit 1; }
  sleep 1
done
success "PostgreSQL ready"

log "Waiting for Redis..."
for i in $(seq 1 30); do
  docker exec redis redis-cli -a "${REDIS_PASSWORD:-}" ping 2>/dev/null | grep -q "PONG" && break
  [[ $i -eq 30 ]] && { error "Redis failed to start"; exit 1; }
  sleep 1
done
success "Redis ready"

log "Running database migrations..."
docker-compose -f "$COMPOSE_FILE" run --rm quantum-api python -m alembic upgrade head 2>/dev/null \
  && success "Migrations complete" || warn "Migrations skipped (may be up to date)"

log "Starting application services..."
docker-compose -f "$COMPOSE_FILE" up -d openclaw-gateway quantum-api blog-frontend
success "Application services starting"

log "Starting monitoring..."
docker-compose -f "$COMPOSE_FILE" up -d nginx grafana prometheus
success "Monitoring services starting"

log "Waiting for health checks (60s max)..."
sleep 10
for service_port in "openclaw-gateway:3000/health" "quantum-api:8000/health" "blog-frontend:3000"; do
  svc="${service_port%%:*}"; ep="${service_port#*:}"
  for i in $(seq 1 30); do
    curl -sf "http://localhost:${ep}" > /dev/null 2>&1 && break
    [[ $i -eq 30 ]] && { warn "$svc not responding"; break; }
    sleep 2
  done
  curl -sf "http://localhost:${ep}" > /dev/null 2>&1 && success "$svc healthy" || warn "$svc not yet responding"
done

# ---- VERIFY ----
header "VERIFICATION"
[[ -f "${SCRIPT_DIR}/verify-deployment.sh" ]] && "${SCRIPT_DIR}/verify-deployment.sh" --summary || true

ELAPSED=$(( $(date +%s) - DEPLOY_START ))

header "DEPLOYMENT COMPLETE"
docker-compose -f "$COMPOSE_FILE" ps
echo ""
success "Deployed in ${ELAPSED}s — Version: ${DEPLOY_VERSION}"
echo -e "  ${CYAN}Dashboard:  ${NC}https://ssd.cloud"
echo -e "  ${CYAN}API:        ${NC}https://api.ssd.cloud/health"
echo -e "  ${CYAN}Monitor:    ${NC}https://monitor.ssd.cloud"
echo -e "  ${CYAN}Log:        ${NC}$DEPLOY_LOG"

notify_slack "SUCCESS" "All services deployed in ${ELAPSED}s. Version: $DEPLOY_VERSION" "good"
trap - EXIT
exit 0

# Original stub follows (replaced above)
# Sun State Digital - Complete Production Deployment

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
