#!/bin/bash
# =============================================================================
# Sun State Digital — Deploy Blog Frontend (Next.js)
# Builds Next.js app, pushes to ECR, updates ECS service
# Usage: ./deploy-blog.sh [--tag v1.2.1] [--skip-build]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="blog-frontend"
ECR_REGISTRY="${ECR_REGISTRY:-123456789.dkr.ecr.ap-southeast-2.amazonaws.com}"
ECR_REPO="${ECR_REGISTRY}/ssd/blog-frontend"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
ECS_CLUSTER="${ECS_CLUSTER:-ssd-prod-cluster}"
ECS_SERVICE="${ECS_SERVICE:-ssd-blog-frontend}"
HEALTH_URL="${HEALTH_URL:-https://blog.ssd.cloud}"
BUILD_CONTEXT="${SCRIPT_DIR}/services/blog-frontend"
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
    --tag=*)      TAG="${arg#*=}" ;;
    --skip-build) SKIP_BUILD=true ;;
  esac
done

DEPLOY_START=$(date +%s)
echo -e "\n${BOLD}${BLUE}  BLOG FRONTEND DEPLOYMENT — Tag: ${TAG}${NC}\n"

# =============================================================================
header "ECR LOGIN"
# =============================================================================

log "Authenticating with ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"
success "ECR authenticated"

# =============================================================================
header "BUILD NEXT.JS APP"
# =============================================================================

if [[ "$SKIP_BUILD" == "false" ]]; then
  if [[ ! -d "$BUILD_CONTEXT" ]]; then
    warn "Build context not found at $BUILD_CONTEXT"
    log "Using docker-compose build..."
    docker-compose -f "${SCRIPT_DIR}/docker-compose.yml" build blog-frontend
  else
    log "Building Next.js Blog Frontend..."

    # Check for package.json
    [[ -f "${BUILD_CONTEXT}/package.json" ]] || error "No package.json found in $BUILD_CONTEXT"

    # Build the Docker image with standalone output
    log "Building Docker image with Next.js standalone output..."
    docker build \
      --tag "${ECR_REPO}:${TAG}" \
      --tag "${ECR_REPO}:latest" \
      --build-arg NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL:-https://api.ssd.cloud}" \
      --build-arg NEXT_PUBLIC_SITE_URL="${NEXT_PUBLIC_SITE_URL:-https://blog.ssd.cloud}" \
      --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --build-arg GIT_COMMIT="${TAG}" \
      --file "${BUILD_CONTEXT}/Dockerfile" \
      "$BUILD_CONTEXT"

    success "Blog frontend image built: ${ECR_REPO}:${TAG}"

    # Show image size
    IMAGE_SIZE=$(docker image inspect "${ECR_REPO}:${TAG}" --format='{{.Size}}' | \
      awk '{printf "%.0f MB", $1/1024/1024}')
    log "Image size: $IMAGE_SIZE"
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

  # Also upload static assets to S3 for CloudFront
  if aws s3 ls "s3://ssd-prod-static" > /dev/null 2>&1; then
    log "Syncing static assets to S3..."
    CONTAINER_ID=$(docker create "${ECR_REPO}:${TAG}")
    docker cp "${CONTAINER_ID}:/app/.next/static" /tmp/next-static 2>/dev/null || true
    docker rm "$CONTAINER_ID" > /dev/null 2>/dev/null || true

    if [[ -d "/tmp/next-static" ]]; then
      aws s3 sync /tmp/next-static "s3://ssd-prod-static/_next/static" \
        --cache-control "public, max-age=31536000, immutable" \
        --region "$AWS_REGION" \
        && success "Static assets synced to S3/CloudFront" \
        || warn "S3 sync failed"
      rm -rf /tmp/next-static
    fi
  fi
fi

# =============================================================================
header "UPDATE SERVICE"
# =============================================================================

if aws ecs describe-services \
     --cluster "$ECS_CLUSTER" \
     --services "$ECS_SERVICE" \
     --region "$AWS_REGION" \
     --query 'services[0].status' \
     --output text 2>/dev/null | grep -q "ACTIVE"; then

  log "Updating ECS service: ${ECS_SERVICE}..."

  CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" \
    --region "$AWS_REGION" \
    --query 'services[0].taskDefinition' \
    --output text)

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

  aws ecs update-service \
    --cluster "$ECS_CLUSTER" \
    --service "$ECS_SERVICE" \
    --task-definition "$NEW_TASK_DEF" \
    --region "$AWS_REGION" \
    --force-new-deployment > /dev/null

  success "ECS update initiated — blue/green deployment in progress"

  log "Waiting for ECS to stabilize..."
  aws ecs wait services-stable \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" \
    --region "$AWS_REGION" \
    && success "ECS service stable" \
    || warn "Service still deploying"

  # Invalidate CloudFront cache
  CF_DIST_ID=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Origins.Items[0].DomainName, 'ssd-prod-alb')].Id" \
    --output text 2>/dev/null || echo "")

  if [[ -n "$CF_DIST_ID" ]]; then
    log "Invalidating CloudFront cache..."
    aws cloudfront create-invalidation \
      --distribution-id "$CF_DIST_ID" \
      --paths "/*" > /dev/null
    success "CloudFront cache invalidated"
  fi

else
  log "Using docker-compose deployment..."
  cd "$SCRIPT_DIR"
  docker-compose pull blog-frontend
  docker-compose up -d --no-deps blog-frontend
  success "Blog frontend restarted"
fi

# =============================================================================
header "VERIFY DEPLOYMENT"
# =============================================================================

log "Verifying blog is serving content: $HEALTH_URL"
RETRIES=12
DEPLOY_OK=false

for i in $(seq 1 $RETRIES); do
  HTTP_CODE=$(curl -so /dev/null -w "%{http_code}" "$HEALTH_URL" 2>/dev/null || echo "0")
  if [[ "$HTTP_CODE" == "200" ]]; then
    success "Blog responding with HTTP 200"
    DEPLOY_OK=true
    break
  elif [[ "$HTTP_CODE" == "301" ]] || [[ "$HTTP_CODE" == "302" ]]; then
    success "Blog responding with redirect $HTTP_CODE"
    DEPLOY_OK=true
    break
  fi
  log "Attempt $i/$RETRIES — HTTP $HTTP_CODE, waiting 10s..."
  sleep 10
done

# Check page title
if [[ "$DEPLOY_OK" == "true" ]]; then
  PAGE_TITLE=$(curl -sf "$HEALTH_URL" 2>/dev/null | \
    grep -o '<title>[^<]*</title>' | \
    sed 's/<[^>]*>//g' || echo "Unknown")
  log "Page title: $PAGE_TITLE"
fi

ELAPSED=$(( $(date +%s) - DEPLOY_START ))

if [[ "$DEPLOY_OK" == "true" ]]; then
  success "Blog Frontend deployed in ${ELAPSED}s!"
  echo -e "  ${CYAN}URL:    ${NC}${HEALTH_URL}"
  echo -e "  ${CYAN}Image:  ${NC}${ECR_REPO}:${TAG}"
else
  warn "Blog may not be serving correctly — check logs:"
  warn "  docker logs blog-frontend --tail=50"
fi
