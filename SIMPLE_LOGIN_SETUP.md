# Simple Login Setup — MacBook Pro
## SSH Keys + Login Aliases for SSD Production Server

**Time required:** ~10 minutes
**Server IP:** 13.237.5.80
**Username:** ubuntu

---

## Step 1 — Generate SSH Key Pair

Open Terminal on your MacBook and run:

```bash
# Generate a 4096-bit RSA key specifically for SSD
ssh-keygen -t ed25519 -C "joshua@sunstatedigital.com.au" -f ~/.ssh/ssd_prod

# When prompted:
# Enter passphrase: (choose a strong passphrase, e.g. 3 random words)
# Enter same passphrase again: (repeat it)
```

This creates two files:
- `~/.ssh/ssd_prod` — your private key (NEVER share this)
- `~/.ssh/ssd_prod.pub` — your public key (safe to copy to server)

---

## Step 2 — Copy Public Key to Server

**Option A — Using ssh-copy-id (easiest):**

```bash
ssh-copy-id -i ~/.ssh/ssd_prod.pub ubuntu@13.237.5.80
# Enter your current server password when prompted
```

**Option B — Manual copy:**

```bash
# View your public key
cat ~/.ssh/ssd_prod.pub

# SSH to server with password
ssh ubuntu@13.237.5.80

# On the server, add your key
mkdir -p ~/.ssh
echo "PASTE_YOUR_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
exit
```

---

## Step 3 — Test SSH Key Login

```bash
# Test the connection (should NOT ask for password, only passphrase)
ssh -i ~/.ssh/ssd_prod ubuntu@13.237.5.80

# If it works, you'll see the server prompt:
# ubuntu@ssd-prod:~$
```

If it asks for a password instead of passphrase, check the authorized_keys file on the server.

---

## Step 4 — Create SSH Config Entry

Create or edit `~/.ssh/config` on your MacBook:

```bash
nano ~/.ssh/config
```

Add this block:

```
# Sun State Digital — Production Server
Host ssd-prod
    HostName 13.237.5.80
    User ubuntu
    IdentityFile ~/.ssh/ssd_prod
    ServerAliveInterval 60
    ServerAliveCountMax 3
    AddKeysToAgent yes
    UseKeychain yes
```

Save with `Ctrl+X`, then `Y`, then `Enter`.

Set correct permissions:
```bash
chmod 600 ~/.ssh/config
```

**Now you can login with just:**
```bash
ssh ssd-prod
```

---

## Step 5 — Add SSH Key to macOS Keychain

So you don't need to enter your passphrase every time:

```bash
# Add key to SSH agent with macOS Keychain
ssh-add --apple-use-keychain ~/.ssh/ssd_prod
# Enter your passphrase once — macOS saves it
```

---

## Step 6 — Create Bash Aliases

Add these aliases to your shell profile. Determine which shell you're using:

```bash
echo $SHELL
# /bin/zsh  ← most Macs use zsh now
# /bin/bash ← older setup
```

Edit the appropriate file:

```bash
# For zsh (most common):
nano ~/.zshrc

# For bash:
nano ~/.bash_profile
```

Add these lines at the bottom:

```bash
# ===== SUN STATE DIGITAL ALIASES =====

# Login to production server
alias ssd='ssh ssd-prod'

# View all service logs (live tail)
alias ssd-logs='ssh ssd-prod "cd /opt/ssd && docker-compose logs -f --tail=100"'

# View logs for specific service
alias ssd-logs-api='ssh ssd-prod "docker logs -f openclaw-gateway --tail=100"'
alias ssd-logs-quantum='ssh ssd-prod "docker logs -f quantum-api --tail=100"'
alias ssd-logs-blog='ssh ssd-prod "docker logs -f blog-frontend --tail=100"'

# Deploy all services
alias ssd-deploy='ssh ssd-prod "cd /opt/ssd && ./deploy-all.sh"'

# Verify all services are healthy
alias ssd-verify='ssh ssd-prod "cd /opt/ssd && ./verify-deployment.sh"'

# Check service status
alias ssd-status='ssh ssd-prod "cd /opt/ssd && docker-compose ps"'

# Restart all services
alias ssd-restart='ssh ssd-prod "cd /opt/ssd && docker-compose restart"'

# Restart specific service
alias ssd-restart-api='ssh ssd-prod "docker restart openclaw-gateway"'
alias ssd-restart-quantum='ssh ssd-prod "docker restart quantum-api"'

# Run backup now
alias ssd-backup='ssh ssd-prod "cd /opt/ssd && ./backup-restore.sh backup"'

# Check disk/memory usage
alias ssd-resources='ssh ssd-prod "df -h && free -h && docker stats --no-stream"'

# Onboard a new client
alias ssd-onboard='ssh ssd-prod "cd /opt/ssd && ./onboard-client.sh"'

# ===== END SSD ALIASES =====
```

Save the file, then reload your shell:

```bash
# For zsh:
source ~/.zshrc

# For bash:
source ~/.bash_profile
```

---

## Step 7 — Verify Everything Works

Test each alias:

```bash
# Test login
ssh ssd-prod
# Should connect without password prompt

# Test status check (from your Mac, no need to SSH first)
ssd-status
# Should show list of running Docker containers

# Test logs
ssd-logs
# Should show live log stream (press Ctrl+C to exit)

# Test verification
ssd-verify
# Should show green checkmarks for all health checks
```

---

## Quick Reference Card

```
╔══════════════════════════════════════════════╗
║          SSD QUICK REFERENCE                 ║
╠══════════════════════════════════════════════╣
║  LOGIN       ssh ssd-prod                   ║
║  STATUS      ssd-status                     ║
║  LOGS        ssd-logs                       ║
║  DEPLOY      ssd-deploy                     ║
║  VERIFY      ssd-verify                     ║
║  RESTART     ssd-restart                    ║
║  BACKUP      ssd-backup                     ║
║  RESOURCES   ssd-resources                  ║
║  ONBOARD     ssd-onboard                    ║
╚══════════════════════════════════════════════╝
  Server: 13.237.5.80 | User: ubuntu
  Support: support@sunstatedigital.com.au
```

---

## Troubleshooting

**Problem: SSH still asks for password**
```bash
# Check server authorized_keys
ssh ubuntu@13.237.5.80 "cat ~/.ssh/authorized_keys"
# Should show your public key

# Check permissions on server
ssh ubuntu@13.237.5.80 "ls -la ~/.ssh/"
# .ssh should be drwx------ (700)
# authorized_keys should be -rw------- (600)
```

**Problem: "Permission denied (publickey)"**
```bash
# Verbose debug output
ssh -vvv ssd-prod
# Look for which keys are being tried
```

**Problem: Alias not found after adding to .zshrc**
```bash
# Make sure you reloaded the file
source ~/.zshrc
# Or open a new terminal tab
```

**Problem: ssh-add doesn't persist after restart**
```bash
# Ensure UseKeychain yes is in ~/.ssh/config
# Re-add the key
ssh-add --apple-use-keychain ~/.ssh/ssd_prod
```

---

*Setup complete. You now have single-command access to your production server.*
