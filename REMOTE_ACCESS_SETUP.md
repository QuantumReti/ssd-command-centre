# Remote Access Setup — MacBook Pro
## Complete Configuration for Sun State Digital Platform

**Goal:** Full remote control of your production server from any location on your MacBook Pro.

---

## 1. SSH Configuration

### Install Dependencies

```bash
# Ensure Homebrew is installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install useful tools
brew install openssh mosh tmux
```

### SSH Config (`~/.ssh/config`)

```bash
nano ~/.ssh/config
```

Complete config:

```
# ========================================
# SUN STATE DIGITAL SSH CONFIGURATION
# ========================================

# Production Server
Host ssd-prod
    HostName 13.237.5.80
    User ubuntu
    IdentityFile ~/.ssh/ssd_prod
    ServerAliveInterval 60
    ServerAliveCountMax 5
    AddKeysToAgent yes
    UseKeychain yes
    Compression yes
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
    ControlPersist 600

# Staging Server (when set up)
Host ssd-staging
    HostName STAGING_IP
    User ubuntu
    IdentityFile ~/.ssh/ssd_prod
    ServerAliveInterval 60
    AddKeysToAgent yes
    UseKeychain yes

# Jump through bastion (if VPC only setup)
Host ssd-bastion
    HostName 13.237.5.80
    User ubuntu
    IdentityFile ~/.ssh/ssd_prod

Host ssd-internal
    HostName 10.0.1.10
    User ubuntu
    ProxyJump ssd-bastion
    IdentityFile ~/.ssh/ssd_prod
```

Create sockets directory:
```bash
mkdir -p ~/.ssh/sockets
chmod 700 ~/.ssh/sockets
```

### SSH Key Management

```bash
# View all keys in agent
ssh-add -l

# Add key persistently (survives reboots)
ssh-add --apple-use-keychain ~/.ssh/ssd_prod

# Remove key from agent
ssh-add -d ~/.ssh/ssd_prod

# Generate new key if needed
ssh-keygen -t ed25519 -C "joshua@sunstatedigital.com.au" -f ~/.ssh/ssd_prod
```

---

## 2. Shell Aliases & Functions

Edit `~/.zshrc`:

```bash
nano ~/.zshrc
```

Add the full SSD section:

```bash
# ========================================
# SUN STATE DIGITAL — REMOTE MANAGEMENT
# ========================================

# --- Connection ---
alias ssd='ssh ssd-prod'
alias ssd-tmux='ssh ssd-prod -t "tmux new-session -A -s main"'
alias ssd-mosh='mosh ubuntu@13.237.5.80'

# --- Service Management ---
alias ssd-status='ssh ssd-prod "cd /opt/ssd && docker-compose ps"'
alias ssd-start='ssh ssd-prod "cd /opt/ssd && docker-compose up -d"'
alias ssd-stop='ssh ssd-prod "cd /opt/ssd && docker-compose down"'
alias ssd-restart='ssh ssd-prod "cd /opt/ssd && docker-compose restart"'
alias ssd-restart-api='ssh ssd-prod "docker restart openclaw-gateway"'
alias ssd-restart-quantum='ssh ssd-prod "docker restart quantum-api"'
alias ssd-restart-blog='ssh ssd-prod "docker restart blog-frontend"'

# --- Logs ---
alias ssd-logs='ssh ssd-prod "cd /opt/ssd && docker-compose logs -f --tail=100"'
alias ssd-logs-api='ssh ssd-prod "docker logs -f openclaw-gateway --tail=100"'
alias ssd-logs-quantum='ssh ssd-prod "docker logs -f quantum-api --tail=100"'
alias ssd-logs-blog='ssh ssd-prod "docker logs -f blog-frontend --tail=100"'
alias ssd-logs-nginx='ssh ssd-prod "sudo tail -f /var/log/nginx/access.log"'
alias ssd-errors='ssh ssd-prod "sudo tail -f /var/log/nginx/error.log"'

# --- Deployment ---
alias ssd-deploy='ssh ssd-prod "cd /opt/ssd && ./deploy-all.sh"'
alias ssd-deploy-api='ssh ssd-prod "cd /opt/ssd && ./deploy-openclaw.sh"'
alias ssd-deploy-quantum='ssh ssd-prod "cd /opt/ssd && ./deploy-quantum.sh"'
alias ssd-deploy-blog='ssh ssd-prod "cd /opt/ssd && ./deploy-blog.sh"'

# --- Verification & Health ---
alias ssd-verify='ssh ssd-prod "cd /opt/ssd && ./verify-deployment.sh"'
alias ssd-health='curl -s https://ssd.cloud/health | jq .'
alias ssd-ping='ping -c 3 13.237.5.80'

# --- Resources ---
alias ssd-resources='ssh ssd-prod "echo === DISK === && df -h && echo === MEMORY === && free -h && echo === CPU === && top -bn1 | grep Cpu"'
alias ssd-docker-stats='ssh ssd-prod "docker stats --no-stream"'
alias ssd-processes='ssh ssd-prod "ps aux --sort=-%cpu | head -20"'

# --- Database ---
alias ssd-db='ssh ssd-prod "docker exec -it postgres psql -U ssd_user -d ssd_production"'
alias ssd-db-backup='ssh ssd-prod "cd /opt/ssd && ./backup-restore.sh backup"'
alias ssd-db-restore='ssh ssd-prod "cd /opt/ssd && ./backup-restore.sh restore"'

# --- Client Management ---
alias ssd-onboard='ssh ssd-prod "cd /opt/ssd && ./onboard-client.sh"'
alias ssd-clients='ssh ssd-prod "docker exec postgres psql -U ssd_user -d ssd_production -c \"SELECT client_name, tier, created_at FROM clients ORDER BY created_at DESC;\""'

# --- AWS ---
alias aws-login='aws sso login --profile ssd-prod'
alias aws-prod='export AWS_PROFILE=ssd-prod'
alias ecr-login='aws ecr get-login-password --region ap-southeast-2 | docker login --username AWS --password-stdin 123456789.dkr.ecr.ap-southeast-2.amazonaws.com'

# --- Useful Functions ---
ssd-exec() {
    # Run any command on server: ssd-exec "ls -la /opt/ssd"
    ssh ssd-prod "$@"
}

ssd-upload() {
    # Upload file to server: ssd-upload local_file.txt /opt/ssd/
    scp -i ~/.ssh/ssd_prod "$1" ubuntu@13.237.5.80:"$2"
}

ssd-download() {
    # Download file from server: ssd-download /opt/ssd/.env ./
    scp -i ~/.ssh/ssd_prod ubuntu@13.237.5.80:"$1" "$2"
}

ssd-tunnel() {
    # Forward local port to server: ssd-tunnel 5432 5432 (local:remote)
    ssh -L "${1}:localhost:${2}" ssd-prod -N
}

# ========================================
# END SSD SECTION
# ========================================
```

Reload:
```bash
source ~/.zshrc
```

---

## 3. Termius App Setup (iPhone & iPad)

### Installation
1. Download **Termius** from App Store (free or Pro)
2. Create account at termius.com (enables sync across devices)

### Host Configuration

In Termius → Hosts → New Host:

```
Label:       SSD Production
Hostname:    13.237.5.80
Port:        22
Username:    ubuntu
Auth Type:   Key
```

### Import SSH Key

1. On MacBook: `cat ~/.ssh/ssd_prod | pbcopy`
2. In Termius → Keychain → New Key
3. Paste private key
4. Name: "ssd_prod"
5. Enter your passphrase
6. Assign to the SSD Production host

### Create Snippets

In Termius → Snippets → New Snippet for each:

```
Name: 📊 Status
Command: cd /opt/ssd && docker-compose ps

Name: 📋 All Logs
Command: cd /opt/ssd && docker-compose logs -f --tail=50

Name: 🔄 Restart All
Command: cd /opt/ssd && docker-compose restart

Name: ✅ Verify
Command: cd /opt/ssd && ./verify-deployment.sh

Name: 💾 Backup
Command: cd /opt/ssd && ./backup-restore.sh backup

Name: 📈 Resources
Command: df -h && free -h && docker stats --no-stream

Name: 🔧 Deploy All
Command: cd /opt/ssd && ./deploy-all.sh

Name: 👤 Onboard Client
Command: cd /opt/ssd && ./onboard-client.sh
```

---

## 4. Web Dashboard Bookmarks

### Safari Bookmark Folder Structure

Create a bookmark folder called "SSD Platform" with these bookmarks:

```
📁 SSD Platform
├── 🏠 Main Dashboard        → https://ssd.cloud
├── 📊 Grafana Monitoring    → https://monitor.ssd.cloud
├── 🔌 API Docs              → https://api.ssd.cloud/docs
├── ⚡ Quantum API Docs      → https://quantum.ssd.cloud/docs
├── 📝 Blog                  → https://blog.ssd.cloud
└── 📁 AWS Console
    ├── ECS (Containers)     → https://ap-southeast-2.console.aws.amazon.com/ecs
    ├── RDS (Database)       → https://ap-southeast-2.console.aws.amazon.com/rds
    ├── EC2 (Servers)        → https://ap-southeast-2.console.aws.amazon.com/ec2
    ├── CloudWatch (Logs)    → https://ap-southeast-2.console.aws.amazon.com/cloudwatch
    └── S3 (Storage)         → https://s3.console.aws.amazon.com
```

### Add to Safari Reading List (Offline Access)

For offline reference, save these to Reading List:
- `QUICK_START.txt`
- This file
- `kb/KNOWLEDGE_BASE.md` (open from GitHub)

---

## 5. iOS Shortcuts

### Set Up Notification Shortcut

1. Open Shortcuts app on iPhone
2. Tap + → Add Action → "Run Script Over SSH"
3. Configure:
   - Host: 13.237.5.80
   - User: ubuntu
   - Key: ssd_prod
   - Script: `cd /opt/ssd && ./verify-deployment.sh | tail -5`
4. Add "Get Contents of URL" → `https://ssd.cloud/health`
5. Add to Automation: "Every 30 minutes between 8am-6pm"
6. Name: "SSD Health Check"

### Quick Action Shortcuts (Add to Home Screen)

**Shortcut: SSD Status**
```
Actions:
1. Run Script Over SSH
   - Script: cd /opt/ssd && docker-compose ps
2. Show Result
```

**Shortcut: Open Monitoring**
```
Actions:
1. Open URL: https://monitor.ssd.cloud
```

**Shortcut: Call Nick Esplin (Quantum Buyers Agents)**
```
Actions:
1. Call: +61427716756
```

---

## 6. Notification Setup

### Slack Notifications (Recommended)

The deployment scripts send Slack notifications automatically. To set up:

1. Go to api.slack.com/apps
2. Create New App → From Scratch
3. App Name: "SSD Alerts"
4. Workspace: Sun State Digital
5. Add feature: Incoming Webhooks
6. Create webhook for #alerts channel
7. Copy webhook URL to `.env`:
   ```
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/XXXX/YYYY/ZZZZ
   ```

### Notification Events

The system sends Slack alerts for:
- ✅ Deployment success
- ❌ Deployment failure
- ⚠️ Service health check failure
- 🔴 Error rate > 1%
- 💾 Disk usage > 90%
- 🧠 Memory usage > 85%
- 🆕 New client onboarded
- 💰 New payment received
- 🔑 SSL cert expiring in 30 days

### Email Notifications via AWS SES

Critical alerts are also emailed to joshua@sunstatedigital.com.au:
- Server down
- SSL cert < 7 days to expiry
- Backup failure
- Security event

---

## 7. tmux Session Management (Persistent Terminal)

When SSH-ing for long running tasks, use tmux so sessions persist:

```bash
# Connect and attach to persistent session
ssd-tmux
# or: ssh ssd-prod -t "tmux new-session -A -s main"

# Inside tmux:
Ctrl+B, C       = New window
Ctrl+B, N       = Next window
Ctrl+B, P       = Previous window
Ctrl+B, D       = Detach (session keeps running)
Ctrl+B, [       = Scroll mode (q to exit)
Ctrl+B, %       = Split vertically
Ctrl+B, "       = Split horizontally

# Reattach later
ssh ssd-prod -t "tmux attach -t main"
```

---

## 8. Port Forwarding (Local Access to Server Services)

Access server services locally without exposing them publicly:

```bash
# Forward Grafana to localhost:3001
ssd-tunnel 3001 3001
# Then open: http://localhost:3001

# Forward PostgreSQL to localhost:5432
ssd-tunnel 5432 5432
# Then connect with TablePlus/Postico

# Forward Prometheus to localhost:9090
ssd-tunnel 9090 9090
# Then open: http://localhost:9090
```

### TablePlus (macOS Database Client)

1. Install: brew install --cask tableplus
2. Set up SSH tunnel: `ssd-tunnel 5432 5432`
3. In TablePlus: New Connection → PostgreSQL
   - Host: localhost
   - Port: 5432
   - User: ssd_user
   - Password: (from .env)
   - Database: ssd_production

---

## 9. Complete Tool Checklist

| Tool | Purpose | Status |
|---|---|---|
| Terminal.app or iTerm2 | SSH terminal | ✅ Built-in |
| Homebrew | Package manager | Install: brew.sh |
| openssh | SSH client | `brew install openssh` |
| mosh | Resilient SSH | `brew install mosh` |
| tmux | Session persistence | `brew install tmux` |
| awscli | AWS management | `brew install awscli` |
| docker | Local Docker | Docker Desktop |
| Termius | Mobile SSH | App Store |
| TablePlus | DB client | `brew install --cask tableplus` |
| AWS Console | Cloud management | browser |
| 1Password | Credentials | App Store |

---

## 10. First-Time Setup Checklist

```
[ ] SSH key generated (ed25519)
[ ] Public key copied to server
[ ] ~/.ssh/config entry created
[ ] SSH key added to macOS Keychain
[ ] Shell aliases added to ~/.zshrc
[ ] Aliases tested (ssd-status works)
[ ] Termius installed and configured
[ ] SSH key imported to Termius
[ ] Termius snippets created
[ ] Web dashboards bookmarked
[ ] iOS shortcuts created
[ ] Slack notifications configured
[ ] AWS CLI configured
[ ] TablePlus connected via tunnel
[ ] tmux session tested
```

---

*Full setup time: approximately 45 minutes. After this, all day-to-day operations take seconds.*
