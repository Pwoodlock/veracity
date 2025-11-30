# Veracity Installation Guide

Complete installation guide for Veracity Server Manager - a comprehensive infrastructure management platform powered by SaltStack.

## Quick Start

For a fully automated installation on a fresh Ubuntu 22.04/24.04, Debian 11/12, or Rocky Linux 9 server:

```bash
curl -sSL https://raw.githubusercontent.com/Pwoodlock/veracity-/main/install.sh | sudo bash
```

**Or clone and run locally:**

```bash
git clone https://github.com/Pwoodlock/veracity-.git
cd veracity-
sudo ./install.sh
```

### Installation with Error Recovery

The installer includes comprehensive error handling with checkpoint support:

```bash
# Resume installation after fixing errors
sudo ./install.sh --resume

# Rollback all changes
sudo ./install.sh --rollback

# Run diagnostic check
sudo ./scripts/install/diagnose.sh
```

## System Requirements

### Minimum Requirements
- **OS**: Ubuntu 20.04/22.04/24.04, Debian 11/12
- **CPU**: 2 cores
- **RAM**: 2GB minimum (4GB recommended)
- **Disk**: 20GB free space
- **Network**: Internet connectivity for package downloads

### Recommended for Production
- **CPU**: 4+ cores
- **RAM**: 4GB+ (8GB for larger deployments)
- **Disk**: 50GB+ SSD storage
- **Network**: Static IP or domain with DNS configured

> **Note:** RHEL-based distributions (Rocky Linux, AlmaLinux) support is planned.

## What Gets Installed

The installer sets up a complete, Veracity infrastructure management system:

### Core Services
- **PostgreSQL 14+** - Primary database
- **Redis 7+** - Caching and job queues
- **SaltStack 3007** - Minion management and automation
- **Ruby 3.3.6** (via Mise) - Application runtime
- **Node.js 24 LTS** - Asset compilation
- **Caddy** - Reverse proxy with automatic HTTPS

### Application Components
- **Puma** - Rails application server
- **Sidekiq** - Background job processing
- **Systemd services** - Auto-start and monitoring
- **UFW Firewall** - Security rules

### Integrated Features (All Installed)
- **Gotify** - Push notifications (binary)
- **CVE Monitoring** - Automatic vulnerability scanning (Python)
- **Proxmox API** - Virtual machine management
- **Hetzner Cloud API** - Cloud server management

## Installation Process

### 1. Pre-Installation

Before running the installer, ensure:

- You have root/sudo access
- Server has a fresh OS installation (recommended)
- DNS is configured (for HTTPS with Let's Encrypt)
- Ports 80, 443, 4505, 4506 are accessible

### 2. Interactive Prompts

The installer will ask for:

**Required:**
- Domain or IP address (e.g., `example.com`)
- Enable HTTPS? (yes/no)
- Admin email address
- Admin password (or auto-generate)
- Database username (default: `servermanager`)
- Server timezone (default: UTC)

**All Features Installed Automatically:**
- Gotify push notifications (configure via UI)
- CVE vulnerability scanning (active)
- Proxmox API support (add tokens via UI)
- Hetzner Cloud API support (add tokens via UI)

### 3. Installation Steps

The installer performs these steps automatically:

1. ✓ System prerequisites check
2. ✓ Install PostgreSQL and create database
3. ✓ Install and configure Redis
4. ✓ Install Salt Master and Salt API
5. ✓ Install Ruby 3.3.6 via Mise
6. ✓ Install Node.js 24 LTS
7. ✓ Install Caddy and configure automatic HTTPS
8. ✓ Install Gotify push notification server (binary)
9. ✓ Install Python integrations (CVE, Hetzner, Proxmox)
10. ✓ Clone application and install dependencies
11. ✓ Run database migrations and seed data
12. ✓ Precompile assets
13. ✓ Create admin user
14. ✓ Install systemd services
15. ✓ Configure firewall
16. ✓ Run health checks

**Estimated time: 15-20 minutes** (depends on internet speed and server specs)

### 4. Post-Installation

After installation completes:

1. **Access Dashboard**: Navigate to `https://your-domain.com`
2. **Login**: Use the admin email and password
3. **Enable 2FA**: Go to Settings → Security
4. **Configure Gotify**: Go to Settings → Notifications to add Gotify app token
5. **Configure Proxmox**: Go to Settings → Proxmox to add API tokens
6. **Configure Hetzner**: Go to Settings → Hetzner to add API tokens
7. **Review CVE Scans**: Check Settings → Vulnerability Monitoring
8. **Install Minions**: Run on servers you want to manage:
   ```bash
   curl -sSL https://your-domain.com/install/minion.sh | sudo bash
   ```
9.  **Accept Minion Keys**: Go to Onboarding page and accept keys

## File Locations

```
/opt/veracity/app/              # Application directory
├── app/                          # Rails application code
├── config/                       # Configuration files
├── log/                          # Application logs
├── .env.production               # Environment variables
├── public/                       # Static assets
├── cve_venv/                     # Python virtual environment for CVE monitoring
└── bin/cve_python                # Python wrapper script

/home/deploy/                     # Deploy user home
└── .local/share/mise/            # Ruby installation (via Mise)

/var/log/                         # System logs
├── veracity-install.log          # Installation log
└── caddy/                        # Caddy access logs

/var/lib/veracity-installer/      # Installation state
├── checkpoints                   # Phase completion tracking
├── errors.log                    # Error log
├── rollback.sh                   # Auto-generated rollback script
└── config                        # Saved installation config

/root/veracity-install-credentials.txt  # Saved credentials

/opt/gotify/                      # Gotify installation

/etc/systemd/system/
├── server-manager.service        # Puma service
└── server-manager-sidekiq.service  # Sidekiq service

/etc/caddy/Caddyfile              # Caddy configuration
/srv/salt/                        # Salt states
/srv/pillar/                      # Salt pillars
```

## Managing Services

### View Service Status
```bash
systemctl status server-manager
systemctl status server-manager-sidekiq
systemctl status caddy
systemctl status postgresql
systemctl status redis
systemctl status salt-master
systemctl status salt-api
systemctl status gotify
```

### Restart Services
```bash
systemctl restart server-manager
systemctl restart server-manager-sidekiq
```

### View Logs
```bash
# Application logs
tail -f /opt/veracity/app/log/production.log

# Puma logs
tail -f /opt/veracity/app/log/puma.log

# Sidekiq logs
tail -f /opt/veracity/app/log/sidekiq.log

# System logs
journalctl -u server-manager -f
journalctl -u server-manager-sidekiq -f
```

## Troubleshooting

### Installation Failed

The installer includes comprehensive error handling with detailed diagnostics. When an error occurs:

1. **Review the error message** - The installer displays context-specific error information
2. **Run diagnostics** - Check system state with the diagnostic tool:
   ```bash
   sudo ./scripts/install/diagnose.sh
   ```

3. **Check logs**:
   ```bash
   # Installation log
   tail -n 100 /var/log/veracity-install.log

   # Error log with detailed context
   cat /var/lib/veracity-installer/errors.log

   # View completed phases
   cat /var/lib/veracity-installer/checkpoints
   ```

4. **Resume installation** after fixing issues:
   ```bash
   sudo ./install.sh --resume
   ```

5. **Rollback if needed**:
   ```bash
   sudo ./install.sh --rollback
   ```

### Common Installation Issues

#### Port Already in Use

If you see "Port X is already in use" errors:

```bash
# Find what's using the port
sudo ss -tlnp | grep :PORT_NUMBER

# Stop the conflicting service
sudo systemctl stop SERVICE_NAME
```

#### Salt API Not Starting

Salt API can take 10-15 seconds to fully initialize. If it fails:

```bash
# Check Salt API status
sudo systemctl status salt-api

# View logs
sudo journalctl -u salt-api -n 50 --no-pager

# Restart if needed
sudo systemctl restart salt-master
sudo systemctl restart salt-api
```

#### Ruby Installation Timeout

Ruby compilation requires significant resources. If it fails:

```bash
# Check available memory
free -h

# Check available disk space
df -h

# Resume installation (will retry from last successful checkpoint)
sudo ./install.sh --resume
```

#### PostgreSQL Connection Failed

```bash
# Check PostgreSQL is running
sudo systemctl status postgresql

# Test connection
sudo -u postgres psql -c '\l'

# Check logs
sudo journalctl -u postgresql -n 50 --no-pager
```

### Services Not Starting

Check service status and logs:
```bash
systemctl status server-manager
journalctl -u server-manager -n 50 --no-pager

# Check dependencies
systemctl status postgresql redis-server salt-api
```

### Database Connection Issues

Test database connectivity:
```bash
sudo -u postgres psql -d server_manager_production
```

### Rails Console Access

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
user.password = 'new-secure-password'
user.password_confirmation = 'new-secure-password'
user.save!
\""
```

### Get Installation State

View what phases have completed and which failed:

```bash
# View checkpoints
cat /var/lib/veracity-installer/checkpoints

# View error summary
cat /var/lib/veracity-installer/errors.log

# Run full diagnostic
sudo ./scripts/install/diagnose.sh
```

## Firewall Configuration

Default UFW rules:
```
22/tcp   - SSH
80/tcp   - HTTP
443/tcp  - HTTPS
4505/tcp - Salt Publisher
4506/tcp - Salt Request Server
```

### Add Custom Rules
```bash
ufw allow 8080/tcp comment "Custom service"
ufw reload
```

## Upgrading

### Automated Update (Recommended)

To update Veracity to the latest version from GitHub, use the included update script:

```bash
sudo /opt/veracity/app/scripts/update.sh
```

This automated script will:
1. Create a backup of your current installation
2. Pull the latest code from GitHub (`main` branch)
3. Update Ruby gems (exact versions from `Gemfile.lock`)
4. Update Node packages (exact versions from `yarn.lock`)
5. Run database migrations
6. Precompile assets
7. Restart services
8. Run health checks

**Version Control:**
- All dependency versions are controlled by `Gemfile.lock` and `yarn.lock` in the repository
- The update script uses `--deployment` and `--frozen-lockfile` flags to ensure exact version matching
- You'll get the same tested versions as the developer

**Backup Location:** `/opt/backups/veracity-YYYYMMDD-HHMMSS/`

### Manual Update

If you prefer to update manually:

```bash
# Stop services
sudo systemctl stop server-manager server-manager-sidekiq

# Pull latest code
cd /opt/veracity/app
sudo -u deploy git pull origin main

# Update dependencies (uses exact versions from lock files)
sudo -u deploy bash -lc "cd /opt/veracity/app && bundle install --deployment"
sudo -u deploy bash -lc "cd /opt/veracity/app && yarn install --frozen-lockfile"

# Run migrations
sudo -u deploy bash -lc "cd /opt/veracity/app && RAILS_ENV=production bundle exec rails db:migrate"

# Precompile assets
sudo -u deploy bash -lc "cd /opt/veracity/app && RAILS_ENV=production bundle exec rails assets:precompile"

# Start services
sudo systemctl start server-manager server-manager-sidekiq

# Check status
sudo systemctl status server-manager server-manager-sidekiq
```

### Checking for Updates

To see if updates are available without installing:

```bash
cd /opt/veracity/app
sudo -u deploy git fetch origin main
sudo -u deploy git log HEAD..origin/main --oneline
```

### Rolling Back an Update

If an update causes issues, you can rollback to a previous version:

```bash
# Find backup directory
ls -la /opt/backups/

# Stop services
sudo systemctl stop server-manager server-manager-sidekiq

# Restore from backup
sudo cp -r /opt/backups/veracity-YYYYMMDD-HHMMSS/server-manager /opt/

# Start services
sudo systemctl start server-manager server-manager-sidekiq
```

## Uninstalling

To completely remove Veracity:

```bash
# Stop services
systemctl stop server-manager server-manager-sidekiq caddy salt-api salt-master

# Remove application
rm -rf /opt/veracity/app

# Remove services
rm /etc/systemd/system/server-manager*.service
systemctl daemon-reload

# Optionally remove dependencies
apt-get remove --purge postgresql redis-server salt-master salt-api caddy
userdel -r deploy
```

## Security Best Practices

1. **Enable 2FA** for all admin accounts
2. **Change default passwords** immediately after installation
3. **Keep system updated**: `apt update && apt upgrade` (Ubuntu/Debian)
4. **Configure backup strategy** for database and application data
5. **Monitor logs regularly** for suspicious activity
6. **Use strong passwords** for all services
7. **Restrict SSH access** to specific IPs if possible
8. **Enable fail2ban** for additional brute-force protection

## Support & Documentation

- **Documentation**: https://github.com/Pwoodlock/veracity-/wiki
- **Issues**: https://github.com/Pwoodlock/veracity-/issues
- **Discussions**: https://github.com/Pwoodlock/veracity-/discussions
- **Email**: support@veracity.io (if configured)

## License

Veracity is open-source software licensed under the MIT License.

---

**Need help?** Open an issue on GitHub or check the troubleshooting section above.
