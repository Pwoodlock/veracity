#!/bin/bash
# Veracity Update Script
# Updates an existing Veracity installation from GitHub main branch
#
# Usage: sudo /opt/veracity/app/scripts/update.sh
#
# This script will:
# 1. Create a backup of the current installation
# 2. Pull the latest code from GitHub
# 3. Update Ruby gems and Node packages
# 4. Run database migrations
# 5. Precompile assets
# 6. Restart services

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
APP_DIR="/opt/veracity/app"
BACKUP_DIR="/opt/backups/veracity-$(date +%Y%m%d-%H%M%S)"
DEPLOY_USER="deploy"

# Functions
info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
  echo -e "${GREEN}[✓]${NC} $1"
}

warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

fatal() {
  error "$1"
  exit 1
}

print_banner() {
  clear
  cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║  ██╗   ██╗███████╗██████╗  █████╗  ██████╗██╗████████╗██╗   ║
║  ██║   ██║██╔════╝██╔══██╗██╔══██╗██╔════╝██║╚══██╔══╝╚██╗  ║
║  ██║   ██║█████╗  ██████╔╝███████║██║     ██║   ██║    ╚██╗ ║
║  ╚██╗ ██╔╝██╔══╝  ██╔══██╗██╔══██║██║     ██║   ██║    ██╔╝ ║
║   ╚████╔╝ ███████╗██║  ██║██║  ██║╚██████╗██║   ██║   ██╔╝  ║
║    ╚═══╝  ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝   ╚═╝   ╚═╝   ║
║                                                              ║
║                      Update Script                           ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

EOF
}

# Pre-flight checks
check_root() {
  if [[ $EUID -ne 0 ]]; then
    fatal "This script must be run as root (use sudo)"
  fi
}

check_installation() {
  if [[ ! -d "$APP_DIR" ]]; then
    fatal "Veracity installation not found at $APP_DIR"
  fi

  if [[ ! -d "$APP_DIR/.git" ]]; then
    fatal "Not a git repository. Cannot update."
  fi
}

# Backup current installation
create_backup() {
  info "Creating backup at $BACKUP_DIR..."

  mkdir -p "$BACKUP_DIR"

  # Backup application code
  cp -r "$APP_DIR" "$BACKUP_DIR/" 2>/dev/null || true

  # Backup database (optional - commented out for safety)
  # sudo -u postgres pg_dump server_manager_production > "$BACKUP_DIR/database.sql"

  success "Backup created at $BACKUP_DIR"
  info "Note: Database backup not included. Run manually if needed:"
  info "  sudo -u postgres pg_dump server_manager_production > $BACKUP_DIR/database.sql"
}

# Stop services
stop_services() {
  info "Stopping services..."

  systemctl stop server-manager || warning "server-manager service not running"
  systemctl stop server-manager-sidekiq || warning "server-manager-sidekiq service not running"

  success "Services stopped"
}

# Update code from GitHub
update_code() {
  info "Pulling latest code from GitHub..."

  cd "$APP_DIR"

  # Fetch latest changes
  sudo -u "$DEPLOY_USER" git fetch origin main

  # Show what will be updated
  local current_commit=$(sudo -u "$DEPLOY_USER" git rev-parse HEAD)
  local latest_commit=$(sudo -u "$DEPLOY_USER" git rev-parse origin/main)

  if [[ "$current_commit" == "$latest_commit" ]]; then
    info "Already up to date!"
    return 0
  fi

  info "Current commit: ${current_commit:0:7}"
  info "Latest commit:  ${latest_commit:0:7}"

  # Pull changes
  sudo -u "$DEPLOY_USER" git pull origin main

  success "Code updated successfully"
}

# Update dependencies
update_dependencies() {
  info "Updating Ruby gems..."

  cd "$APP_DIR"
  sudo -u "$DEPLOY_USER" bash -c "export PATH=/home/${DEPLOY_USER}/.rbenv/shims:\$PATH && bundle install --deployment --without development test"

  success "Ruby gems updated"

  info "Updating Node packages..."

  sudo -u "$DEPLOY_USER" bash -c "export PATH=/home/${DEPLOY_USER}/.rbenv/shims:\$PATH && yarn install --production --frozen-lockfile"

  success "Node packages updated"
}

# Update Python virtual environment
update_python_venv() {
  info "Updating Python virtual environment..."

  cd "$APP_DIR"

  # Check if venv exists
  if [ ! -d "$APP_DIR/cve_venv" ]; then
    warning "Python virtual environment not found - CVE monitoring may not work"
    info "Reinstall with: python3 -m venv $APP_DIR/cve_venv && $APP_DIR/cve_venv/bin/pip install pyvulnerabilitylookup>=2.0.0 requests>=2.28.0"
    return 0
  fi

  # Update pip and packages
  sudo -u "$DEPLOY_USER" bash -c "
    $APP_DIR/cve_venv/bin/pip install --upgrade pip > /dev/null 2>&1
    $APP_DIR/cve_venv/bin/pip install --upgrade pyvulnerabilitylookup>=2.0.0 requests>=2.28.0 > /dev/null 2>&1
  "

  success "Python packages updated"
}

# Run database migrations
run_migrations() {
  info "Running database migrations..."

  cd "$APP_DIR"
  sudo -u "$DEPLOY_USER" bash -c "export PATH=/home/${DEPLOY_USER}/.rbenv/shims:\$PATH && RAILS_ENV=production bundle exec rails db:migrate"

  success "Database migrations complete"
}

# Precompile assets
precompile_assets() {
  info "Precompiling assets (this may take a few minutes)..."

  cd "$APP_DIR"
  sudo -u "$DEPLOY_USER" bash -c "export PATH=/home/${DEPLOY_USER}/.rbenv/shims:\$PATH && RAILS_ENV=production bundle exec rails assets:precompile"

  success "Assets precompiled"
}

# Start services
start_services() {
  info "Starting services..."

  systemctl start server-manager
  systemctl start server-manager-sidekiq

  success "Services started"
}

# Health check
health_check() {
  info "Running health check..."

  sleep 5

  # Check services
  if systemctl is-active --quiet server-manager; then
    success "server-manager is running"
  else
    error "server-manager failed to start"
  fi

  if systemctl is-active --quiet server-manager-sidekiq; then
    success "server-manager-sidekiq is running"
  else
    error "server-manager-sidekiq failed to start"
  fi

  # Check web app
  if curl -sf http://localhost:3000/health > /dev/null 2>&1; then
    success "Web application is responding"
  else
    warning "Web application may not be fully ready yet (give it a minute)"
  fi
}

# Show status
show_status() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Service Status:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  systemctl status server-manager --no-pager --lines=0
  systemctl status server-manager-sidekiq --no-pager --lines=0
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main execution
main() {
  print_banner

  echo -e "${BLUE}Veracity Update Script${NC}"
  echo ""

  # Pre-flight checks
  check_root
  check_installation

  # Confirm update
  echo -e "${YELLOW}This will update Veracity to the latest version from GitHub.${NC}"
  echo ""
  read -p "Do you want to continue? (yes/no): " -r
  echo ""

  if [[ ! $REPLY =~ ^[Yy][Ee]?[Ss]?$ ]]; then
    info "Update cancelled"
    exit 0
  fi

  # Execute update steps
  create_backup
  stop_services
  update_code
  update_dependencies
  update_python_venv
  run_migrations
  precompile_assets
  start_services
  health_check
  show_status

  # Summary
  echo ""
  success "Update complete!"
  echo ""
  info "Backup saved at: $BACKUP_DIR"
  info "To view logs:"
  info "  journalctl -u server-manager -f"
  info "  journalctl -u server-manager-sidekiq -f"
  echo ""
}

# Run main function
main "$@"
