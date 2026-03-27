# Security Guide
## Sun State Digital Platform

**Security contact:** joshua@sunstatedigital.com.au
**Emergency contact:** joshua@sunstatedigital.com.au (mobile)
**Last reviewed:** 2026-03-18

---

## 1. Credential Management

### Where Credentials Live

| Location | What's Stored | Who Can Access |
|---|---|---|
| AWS Secrets Manager | All production secrets | ECS tasks (via IAM role) |
| `.env` on server | Runtime values | ubuntu user only |
| 1Password | Josh's admin credentials | Josh only |
| Termius Keychain | SSH private key | Secure device only |

### AWS Secrets Manager

All production secrets stored under `ssd/prod/`:

```bash
# List all SSD secrets
aws secretsmanager list-secrets \
  --filter Key=name,Values=ssd/ \
  --region ap-southeast-2 \
  --query 'SecretList[].Name'

# Read a secret (for reference only — services read directly)
aws secretsmanager get-secret-value \
  --secret-id ssd/prod/db-credentials \
  --region ap-southeast-2 \
  --query 'SecretString' \
  --output text
```

### Generating Strong Credentials

```bash
# Generate JWT secret (64 bytes = 128 hex chars)
openssl rand -hex 64

# Generate API key
openssl rand -hex 32

# Generate encryption key
openssl rand -hex 32

# Generate webhook secret
openssl rand -base64 48

# Generate password (alphanumeric, no special chars)
openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32
```

---

## 2. MFA Setup

### Josh's AWS Account

**Enable MFA on root account:**
1. AWS Console → Security Credentials
2. Multi-factor authentication → Assign MFA device
3. App: Google Authenticator or Authy
4. Save QR code backup securely in 1Password

**Enable MFA on IAM user (josh-admin):**
1. IAM → Users → josh-admin → Security credentials
2. Manage MFA → Virtual MFA device
3. Same authenticator app

**Enforce MFA on all IAM users:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyAllExceptMFA",
      "Effect": "Deny",
      "NotAction": [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
```

---

## 3. SSH Hardening

### Server SSH Configuration (`/etc/ssh/sshd_config`)

```conf
# Disable password authentication
PasswordAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes

# Disable root login
PermitRootLogin no

# Allowed users only
AllowUsers ubuntu

# Use modern algorithms
HostKeyAlgorithms ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ssh-ed25519
KexAlgorithms curve25519-sha256@libssh.org,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com

# Connection limits
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30

# Keepalive
ClientAliveInterval 120
ClientAliveCountMax 3

# Logging
LogLevel VERBOSE
SyslogFacility AUTH
```

Apply changes:
```bash
sudo sshd -t  # Test config
sudo systemctl reload ssh
```

### fail2ban Configuration

```bash
# Check fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status sshd

# View banned IPs
sudo fail2ban-client get sshd banip

# Unban an IP (if you locked yourself out)
sudo fail2ban-client set sshd unbanip YOUR.IP.ADDRESS

# Config file: /etc/fail2ban/jail.local
```

**fail2ban jail.local:**
```ini
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
destemail = joshua@sunstatedigital.com.au
sendername = Fail2Ban SSD
action = %(action_mw)s

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 86400  # 24 hours for SSH
```

---

## 4. Firewall Rules

### UFW (Host Firewall)

```bash
# View current rules
sudo ufw status verbose

# Current allowed rules:
# 22/tcp (SSH)  — consider restricting to your IP
# 80/tcp (HTTP) — redirects to HTTPS
# 443/tcp (HTTPS)
# 51820/udp (WireGuard VPN)

# Restrict SSH to your home/office IP (recommended)
sudo ufw delete allow 22/tcp
sudo ufw allow from YOUR.IP.ADDRESS to any port 22
sudo ufw reload
```

### AWS Security Groups

```bash
# View current rules
aws ec2 describe-security-groups \
  --group-ids sg-ssd-prod \
  --region ap-southeast-2 \
  --query 'SecurityGroups[0].IpPermissions'

# Best practice: restrict SSH to your IP
aws ec2 revoke-security-group-ingress \
  --group-id sg-XXXXXXXX \
  --protocol tcp --port 22 \
  --cidr "0.0.0.0/0" \
  --region ap-southeast-2

aws ec2 authorize-security-group-ingress \
  --group-id sg-XXXXXXXX \
  --protocol tcp --port 22 \
  --cidr "YOUR.IP.ADDRESS/32" \
  --region ap-southeast-2
```

---

## 5. Encryption

### Encryption at Rest

| Data | Encryption |
|---|---|
| RDS PostgreSQL | AWS KMS (AES-256) |
| ElastiCache Redis | AWS KMS (in-transit TLS) |
| S3 buckets | SSE-S3 (AES-256) |
| EBS volumes | Encrypted with KMS |
| Docker volumes (host) | OS-level encryption (off by default — consider LUKS) |
| Backup files (S3) | OpenSSL AES-256-CBC + SSE-S3 |

### Encryption in Transit

| Connection | Encryption |
|---|---|
| All web traffic | TLS 1.2/1.3 (nginx) |
| Internal service-to-service | TLS (docker network) |
| RDS connections | SSL required |
| Redis connections | TLS (ElastiCache) |
| S3 API calls | HTTPS only |
| SSH connections | ed25519 with strong ciphers |

### Application-Level Encryption

```javascript
// Sensitive fields encrypted before DB storage
// In openclaw-gateway/src/utils/crypto.js:

const ALGORITHM = 'aes-256-gcm';
const KEY = Buffer.from(process.env.ENCRYPTION_KEY, 'hex');

function encrypt(text) {
  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv(ALGORITHM, KEY, iv);
  const encrypted = Buffer.concat([cipher.update(text), cipher.final()]);
  const tag = cipher.getAuthTag();
  return { iv: iv.hex(), tag: tag.hex(), data: encrypted.hex() };
}
```

Fields encrypted in database:
- Client API keys
- OAuth tokens
- Webhook secrets
- Payment card tokens (Stripe handles these)

---

## 6. Audit Logging

### What's Logged

```
OpenClaw Gateway:
  - All API requests (method, path, status, latency, client_id)
  - Authentication events (login, logout, token refresh, failures)
  - API key usage (which key, which client, what action)
  - Webhook receipts (source, event type, processing result)
  - Admin actions (client created, deleted, updated)

AWS CloudTrail:
  - All AWS API calls
  - IAM changes
  - S3 access
  - Secret Manager access
  - EC2/ECS changes

Nginx:
  - All HTTP requests with IP, method, path, status, response time
  - Authentication failures (401, 403)

PostgreSQL:
  - All connections
  - Queries > 1 second
  - DDL changes (schema modifications)
```

### Viewing Audit Logs

```bash
# View auth events in last hour
ssh ssd-prod "docker logs openclaw-gateway --since 1h 2>&1 | jq 'select(.type == \"auth\")"

# View all admin actions today
ssh ssd-prod "docker logs openclaw-gateway --since 24h 2>&1 | jq 'select(.type == \"admin\")'"

# AWS CloudTrail (last 24h)
aws cloudtrail lookup-events \
  --start-time $(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ) \
  --region ap-southeast-2 \
  --query 'Events[*].[EventName,EventTime,Username,SourceIPAddress]' \
  --output table
```

---

## 7. Credential Rotation Schedule

### 90-Day Rotation (Quarterly)

| Credential | Last Rotated | Next Due | How to Rotate |
|---|---|---|---|
| JWT_SECRET | 2026-01-01 | 2026-04-01 | Update .env + restart openclaw |
| ENCRYPTION_KEY | 2026-01-01 | 2026-04-01 | Re-encrypt all DB records |
| OPENCLAW_API_KEY | 2026-01-01 | 2026-04-01 | Update .env + notify integrations |
| AWS IAM keys | 2026-01-01 | 2026-04-01 | Generate new in IAM console |
| GHL API key | 2026-01-01 | 2026-04-01 | Regenerate in GHL settings |

### Rotation Procedure

```bash
# 1. Generate new value
NEW_SECRET=$(openssl rand -hex 64)

# 2. Update AWS Secrets Manager
aws secretsmanager update-secret \
  --secret-id ssd/prod/jwt-secret \
  --secret-string "$NEW_SECRET" \
  --region ap-southeast-2

# 3. Update .env on server
ssh ssd-prod "sed -i 's/^JWT_SECRET=.*/JWT_SECRET=${NEW_SECRET}/' /opt/ssd/.env"

# 4. Restart affected service
ssh ssd-prod "docker restart openclaw-gateway"

# 5. Verify service is healthy
ssd-verify

# 6. Invalidate all existing sessions (JWT rotation)
ssh ssd-prod "docker exec redis redis-cli -a $REDIS_PASSWORD FLUSHDB"
# Note: this logs out all users — warn them first

# 7. Document the rotation
# Update the table above with new date
```

### Annual Rotation

- SSL certificates: Auto-renewed by Certbot (90 days, auto)
- SSH host keys: Annually, coordinate with team
- Database master password: Annually (RDS Master Credentials)

---

## 8. Incident Response

### Severity Levels

| Level | Definition | Response Time | Examples |
|---|---|---|---|
| P0 - Critical | Platform completely down | < 15 minutes | All services down, data breach |
| P1 - High | Major feature unavailable | < 1 hour | Single service down |
| P2 - Medium | Degraded performance | < 4 hours | High error rate, slow responses |
| P3 - Low | Minor issue | < 24 hours | Non-critical bug, cosmetic |

### Incident Response Steps

**P0/P1 Incident:**

```
1. DETECT (0-5 min)
   - Alert fires in Slack #ssd-alerts
   - Josh gets phone notification
   - Check: https://ssd.cloud/health

2. ASSESS (5-10 min)
   - Run: ssd-verify
   - Check logs: ssd-logs
   - Check Grafana: monitor.ssd.cloud

3. COMMUNICATE (10 min)
   - Post in Slack: "Investigating incident with [service]"
   - If client-impacting: notify affected clients

4. MITIGATE (10-30 min)
   - Restart affected service: ssd-restart
   - If deployment issue: ssd-deploy
   - If DNS issue: check Route 53
   - If AWS issue: check EC2/ECS console

5. RESOLVE (variable)
   - Confirm resolution: ssd-verify
   - Post in Slack: "Incident resolved. Duration: X min"

6. POST-MORTEM (within 24h for P0/P1)
   - Root cause analysis
   - Prevention measures
   - Update runbooks
```

### Suspected Security Breach

```bash
# 1. Immediately rotate all credentials
# See rotation procedure above

# 2. Check for unauthorized access
ssh ssd-prod "sudo last | head -30"
ssh ssd-prod "sudo lastb | head -30"  # Failed logins
ssh ssd-prod "sudo grep 'Invalid user' /var/log/auth.log | tail -20"

# 3. Check for unusual processes
ssh ssd-prod "ps aux --sort=-%cpu | head -20"
ssh ssd-prod "netstat -tulpn | grep -v docker"

# 4. Check crontab for tampering
ssh ssd-prod "crontab -l && sudo crontab -l && cat /etc/crontab"

# 5. Check for modified files
ssh ssd-prod "find /opt/ssd -newer /opt/ssd/docker-compose.yml -type f"

# 6. Block suspicious IPs
ssh ssd-prod "sudo ufw deny from SUSPICIOUS.IP.ADDRESS"

# 7. Notify clients if their data may be affected
# (legal obligation under Australian Privacy Act)

# 8. AWS-level isolation if needed
aws ec2 revoke-security-group-ingress --group-id sg-XXXX --protocol all --cidr 0.0.0.0/0
# (will take down site — only if breach is ongoing)
```

---

## 9. GDPR / Privacy Compliance (Australian Context)

### Australian Privacy Act 1988 Compliance

- **Privacy Policy:** Required on ssd.cloud
- **Data Collection:** Only collect what's necessary
- **Data Retention:** Delete client data after contract ends (90 days grace)
- **Data Location:** Primary data in Australia (ap-southeast-2 ✅)
- **Breach Notification:** Report to OAIC within 30 days of becoming aware
- **Client Rights:** Provide access to data on request

### Data Handling

```bash
# Delete a client's data (when contract ends)
ssh ssd-prod "/opt/ssd/onboard-client.sh offboard --client-id CLIENT_ID"

# This will:
# - Export final backup to S3
# - Drop client database
# - Delete client S3 bucket
# - Remove API keys
# - Archive monitoring data
# - Send final data export to client
```

### Third-Party Data Processors

| Processor | Data Shared | Jurisdiction | DPA |
|---|---|---|---|
| AWS | Infrastructure | Australia (ap-southeast-2) | Standard |
| OpenAI | Lead data (anonymized) | US | DPA in place |
| Anthropic | Lead data (anonymized) | US | DPA in place |
| Google | Ads data | US | Standard terms |
| Meta | Ads data | US | Standard terms |

---

*Security review scheduled quarterly. Next review: 2026-06-01*
*Contact: joshua@sunstatedigital.com.au for security questions or to report issues.*
