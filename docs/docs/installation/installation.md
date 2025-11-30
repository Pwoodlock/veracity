---
sidebar_position: 1
---

# Installation Guide

Complete guide for installing Veracity on your server.

## System Requirements

### Supported Operating Systems

| OS | Versions | Status |
|----|----------|--------|
| Ubuntu | 20.04, 22.04, 24.04 LTS | Supported |
| Debian | 11 (Bullseye), 12 (Bookworm) | Supported |
| Rocky Linux | 9 | Planned |
| AlmaLinux | 9 | Planned |

### Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 2 GB | 4+ GB |
| Disk | 20 GB | 50+ GB |
| Network | 100 Mbps | 1 Gbps |

## Installation Methods

### Method 1: One-Line Install (Recommended)

```bash
curl -sSL https://raw.githubusercontent.com/Pwoodlock/veracity-/main/install.sh | sudo bash
```

### Method 2: Clone and Install

```bash
git clone https://github.com/Pwoodlock/veracity-.git
cd veracity-
sudo ./install.sh
```

## Installation Process

### Configuration Prompts

The installer will ask for:

| Setting | Description | Default |
|---------|-------------|---------|
| Domain/IP | Your server's FQDN or IP | Server's IP |
| HTTPS | Enable Let's Encrypt certificates | Yes |
| Admin Email | Administrator email address | Required |
| Admin Password | Auto-generated or custom | Auto-generated |
| Timezone | Server timezone | UTC |

### Automated Steps

The installer performs these steps:

```
✓ System prerequisites check
✓ Install PostgreSQL 14+
✓ Install Redis 7+
✓ Install SaltStack 3007
✓ Install Ruby 3.3.6 (via Mise)
✓ Install Node.js 24 LTS
✓ Install Caddy web server
✓ Install Gotify (binary)
✓ Install Python integrations
✓ Clone application
✓ Install dependencies
✓ Database setup and migrations
✓ Asset compilation
✓ Systemd services
✓ Firewall configuration
✓ Health checks
```

**Estimated time:** 15-20 minutes

### Software Installed

| Component | Version | Purpose |
|-----------|---------|---------|
| Ruby | 3.3.6 | Application runtime (via Mise) |
| Rails | 8.0 | Web framework |
| DaisyUI | 5.x | UI components (Tailwind CSS) |
| Node.js | 24 LTS | Asset compilation |
| PostgreSQL | 14+ | Database |
| Redis | 7+ | Cache & job queue |
| SaltStack | 3007 | Infrastructure automation |
| Python | 3.8+ | CVE monitoring & Salt integrations |
| Caddy | Latest | Web server with auto-HTTPS |
| Gotify | Latest | Push notifications (binary) |

## Post-Installation

### Verify Installation

```bash
# Check service status
systemctl status server-manager
systemctl status server-manager-sidekiq

# View credentials
cat /tmp/veracity-install-credentials-*.txt

# View logs
journalctl -u server-manager -f
```

### Next Steps

1. Access the dashboard at `https://your-domain.com`
2. Login with your admin credentials
3. Enable 2FA in Settings → Security
4. Configure integrations (Gotify, Hetzner, Proxmox, Vulnerability Lookup) via Settings
5. Install Salt minions:
   ```bash
   curl -sSL https://your-domain.com/install-minion.sh | sudo bash
   ```
6. Accept minion keys in the Onboarding page

## Installation Options

### Resume After Error

If installation was interrupted:

```bash
sudo ./install.sh --resume
```

### Rollback

To undo installation changes:

```bash
sudo ./install.sh --rollback
```

## Firewall Rules

The installer configures these firewall rules:

| Service | Port | Protocol |
|---------|------|----------|
| SSH | 22 | TCP |
| HTTP | 80 | TCP |
| HTTPS | 443 | TCP |
| Salt Master | 4505-4506 | TCP |

## File Locations

```
/opt/veracity/app/           # Application directory
├── app/                     # Rails application
├── config/                  # Configuration
├── log/                     # Logs
├── integrations_venv/       # Python virtual environment (CVE monitoring)
├── .env.production          # Environment variables
└── public/                  # Static assets

/home/deploy/                # Deploy user
└── .local/share/mise/       # Ruby installation

/etc/systemd/system/
├── server-manager.service   # Puma service
└── server-manager-sidekiq.service

/var/lib/veracity-installer/ # Installation state
├── checkpoints              # Completed phases
├── config                   # Saved config
└── errors.log               # Error log
```

## Troubleshooting

### Check Logs

```bash
# Installation log
tail -f /var/log/veracity-install/install-*.log

# Application log
tail -f /opt/veracity/app/log/production.log

# Service logs
journalctl -u server-manager -n 50 --no-pager
```

### Common Issues

**Service won't start:**
```bash
journalctl -u server-manager -n 100 --no-pager
```

**Database connection error:**
```bash
sudo systemctl status postgresql
sudo -u postgres psql -c "SELECT 1"
```

**Salt API authentication fails:**
```bash
# Check Salt API status
sudo systemctl status salt-api

# Test authentication
curl -sSk http://127.0.0.1:8001/login \
  -H "Accept: application/json" \
  -d username=saltapi \
  -d password=YOUR_PASSWORD \
  -d eauth=pam
```

### Rails Console

For debugging:

```bash
cd /opt/veracity/app
sudo -u deploy bash -lc "RAILS_ENV=production bundle exec rails console"
```

### Reset Admin Password

```bash
cd /opt/veracity/app
sudo -u deploy bash -lc "RAILS_ENV=production bundle exec rails runner \"
user = User.find_by(email: 'admin@example.com')
user.password = 'new-password'
user.password_confirmation = 'new-password'
user.save!
\""
```

## Upgrading

### Update Script

```bash
sudo /opt/veracity/app/scripts/update.sh
```

This will:
1. Create a backup
2. Pull latest code
3. Update dependencies
4. Run migrations
5. Restart services

### Manual Update

```bash
sudo systemctl stop server-manager server-manager-sidekiq
cd /opt/veracity/app
sudo -u deploy git pull origin main
sudo -u deploy bash -lc "bundle install --deployment"
sudo -u deploy bash -lc "RAILS_ENV=production bundle exec rails db:migrate"
sudo -u deploy bash -lc "RAILS_ENV=production bundle exec rails assets:precompile"
sudo systemctl start server-manager server-manager-sidekiq
```

## Uninstalling

```bash
# Stop services
systemctl stop server-manager server-manager-sidekiq caddy salt-api salt-master

# Remove application
rm -rf /opt/veracity/app

# Remove services
rm /etc/systemd/system/server-manager*.service
systemctl daemon-reload

# Remove user
userdel -r deploy
```
