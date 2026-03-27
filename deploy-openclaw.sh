#!/bin/bash
# =============================================================================
# Sun State Digital — Deploy OpenClaw Gateway Service
# Builds, pushes to ECR, updates ECS, verifies health
# Usage: ./deploy-openclaw.sh [--tag v2.1.5] [--skip-build]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="openclaw-gateway"
ECR_REGISTRY="${ECR_REGISTRY:-123456789.dkr.ecr.ap-southeast-2.amazonaws.com}"
ECR_REPO="${ECR_REGISTRY}/ssd/openclaw-gateway"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
ECS_CLUSTER="${ECS_CLUSTER:-ssd-prod-cluster}"
ECS_SERVICE="${ECS_SERVICE:-ssd-openclaw-gateway}"
HEALTH_URL="${HEALTH_URL:-https://api.ssd.cloud/health}"
BUILD_CONTEXT="${SCRIPT_DIR}/services/openclaw-gateway"
TAG="${TAG:-$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest")}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $1${NC}"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $1${NC}"; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}══════ $1 ══════${NC}\n"; }

SKIP_BUILD=false
for arg in "$@"; do
  case $arg in
    --tag=*)        TAG="${arg#*=}" ;;
    --skip-build)   SKIP_BUILD=true ;;
  esac
done

DEPLOY_START=$(date +%s)
echo -e "\n${BOLD}${BLUE}  OPENCLAW GATEWAY DEPLOYMENT — Tag: ${TAG}${NC}\n"

# =============================================================================
header "ECR LOGIN"
# =============================================================================

log "Authenticating with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"
success "ECR authenticated"

# =============================================================================
header "BUILD DOCKER IMAGE"
# =============================================================================

if [[ "$SKIP_BUILD" == "false" ]]; then
  if [[ ! -d "$BUILD_CONTEXT" ]]; then
    warn "Build context not found at $BUILD_CONTEXT"
    warn "Using docker-compose build instead"
    docker-compose -f "${SCRIPT_DIR}/docker-compose.yml" build openclaw-gateway
  else
    log "Building OpenClaw Gateway image..."
    log "Context: $BUILD_CONTEXT"
    log "Tag: ${ECR_REPO}:${TAG}"

    docker build \
      --tag "${ECR_REPO}:${TAG}" \
      --tag "${ECR_REPO}:latest" \
      --build-arg NODE_ENV=production \
      --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --build-arg GIT_COMMIT="${TAG}" \
      --file "${BUILD_CONTEXT}/Dockerfile" \
      "$BUILD_CONTEXT"

    success "Image built: ${ECR_REPO}:${TAG}"

    log "Image size:"
    docker image inspect "${ECR_REPO}:${TAG}" --format='  {{.Size}} bytes' | \
      awk '{printf "  %.1f MB\n", $1/1024/1024}'
  fi
else
  warn "Skipping build (--skip-build)"
fi

# =============================================================================
header "PUSH TO ECR"
# =============================================================================

if [[ "$SKIP_BUILD" == "false" ]]; then
  log "Pushing ${ECR_REPO}:${TAG}..."
  docker push "${ECR_REPO}:${TAG}"
  docker push "${ECR_REPO}:latest"
  success "Images pushed to ECR"
fi

# =============================================================================
header "UPDATE ECS SERVICE"
# =============================================================================

# Check if running on ECS or docker-compose
if aws ecs describe-services \
     --cluster "$ECS_CLUSTER" \
     --services "$ECS_SERVICE" \
     --region "$AWS_REGION" \
     --query 'services[0].status' \
     --output text 2>/dev/null | grep -q "ACTIVE"; then

  log "Updating ECS service: ${ECS_SERVICE}..."

  # Get current task definition
  CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" \
    --region "$AWS_REGION" \
    --query 'services[0].taskDefinition' \
    --output text)
  log "Current task definition: $CURRENT_TASK_DEF"

  # Register new task definition with updated image
  NEW_TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition "$CURRENT_TASK_DEF" \
    --region "$AWS_REGION" \
    --query 'taskDefinition' \
    --output json | \
    jq --arg IMAGE "${ECR_REPO}:${TAG}" \
       '.containerDefinitions[0].image = $IMAGE | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' | \
    aws ecs register-task-definition \
      --region "$AWS_REGION" \
      --cli-input-json /dev/stdin \
      --query 'taskDefinition.taskDefinitionArn' \
      --output text)

  log "New task definition: $NEW_TASK_DEF"

  # Update the service
  aws ecs update-service \
    --cluster "$ECS_CLUSTER" \
    --service "$ECS_SERVICE" \
    --task-definition "$NEW_TASK_DEF" \
    --region "$AWS_REGION" \
    --force-new-deployment \
    --query 'service.deployments[0].status' \
    --output text

  success "ECS service update initiated"

  log "Waiting for ECS service to stabilize (up to 5 minutes)..."
  aws ecs wait services-stable \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" \
    --region "$AWS_REGION" \
    && success "ECS service stable" \
    || warn "Service may still be deploying — check ECS console"

else
  log "ECS service not found or not active — using docker-compose..."
  cd "$SCRIPT_DIR"
  [[ -f ".env" ]] && source .env
  docker-compose pull openclaw-gateway
  docker-compose up -d --no-deps openclaw-gateway
  success "OpenClaw Gateway restarted via docker-compose"
fi

# =============================================================================
header "HEALTH CHECK"
# =============================================================================

log "Verifying health endpoint: $HEALTH_URL"
RETRIES=12
HEALTH_OK=false

for i in $(seq 1 $RETRIES); do
  RESPONSE=$(curl -sf "$HEALTH_URL" 2>/dev/null || echo "")
  if [[ -n "$RESPONSE" ]]; then
    STATUS=$(echo "$RESPONSE" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
    VERSION=$(echo "$RESPONSE" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")

    if [[ "$STATUS" == "ok" ]] || [[ "$STATUS" == "healthy" ]]; then
      success "Health check passed — Status: $STATUS, Version: $VERSION"
      HEALTH_OK=true
      break
    fi
  fi

  log "Attempt $i/$RETRIES — waiting 10 seconds..."
  sleep 10
done

ELAPSED=$(( $(date +%s) - DEPLOY_START ))

if [[ "$HEALTH_OK" == "true" ]]; then
  echo ""
  success "OpenClaw Gateway deployed successfully in ${ELAPSED}s!"
  echo -e "  ${CYAN}Health:   ${NC}${HEALTH_URL}"
  echo -e "  ${CYAN}Image:    ${NC}${ECR_REPO}:${TAG}"
  echo -e "  ${CYAN}Endpoint: ${NC}https://api.ssd.cloud"
else
  warn "Health check did not pass after ${ELAPSED}s"
  warn "Check logs: docker logs openclaw-gateway --tail=50"
  warn "Or ECS: aws ecs describe-services --cluster $ECS_CLUSTER --services $ECS_SERVICE --region $AWS_REGION"
  exit 1
fi
