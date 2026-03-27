# Login Guide — All Access Methods
## Sun State Digital Production Platform

**Server:** 13.237.5.80
**Domain:** ssd.cloud
**Owner:** Josh (joshua@sunstatedigital.com.au)

---

## Method 1 — SSH (MacBook Pro — Primary Method)

### Quick Login
```bash
ssh ssd-prod
# (After completing SIMPLE_LOGIN_SETUP.md)
```

### Manual Login (if alias not set up)
```bash
ssh -i ~/.ssh/ssd_prod ubuntu@13.237.5.80
```

### What You Can Do via SSH
- View and tail service logs
- Restart services
- Run deployment scripts
- Access databases directly
- Edit configuration files
- Run backup/restore
- Monitor resource usage

---

## Method 2 — Web Dashboard (iPad / Browser)

### URLs

| Dashboard | URL | Credentials |
|---|---|---|
| Main Dashboard | https://ssd.cloud | admin / see .env |
| Grafana Monitoring | https://monitor.ssd.cloud | admin / see .env |
| API Documentation | https://api.ssd.cloud/docs | Public |
| Quantum API Docs | https://quantum.ssd.cloud/docs | Public |

### Accessing from iPad

1. Open Safari on iPad
2. Navigate to `https://ssd.cloud`
3. Enter your dashboard credentials
4. Tap the Share button → "Add to Home Screen"
5. Name it "SSD Dashboard"
6. Tap "Add"

Now you have a dedicated app icon on your iPad home screen.

### Grafana Dashboard

1. Go to `https://monitor.ssd.cloud`
2. Username: `admin`
3. Password: stored in `.env` as `GRAFANA_ADMIN_PASSWORD`
4. Bookmark: "SSD Monitoring"

**Key dashboards available:**
- System Overview (CPU, memory, disk)
- Service Health (all 3 services)
- Client Activity (per-client metrics)
- Revenue Metrics (MRR, churn, new clients)
- Error Rates (4xx, 5xx by service)
- Database Performance (query times, connections)

---

## Method 3 — Termius Mobile App (iPhone/iPad)

### Setup

1. Download **Termius** from the App Store (free tier is sufficient)
2. Open Termius → New Host
3. Fill in:
   - **Label:** SSD Production
   - **Hostname:** 13.237.5.80
   - **Port:** 22
   - **Username:** ubuntu
   - **Key:** Import your `ssd_prod` private key

### Importing Your Private Key to Termius

1. On MacBook, copy private key:
   ```bash
   cat ~/.ssh/ssd_prod | pbcopy
   ```
2. In Termius → Keychain → New Key → Paste
3. Name it "ssd_prod_key"
4. Assign it to the SSD Production host

### Termius Snippets (Save These)

Create these saved snippets in Termius for one-tap execution:

| Snippet Name | Command |
|---|---|
| Status | `cd /opt/ssd && docker-compose ps` |
| Logs All | `cd /opt/ssd && docker-compose logs -f --tail=50` |
| Restart All | `cd /opt/ssd && docker-compose restart` |
| Verify | `cd /opt/ssd && ./verify-deployment.sh` |
| Resources | `df -h && free -h` |

---

## Method 4 — VPN Access (Recommended for Sensitive Work)

### WireGuard VPN Setup

The production server runs a WireGuard VPN for additional security.

**Install WireGuard on MacBook:**
```bash
brew install wireguard-tools
```

**Request VPN config from server admin:**
```bash
# On server, generate client config
ssh ssd-prod
sudo wg genkey | tee /tmp/client_private | wg pubkey > /tmp/client_public
sudo cat /tmp/client_public  # Copy this
```

**WireGuard config on MacBook** (`/etc/wireguard/ssd.conf`):
```ini
[Interface]
PrivateKey = YOUR_CLIENT_PRIVATE_KEY
Address = 10.8.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = SERVER_PUBLIC_KEY
Endpoint = 13.237.5.80:51820
AllowedIPs = 10.8.0.0/24
PersistentKeepalive = 25
```

**Connect:**
```bash
sudo wg-quick up ssd
```

**Disconnect:**
```bash
sudo wg-quick down ssd
```

---

## Method 5 — AWS Console (Management Tasks)

### Console Access

1. Go to https://console.aws.amazon.com
2. Account ID: stored in `~/.aws/credentials`
3. IAM Username: `josh-admin`
4. Region: ap-southeast-2 (Sydney)

### AWS CLI Access

```bash
# Install AWS CLI
brew install awscli

# Configure
aws configure
# AWS Access Key ID: (from IAM console)
# AWS Secret Access Key: (from IAM console)
# Default region: ap-southeast-2
# Default output format: json

# Test
aws sts get-caller-identity
```

### Key AWS Console Shortcuts

| Service | Direct URL |
|---|---|
| ECS (containers) | https://ap-southeast-2.console.aws.amazon.com/ecs |
| RDS (database) | https://ap-southeast-2.console.aws.amazon.com/rds |
| EC2 (servers) | https://ap-southeast-2.console.aws.amazon.com/ec2 |
| CloudWatch (logs) | https://ap-southeast-2.console.aws.amazon.com/cloudwatch |
| S3 (storage) | https://s3.console.aws.amazon.com |
| Route 53 (DNS) | https://console.aws.amazon.com/route53 |

---

## iOS Shortcuts (iPhone/iPad)

### Create Quick Access Shortcuts

1. Open **Shortcuts** app on iPhone/iPad
2. Tap "+" to create new shortcut
3. Add action: "Open URL"

**Shortcut 1: SSD Status**
- URL: `https://ssd.cloud/health`
- Icon: Server rack
- Add to Home Screen

**Shortcut 2: SSD Monitoring**
- URL: `https://monitor.ssd.cloud`
- Icon: Chart
- Add to Home Screen

**Shortcut 3: Call Nick (Quantum Buyers Agents)**
- URL: `tel:+61427716756`
- Icon: Phone
- Add to Home Screen (or Lock Screen widget)

---

## Troubleshooting Common Login Issues

### Issue: SSH Connection Refused

```bash
# Check if server is up
ping 13.237.5.80

# Check if SSH port is open
nc -zv 13.237.5.80 22

# Try with verbose output
ssh -vvv ssd-prod
```

**Common causes:**
- AWS Security Group blocking port 22 → Check EC2 console
- UFW firewall on server → Need AWS console access to fix
- Instance stopped → Start it in EC2 console

### Issue: "Connection timed out"

```bash
# Check from different network (try mobile hotspot)
# If it works on hotspot, your ISP or router may be blocking SSH

# Alternative: Use SSH over port 443
# (Configure server to also listen on 443)
```

### Issue: "Host key verification failed"

```bash
# Server was rebuilt — remove old key
ssh-keygen -R 13.237.5.80
ssh-keygen -R ssd-prod

# Then reconnect
ssh ssd-prod
# Accept new fingerprint
```

### Issue: Web Dashboard Not Loading

1. Check server status: `ping 13.237.5.80`
2. Check SSL cert: `curl -I https://ssd.cloud`
3. Check nginx: `ssh ssd-prod "sudo systemctl status nginx"`
4. Check Docker: `ssh ssd-prod "docker-compose ps"`

### Issue: Forgot Dashboard Password

```bash
# View current password
ssh ssd-prod "grep GRAFANA_ADMIN_PASSWORD /opt/ssd/.env"

# Reset Grafana password
ssh ssd-prod "docker exec grafana grafana-cli admin reset-admin-password NEWPASSWORD"
```

### Issue: AWS Console MFA Required

- MFA device: Authenticator app on iPhone
- App: Google Authenticator or Authy
- Account: AWS account number (in your .env file)
- If you lose MFA device, use root account recovery

---

## Emergency Access

If all normal access methods fail:

### AWS Systems Manager (SSM)

```bash
# No SSH needed — access via AWS console
aws ssm start-session --target INSTANCE_ID --region ap-southeast-2
```

Find instance ID in EC2 console → Running Instances.

### EC2 Instance Connect (Browser-based SSH)

1. Go to EC2 console
2. Select your instance
3. Click "Connect" → "EC2 Instance Connect"
4. Click "Connect" button
5. Browser opens a terminal

### Root Recovery

If the instance is unreachable via all methods:
1. In EC2 console, stop the instance
2. Detach the root EBS volume
3. Attach to a rescue instance
4. Mount and repair/access files
5. Re-attach and start

---

## Access Credentials Location

All credentials are stored in:
- **Server:** `/opt/ssd/.env`
- **Local backup:** 1Password / your password manager
- **AWS Secrets Manager:** `ssd/prod/credentials`

**NEVER store credentials in:**
- Slack messages
- Email
- Git repositories
- Text files on Desktop

---

*See `REMOTE_ACCESS_SETUP.md` for full MacBook Pro configuration including all tools and apps.*
