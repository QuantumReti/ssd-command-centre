#!/bin/bash
# =============================================================================
# Sun State Digital — Backup and Restore Script
# Backs up PostgreSQL, Redis, nginx config, env files to S3
# Usage:
#   ./backup-restore.sh backup [--quiet]
#   ./backup-restore.sh restore [--date 20260318] [--db-only]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

# --- Configuration ---
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
S3_BUCKET="${S3_BACKUP_BUCKET:-ssd-prod-backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DATE_PREFIX=$(date +%Y%m%d)
BACKUP_DIR="/tmp/ssd-backup-${TIMESTAMP}"
LOG_FILE="/var/log/ssd/backup.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

QUIET=false
DB_ONLY=false
RESTORE_DATE=""
ACTION="${1:-backup}"

shift 2>/dev/null || true
for arg in "$@"; do
  case $arg in
    --quiet)    QUIET=true ;;
    --db-only)  DB_ONLY=true ;;
    --date=*)   RESTORE_DATE="${arg#*=}" ;;
  esac
done

mkdir -p "$(dirname "$LOG_FILE")"
[[ "$QUIET" == "false" ]] && exec > >(tee -a "$LOG_FILE") 2>&1 || exec >> "$LOG_FILE" 2>&1

log()     { [[ "$QUIET" == "false" ]] && echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1" || true; }
success() { [[ "$QUIET" == "false" ]] && echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $1${NC}" || echo "[$(date '+%H:%M:%S')] OK: $1" >> "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $1${NC}"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $1${NC}"; exit 1; }
header()  { [[ "$QUIET" == "false" ]] && echo -e "\n${BOLD}${BLUE}══════ $1 ══════${NC}\n" || true; }

# =============================================================================
backup() {
  header "SSD BACKUP — ${TIMESTAMP}"
  log "S3 Bucket: s3://${S3_BUCKET}"
  log "Retention: ${RETENTION_DAYS} days"

  mkdir -p "$BACKUP_DIR"
  BACKUP_SIZE=0
  BACKUP_FILES=()

  # --- PostgreSQL Backup ---
  header "POSTGRESQL BACKUP"

  # Get list of databases
  DBS=$(docker exec postgres psql -U ssd_user -d ssd_production \
    -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';" \
    -t 2>/dev/null | tr -d ' ' | grep -v '^$' || echo "ssd_production ssd_quantum")

  for DB in $DBS; do
    log "Backing up database: $DB"
    DUMP_FILE="${BACKUP_DIR}/db-${DB}-${TIMESTAMP}.dump"

    docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-}" postgres pg_dump \
      --username=ssd_user \
      --format=custom \
      --compress=9 \
      --file="/tmp/backup-${DB}.dump" \
      "$DB" 2>/dev/null && \
    docker cp "postgres:/tmp/backup-${DB}.dump" "$DUMP_FILE" && \
    docker exec postgres rm -f "/tmp/backup-${DB}.dump"

    if [[ -f "$DUMP_FILE" ]]; then
      SIZE=$(du -sh "$DUMP_FILE" | cut -f1)
      success "Database $DB backed up ($SIZE)"
      BACKUP_FILES+=("$DUMP_FILE")
    else
      warn "Could not backup database: $DB"
    fi
  done

  # --- Redis Backup ---
  header "REDIS BACKUP"
  log "Triggering Redis BGSAVE..."
  docker exec redis redis-cli -a "${REDIS_PASSWORD:-}" BGSAVE 2>/dev/null || warn "Redis BGSAVE failed"
  sleep 3

  REDIS_DUMP="${BACKUP_DIR}/redis-dump-${TIMESTAMP}.rdb"
  docker cp redis:/data/dump.rdb "$REDIS_DUMP" 2>/dev/null && \
    success "Redis dump copied ($(du -sh "$REDIS_DUMP" | cut -f1))" && \
    BACKUP_FILES+=("$REDIS_DUMP") || \
    warn "Redis dump not available — may not have data yet"

  # --- Config Backup ---
  if [[ "$DB_ONLY" == "false" ]]; then
    header "CONFIG BACKUP"

    # Nginx config
    NGINX_ARCHIVE="${BACKUP_DIR}/nginx-config-${TIMESTAMP}.tar.gz"
    tar -czf "$NGINX_ARCHIVE" \
      "${SCRIPT_DIR}/nginx.conf" \
      /etc/nginx/nginx.conf \
      /etc/letsencrypt/ \
      2>/dev/null || tar -czf "$NGINX_ARCHIVE" "${SCRIPT_DIR}/nginx.conf" 2>/dev/null
    success "Nginx config archived"
    BACKUP_FILES+=("$NGINX_ARCHIVE")

    # Application config (env file - encrypted)
    if [[ -f "${SCRIPT_DIR}/.env" ]]; then
      ENV_ARCHIVE="${BACKUP_DIR}/env-config-${TIMESTAMP}.tar.gz.enc"
      tar -czf - "${SCRIPT_DIR}/.env" | \
        openssl enc -aes-256-cbc -pbkdf2 \
          -pass pass:"${BACKUP_ENCRYPTION_KEY:-changeme-set-this-in-env}" \
          -out "$ENV_ARCHIVE" 2>/dev/null && \
        success "Env config encrypted and archived" && \
        BACKUP_FILES+=("$ENV_ARCHIVE") || \
        warn "Could not encrypt env backup — storing unencrypted (configure BACKUP_ENCRYPTION_KEY)"
    fi

    # Docker compose files
    COMPOSE_ARCHIVE="${BACKUP_DIR}/compose-config-${TIMESTAMP}.tar.gz"
    tar -czf "$COMPOSE_ARCHIVE" \
      "${SCRIPT_DIR}/docker-compose.yml" \
      "${SCRIPT_DIR}/"*.json \
      2>/dev/null || true
    BACKUP_FILES+=("$COMPOSE_ARCHIVE")
    success "Compose config archived"
  fi

  # --- Upload to S3 ---
  header "UPLOADING TO S3"

  S3_PREFIX="backups/${DATE_PREFIX}/${TIMESTAMP}"
  UPLOAD_COUNT=0

  for FILE in "${BACKUP_FILES[@]}"; do
    if [[ -f "$FILE" ]]; then
      FILENAME=$(basename "$FILE")
      S3_KEY="${S3_PREFIX}/${FILENAME}"
      log "Uploading ${FILENAME}..."

      aws s3 cp "$FILE" "s3://${S3_BUCKET}/${S3_KEY}" \
        --region "$AWS_REGION" \
        --storage-class STANDARD_IA \
        --metadata "timestamp=${TIMESTAMP},environment=production,server=13.237.5.80" \
        && success "Uploaded: $S3_KEY" && UPLOAD_COUNT=$((UPLOAD_COUNT + 1)) \
        || warn "Failed to upload: $FILENAME"
    fi
  done

  # Create a manifest file
  MANIFEST="${BACKUP_DIR}/manifest.json"
  cat > "$MANIFEST" << EOF
{
  "timestamp": "${TIMESTAMP}",
  "date": "${DATE_PREFIX}",
  "server": "13.237.5.80",
  "environment": "production",
  "files": $(printf '"%s"\n' "${BACKUP_FILES[@]##*/}" | jq -s '.'),
  "databases": $(echo "$DBS" | tr ' ' '\n' | jq -R . | jq -s '.'),
  "retention_days": ${RETENTION_DAYS}
}
EOF
  aws s3 cp "$MANIFEST" "s3://${S3_BUCKET}/${S3_PREFIX}/manifest.json" \
    --region "$AWS_REGION" > /dev/null 2>&1 || true

  # --- Cleanup Old Backups ---
  header "CLEANUP"
  log "Removing backups older than ${RETENTION_DAYS} days..."
  CUTOFF_DATE=$(date -d "${RETENTION_DAYS} days ago" +%Y%m%d 2>/dev/null || \
                date -v-${RETENTION_DAYS}d +%Y%m%d 2>/dev/null || \
                echo "19700101")

  aws s3 ls "s3://${S3_BUCKET}/backups/" --region "$AWS_REGION" 2>/dev/null | \
    grep "PRE " | \
    awk '{print $2}' | \
    tr -d '/' | \
    while read -r dir; do
      if [[ "$dir" < "$CUTOFF_DATE" ]]; then
        log "Removing old backup: $dir"
        aws s3 rm "s3://${S3_BUCKET}/backups/${dir}/" \
          --recursive \
          --region "$AWS_REGION" > /dev/null 2>&1 || warn "Could not remove $dir"
      fi
    done
  success "Old backups cleaned up"

  # --- Local cleanup ---
  rm -rf "$BACKUP_DIR"
  success "Local temp files cleaned up"

  # --- Summary ---
  echo ""
  success "Backup complete! Uploaded ${UPLOAD_COUNT}/${#BACKUP_FILES[@]} files"
  echo -e "  ${CYAN}S3 Path:${NC} s3://${S3_BUCKET}/${S3_PREFIX}/"
  echo -e "  ${CYAN}Time:${NC}    $(date '+%Y-%m-%d %H:%M:%S')"
  echo -e "  ${CYAN}Logs:${NC}    ${LOG_FILE}"
}

# =============================================================================
restore() {
  header "SSD RESTORE"

  if [[ -z "$RESTORE_DATE" ]]; then
    log "Available backups:"
    aws s3 ls "s3://${S3_BUCKET}/backups/" \
      --region "$AWS_REGION" | \
      grep "PRE " | \
      awk '{print $2}' | \
      tr -d '/' | \
      sort -r | \
      head -10
    echo ""
    read -r -p "Enter backup date (YYYYMMDD): " RESTORE_DATE
  fi

  log "Looking for backups from: $RESTORE_DATE"

  # List available timestamps for this date
  TIMESTAMPS=$(aws s3 ls "s3://${S3_BUCKET}/backups/${RESTORE_DATE}/" \
    --region "$AWS_REGION" 2>/dev/null | \
    grep "PRE " | awk '{print $2}' | tr -d '/' || echo "")

  if [[ -z "$TIMESTAMPS" ]]; then
    error "No backups found for date: $RESTORE_DATE"
  fi

  log "Available restore points:"
  echo "$TIMESTAMPS"
  echo ""
  read -r -p "Enter timestamp to restore (or 'latest'): " RESTORE_TS

  if [[ "$RESTORE_TS" == "latest" ]]; then
    RESTORE_TS=$(echo "$TIMESTAMPS" | tail -1)
  fi

  log "Restoring from: s3://${S3_BUCKET}/backups/${RESTORE_DATE}/${RESTORE_TS}/"

  mkdir -p "$BACKUP_DIR"

  # Download backup files
  log "Downloading backup files..."
  aws s3 cp "s3://${S3_BUCKET}/backups/${RESTORE_DATE}/${RESTORE_TS}/" \
    "$BACKUP_DIR/" \
    --recursive \
    --region "$AWS_REGION"

  success "Backup files downloaded to $BACKUP_DIR"

  # --- Restore PostgreSQL ---
  header "RESTORING POSTGRESQL"

  echo ""
  warn "WARNING: This will overwrite existing database data!"
  read -r -p "Type 'yes' to continue: " CONFIRM
  [[ "$CONFIRM" != "yes" ]] && { log "Restore cancelled"; exit 0; }

  for DUMP_FILE in "${BACKUP_DIR}"/db-*.dump; do
    if [[ -f "$DUMP_FILE" ]]; then
      # Extract database name from filename
      DB_NAME=$(basename "$DUMP_FILE" | sed 's/db-\(.*\)-[0-9]*.*.dump/\1/')
      log "Restoring database: $DB_NAME from $(basename $DUMP_FILE)"

      # Copy dump to container
      docker cp "$DUMP_FILE" "postgres:/tmp/restore.dump"

      # Drop and recreate database
      docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-}" postgres psql \
        -U postgres \
        -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}';" \
        -c "DROP DATABASE IF EXISTS ${DB_NAME};" \
        -c "CREATE DATABASE ${DB_NAME} OWNER ssd_user;" \
        2>/dev/null

      # Restore
      docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-}" postgres pg_restore \
        --username=ssd_user \
        --dbname="$DB_NAME" \
        --no-owner \
        --role=ssd_user \
        "/tmp/restore.dump" \
        2>/dev/null && success "Database $DB_NAME restored" || warn "Restore had warnings"

      docker exec postgres rm -f /tmp/restore.dump
    fi
  done

  # --- Restore Redis (optional) ---
  if [[ "$DB_ONLY" == "false" ]]; then
    REDIS_DUMP="${BACKUP_DIR}/redis-dump-"*.rdb
    if compgen -G "$REDIS_DUMP" > /dev/null 2>&1; then
      REDIS_FILE=$(ls "${BACKUP_DIR}"/redis-dump-*.rdb | head -1)
      log "Restoring Redis from: $(basename $REDIS_FILE)"
      docker stop redis
      docker cp "$REDIS_FILE" redis:/data/dump.rdb
      docker start redis
      sleep 3
      success "Redis restored"
    fi
  fi

  # --- Cleanup ---
  rm -rf "$BACKUP_DIR"

  echo ""
  success "Restore complete!"
  echo -e "  ${CYAN}Restored from:${NC} ${RESTORE_DATE}/${RESTORE_TS}"
  warn "Run ./verify-deployment.sh to confirm everything is working"
}

# =============================================================================
list_backups() {
  header "AVAILABLE BACKUPS"
  echo ""
  aws s3 ls "s3://${S3_BUCKET}/backups/" \
    --region "$AWS_REGION" | \
    grep "PRE " | \
    awk '{print $2}' | \
    tr -d '/' | \
    sort -r
}

# =============================================================================
case "$ACTION" in
  backup)        backup ;;
  restore)       restore ;;
  list)          list_backups ;;
  *)
    echo "Usage: $0 {backup|restore|list} [options]"
    echo ""
    echo "Options:"
    echo "  backup  [--quiet] [--db-only]"
    echo "  restore [--date YYYYMMDD] [--db-only]"
    echo "  list"
    exit 1
    ;;
esac
