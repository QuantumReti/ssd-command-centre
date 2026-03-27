#!/bin/bash
# =============================================================================
# Sun State Digital — Deploy Quantum Backend API
# Builds Python FastAPI service, runs migrations, updates ECS
# Usage: ./deploy-quantum.sh [--tag v1.8.3] [--skip-migrations]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="quantum-api"
ECR_REGISTRY="${ECR_REGISTRY:-123456789.dkr.ecr.ap-southeast-2.amazonaws.com}"
ECR_REPO="${ECR_REGISTRY}/ssd/quantum-api"
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
ECS_CLUSTER="${ECS_CLUSTER:-ssd-prod-cluster}"
ECS_SERVICE="${ECS_SERVICE:-ssd-quantum-api}"
HEALTH_URL="${HEALTH_URL:-https://quantum.ssd.cloud/health}"
BUILD_CONTEXT="${SCRIPT_DIR}/services/quantum-api"
TAG="${TAG:-$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest")}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $1${NC}"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $1${NC}"; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}══════ $1 ══════${NC}\n"; }

SKIP_BUILD=false
SKIP_MIGRATIONS=false
for arg in "$@"; do
  case $arg in
    --tag=*)            TAG="${arg#*=}" ;;
    --skip-build)       SKIP_BUILD=true ;;
    --skip-migrations)  SKIP_MIGRATIONS=true ;;
  esac
done

DEPLOY_START=$(date +%s)
echo -e "\n${BOLD}${BLUE}  QUANTUM BACKEND API DEPLOYMENT — Tag: ${TAG}${NC}\n"

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
    docker-compose -f "${SCRIPT_DIR}/docker-compose.yml" build quantum-api
  else
    log "Building Quantum API image..."
    log "Context: $BUILD_CONTEXT"
    log "Tag: ${ECR_REPO}:${TAG}"

    docker build \
      --tag "${ECR_REPO}:${TAG}" \
      --tag "${ECR_REPO}:latest" \
      --build-arg PYTHON_ENV=production \
      --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --build-arg GIT_COMMIT="${TAG}" \
      --file "${BUILD_CONTEXT}/Dockerfile" \
      "$BUILD_CONTEXT"

    success "Image built: ${ECR_REPO}:${TAG}"

    # Verify image runs
    log "Running quick container test..."
    docker run --rm --entrypoint python \
      "${ECR_REPO}:${TAG}" \
      -c "import fastapi; import uvicorn; print('OK')" \
      && success "Container test passed" \
      || warn "Container test failed — check Dockerfile"
  fi
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
header "DATABASE MIGRATIONS"
# =============================================================================

if [[ "$SKIP_MIGRATIONS" == "false" ]]; then
  log "Running database migrations..."
  cd "$SCRIPT_DIR"
  [[ -f ".env" ]] && source .env

  # Check if running on compose or ECS
  if docker ps --format '{{.Names}}' | grep -q "quantum-api\|postgres"; then
    log "Running Alembic migrations via docker-compose..."

    # First, take a backup
    log "Taking pre-migration database backup..."
    BACKUP_FILE="/tmp/ssd-pre-migration-$(date +%Y%m%d-%H%M%S).sql"
    docker exec postgres pg_dump \
      -U ssd_user \
      -d ssd_quantum \
      --format=custom \
      > "$BACKUP_FILE" 2>/dev/null && \
      success "Pre-migration backup: $BACKUP_FILE" || \
      warn "Could not backup quantum DB — check if it exists"

    # Show current migration state
    log "Current migration state:"
    docker-compose -f "${SCRIPT_DIR}/docker-compose.yml" run --rm \
      -e DATABASE_URL="${DATABASE_URL:-}" \
      quantum-api python -m alembic current 2>/dev/null || warn "Could not check current migration"

    # Run migrations
    docker-compose -f "${SCRIPT_DIR}/docker-compose.yml" run --rm \
      -e DATABASE_URL="${DATABASE_URL:-}" \
      quantum-api python -m alembic upgrade head

    success "Migrations applied"

    # Show final state
    log "Final migration state:"
    docker-compose -f "${SCRIPT_DIR}/docker-compose.yml" run --rm \
      -e DATABASE_URL="${DATABASE_URL:-}" \
      quantum-api python -m alembic current 2>/dev/null || true

  else
    warn "Docker containers not running — run migrations manually:"
    warn "  docker-compose run --rm quantum-api python -m alembic upgrade head"
  fi
else
  warn "Skipping migrations (--skip-migrations)"
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

  success "ECS service update initiated"

  log "Waiting for ECS stabilization..."
  aws ecs wait services-stable \
    --cluster "$ECS_CLUSTER" \
    --services "$ECS_SERVICE" \
    --region "$AWS_REGION" \
    && success "ECS service stable" \
    || warn "Service still deploying — check console"

else
  log "Using docker-compose deployment..."
  cd "$SCRIPT_DIR"
  docker-compose pull quantum-api
  docker-compose up -d --no-deps quantum-api
  sleep 10
  success "Quantum API restarted"
fi

# =============================================================================
header "HEALTH CHECK"
# =============================================================================

log "Verifying health endpoint: $HEALTH_URL"
RETRIES=15
HEALTH_OK=false

for i in $(seq 1 $RETRIES); do
  RESPONSE=$(curl -sf "$HEALTH_URL" 2>/dev/null || echo "")
  if [[ -n "$RESPONSE" ]]; then
    STATUS=$(echo "$RESPONSE" | jq -r '.status // "unknown"' 2>/dev/null || echo "unknown")
    VERSION=$(echo "$RESPONSE" | jq -r '.version // "unknown"' 2>/dev/null || echo "unknown")
    DB_STATUS=$(echo "$RESPONSE" | jq -r '.database // "unknown"' 2>/dev/null || echo "unknown")

    if [[ "$STATUS" == "ok" ]] || [[ "$STATUS" == "healthy" ]]; then
      success "Health check passed"
      log "  Status:   $STATUS"
      log "  Version:  $VERSION"
      log "  Database: $DB_STATUS"
      HEALTH_OK=true
      break
    fi
  fi
  log "Attempt $i/$RETRIES — waiting 10s..."
  sleep 10
done

# Verify API endpoints
if [[ "$HEALTH_OK" == "true" ]]; then
  log "Testing key endpoints..."
  BASE="${HEALTH_URL%/health}"

  LEAD_RESP=$(curl -sf "${BASE}/api/v1/leads/qualify" \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-API-Key: ${OPENCLAW_API_KEY:-test}" \
    -d '{"test": true}' 2>/dev/null || echo "")
  [[ -n "$LEAD_RESP" ]] && success "Lead qualification endpoint OK" || warn "Lead endpoint not responding"
fi

ELAPSED=$(( $(date +%s) - DEPLOY_START ))

if [[ "$HEALTH_OK" == "true" ]]; then
  echo ""
  success "Quantum Backend API deployed in ${ELAPSED}s!"
  echo -e "  ${CYAN}Health:    ${NC}${HEALTH_URL}"
  echo -e "  ${CYAN}API Docs:  ${NC}${HEALTH_URL%/health}/docs"
  echo -e "  ${CYAN}Image:     ${NC}${ECR_REPO}:${TAG}"
else
  warn "Quantum API may not be healthy — check logs:"
  warn "  docker logs quantum-api --tail=50"
  exit 1
fi
