#!/bin/bash
# =============================================================================
# Sun State Digital — Deploy Exact Replica to New AWS EC2 Instance
# Creates a complete copy of production on a new server
# Usage: ./deploy-exact-replica.sh [--region ap-southeast-2] [--env staging]
# =============================================================================

set -euo pipefail

# --- Configuration ---
AWS_REGION="${AWS_REGION:-ap-southeast-2}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
AMI_ID="${AMI_ID:-ami-0310483fb2b488153}"  # Ubuntu 22.04 LTS ap-southeast-2
KEY_NAME="${KEY_NAME:-ssd-prod-key}"
DEPLOY_ENV="${DEPLOY_ENV:-staging}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✓ $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠ $1${NC}"; }
error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ✗ $1${NC}"; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}══════ $1 ══════${NC}\n"; }

for arg in "$@"; do
  case $arg in
    --region=*) AWS_REGION="${arg#*=}" ;;
    --env=*)    DEPLOY_ENV="${arg#*=}" ;;
    --type=*)   INSTANCE_TYPE="${arg#*=}" ;;
  esac
done

echo -e "\n${BOLD}${BLUE}  SSD EXACT REPLICA DEPLOYMENT${NC}"
echo -e "  Environment: ${DEPLOY_ENV} | Region: ${AWS_REGION} | Type: ${INSTANCE_TYPE}\n"

# =============================================================================
header "STEP 1: CREATE SECURITY GROUP"
# =============================================================================

log "Creating security group for replica..."
SG_ID=$(aws ec2 create-security-group \
  --group-name "ssd-${DEPLOY_ENV}-sg-$(date +%s)" \
  --description "SSD ${DEPLOY_ENV} replica security group" \
  --region "$AWS_REGION" \
  --query 'GroupId' \
  --output text)

log "Security group created: $SG_ID"
log "Adding inbound rules..."

# SSH
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 22 \
  --cidr "0.0.0.0/0" \
  --region "$AWS_REGION"

# HTTP
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 80 \
  --cidr "0.0.0.0/0" \
  --region "$AWS_REGION"

# HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 443 \
  --cidr "0.0.0.0/0" \
  --region "$AWS_REGION"

success "Security group $SG_ID configured"

# =============================================================================
header "STEP 2: LAUNCH EC2 INSTANCE"
# =============================================================================

log "Preparing user data script..."
cat > /tmp/ssd-userdata.sh << 'USERDATA'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# Update system
apt-get update -y
apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com | bash
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Install docker-compose
curl -SL "https://github.com/docker/compose/releases/download/v2.23.3/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install utilities
apt-get install -y nginx certbot python3-certbot-nginx \
  postgresql-client redis-tools awscli jq htop tmux git \
  fail2ban ufw

# Configure swap (4GB)
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl vm.swappiness=10
echo 'vm.swappiness=10' >> /etc/sysctl.conf

# Configure UFW
ufw --force enable
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp

# Increase file limits
cat >> /etc/security/limits.conf << 'EOF'
ubuntu soft nofile 65536
ubuntu hard nofile 65536
EOF

# Create app directory
mkdir -p /opt/ssd /var/log/ssd
chown -R ubuntu:ubuntu /opt/ssd /var/log/ssd

# Signal completion
echo "USER_DATA_COMPLETE" > /tmp/user-data-done
USERDATA

USER_DATA_B64=$(base64 < /tmp/ssd-userdata.sh | tr -d '\n')

log "Launching EC2 instance (${INSTANCE_TYPE} in ${AWS_REGION})..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --user-data "$USER_DATA_B64" \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":50,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications "[{\"ResourceType\":\"instance\",\"Tags\":[{\"Key\":\"Name\",\"Value\":\"ssd-${DEPLOY_ENV}-replica\"},{\"Key\":\"Project\",\"Value\":\"ssd-platform\"},{\"Key\":\"Environment\",\"Value\":\"${DEPLOY_ENV}\"},{\"Key\":\"Owner\",\"Value\":\"joshua@sunstatedigital.com.au\"}]}]" \
  --region "$AWS_REGION" \
  --query 'Instances[0].InstanceId' \
  --output text)

success "Instance launched: $INSTANCE_ID"

# =============================================================================
header "STEP 3: WAIT FOR INSTANCE"
# =============================================================================

log "Waiting for instance to be running..."
aws ec2 wait instance-running \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION"
success "Instance running"

PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

log "Public IP: $PUBLIC_IP"
log "Waiting for SSH to become available (up to 3 minutes)..."

for i in $(seq 1 36); do
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
    -i ~/.ssh/ssd_prod ubuntu@"$PUBLIC_IP" "echo ready" 2>/dev/null && break
  [[ $i -eq 36 ]] && error "SSH not available after 3 minutes"
  sleep 5
done
success "SSH available at $PUBLIC_IP"

log "Waiting for user-data to complete (Docker install)..."
for i in $(seq 1 60); do
  ssh -o StrictHostKeyChecking=no -i ~/.ssh/ssd_prod ubuntu@"$PUBLIC_IP" \
    "test -f /tmp/user-data-done && echo done" 2>/dev/null | grep -q "done" && break
  [[ $i -eq 60 ]] && warn "User-data may not be complete, continuing anyway"
  sleep 10
done
success "Instance initialized"

# =============================================================================
header "STEP 4: COPY APPLICATION FILES"
# =============================================================================

log "Copying application files to new instance..."
rsync -avz --progress \
  -e "ssh -o StrictHostKeyChecking=no -i ~/.ssh/ssd_prod" \
  --exclude '.git' \
  --exclude 'node_modules' \
  --exclude '__pycache__' \
  "${SCRIPT_DIR}/" \
  "ubuntu@${PUBLIC_IP}:/opt/ssd/"

success "Files copied"

# =============================================================================
header "STEP 5: CONFIGURE ENVIRONMENT"
# =============================================================================

log "Setting up environment on new instance..."
if [[ "$DEPLOY_ENV" == "staging" ]]; then
  # Create staging .env from production with modifications
  ssh -o StrictHostKeyChecking=no -i ~/.ssh/ssd_prod ubuntu@"$PUBLIC_IP" "
    cp /opt/ssd/.env.example /opt/ssd/.env
    sed -i 's/NODE_ENV=production/NODE_ENV=staging/' /opt/ssd/.env
    sed -i 's/ssd_production/ssd_staging/g' /opt/ssd/.env
    echo 'STAGING_INSTANCE=true' >> /opt/ssd/.env
  "
  warn "IMPORTANT: Update /opt/ssd/.env on $PUBLIC_IP with real credentials before deploying"
else
  # Copy production .env if it exists
  if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    scp -o StrictHostKeyChecking=no -i ~/.ssh/ssd_prod \
      "${SCRIPT_DIR}/.env" "ubuntu@${PUBLIC_IP}:/opt/ssd/.env"
    success "Production .env copied"
  else
    warn ".env not found — you'll need to configure it manually"
  fi
fi

# =============================================================================
header "STEP 6: DEPLOY SERVICES"
# =============================================================================

log "Making scripts executable..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/ssd_prod ubuntu@"$PUBLIC_IP" \
  "chmod +x /opt/ssd/*.sh"

log "Running deployment on new instance..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/ssd_prod ubuntu@"$PUBLIC_IP" \
  "cd /opt/ssd && docker-compose pull && docker-compose up -d" 2>&1 | tail -20

success "Services deployed"

# =============================================================================
header "STEP 7: VERIFY DEPLOYMENT"
# =============================================================================

log "Running health checks on new instance..."
sleep 15

HEALTH_OK=true
for port in "3000" "8000"; do
  if ssh -o StrictHostKeyChecking=no -i ~/.ssh/ssd_prod ubuntu@"$PUBLIC_IP" \
     "curl -sf http://localhost:${port}/health" > /dev/null 2>&1; then
    success "Port $port responding"
  else
    warn "Port $port not responding yet"
    HEALTH_OK=false
  fi
done

# =============================================================================
header "STEP 8: DNS SETUP (Optional)"
# =============================================================================

log "To point DNS to this new instance:"
echo ""
echo "  Option A — Update Route 53:"
echo "    aws route53 change-resource-record-sets \\"
echo "      --hosted-zone-id YOUR_ZONE_ID \\"
echo "      --change-batch '{\"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"ssd.cloud\",\"Type\":\"A\",\"TTL\":60,\"ResourceRecords\":[{\"Value\":\"${PUBLIC_IP}\"}]}}]}'"
echo ""
echo "  Option B — Update .ssh/config on MacBook:"
echo "    Host ssd-${DEPLOY_ENV}"
echo "      HostName ${PUBLIC_IP}"
echo ""

# =============================================================================
header "REPLICA DEPLOYMENT COMPLETE"
# =============================================================================

echo ""
echo -e "${GREEN}${BOLD}  ✓ Replica instance deployed successfully!${NC}"
echo ""
echo -e "  ${CYAN}Instance ID:${NC}  $INSTANCE_ID"
echo -e "  ${CYAN}Public IP:${NC}    $PUBLIC_IP"
echo -e "  ${CYAN}Region:${NC}       $AWS_REGION"
echo -e "  ${CYAN}Environment:${NC}  $DEPLOY_ENV"
echo ""
echo -e "  ${CYAN}SSH Access:${NC}"
echo "    ssh -i ~/.ssh/ssd_prod ubuntu@$PUBLIC_IP"
echo ""
echo -e "  ${CYAN}Next steps:${NC}"
echo "    1. Update .env with real credentials: ssh ubuntu@$PUBLIC_IP 'nano /opt/ssd/.env'"
echo "    2. Set up SSL: ssh ubuntu@$PUBLIC_IP 'certbot --nginx -d yourdomain.com'"
echo "    3. Update DNS to point to $PUBLIC_IP"
echo "    4. Run verify: ssh ubuntu@$PUBLIC_IP '/opt/ssd/verify-deployment.sh'"
echo ""

if [[ "$HEALTH_OK" == "false" ]]; then
  warn "Some health checks failed — check logs: ssh ubuntu@$PUBLIC_IP 'docker-compose logs'"
fi
