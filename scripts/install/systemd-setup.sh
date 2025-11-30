#!/bin/bash
#
# systemd-setup.sh - Systemd services installation and configuration
# Sets up server-manager and server-manager-sidekiq services
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SERVICE_SCRIPT_DIR}/lib/common.sh"

readonly APP_DIR="/opt/veracity/app"
readonly DEPLOY_USER="deploy"
readonly DEPLOY_HOME="/home/${DEPLOY_USER}"

#######################################
# Install systemd service files
#######################################
install_systemd_services() {
  section "Installing Systemd Services"

  step "Installing Puma service..."

  # Create server-manager.service
  cat > /etc/systemd/system/server-manager.service << EOF
[Unit]
Description=Veracity Server Manager - Puma Rails Server
After=network.target postgresql.service redis.service salt-master.service salt-api.service
Requires=postgresql.service redis.service

[Service]
Type=simple
User=${DEPLOY_USER}
Group=${DEPLOY_USER}
WorkingDirectory=${APP_DIR}
Environment=RAILS_ENV=production
Environment=PATH=${DEPLOY_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=${APP_DIR}/.env.production
ExecStart=/bin/bash -lc 'eval "\$(\${HOME}/.local/bin/mise activate bash)" && bundle exec puma -C config/puma.rb'
Restart=always
RestartSec=10
StandardOutput=append:${APP_DIR}/log/puma.log
StandardError=append:${APP_DIR}/log/puma.log
SyslogIdentifier=veracity-puma

# Security
PrivateTmp=true
# Note: NoNewPrivileges must be false to allow Salt commands via sudo

[Install]
WantedBy=multi-user.target
EOF

  success "Puma service installed"

  step "Installing Sidekiq service..."

  # Create server-manager-sidekiq.service
  cat > /etc/systemd/system/server-manager-sidekiq.service << EOF
[Unit]
Description=Veracity Server Manager - Sidekiq Background Worker
After=network.target redis.service postgresql.service salt-api.service
Requires=redis.service postgresql.service

[Service]
Type=simple
User=${DEPLOY_USER}
WorkingDirectory=${APP_DIR}
Environment=RAILS_ENV=production
Environment=PATH=${DEPLOY_HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=${APP_DIR}/.env.production
ExecStart=/bin/bash -lc 'eval "\$(\${HOME}/.local/bin/mise activate bash)" && bundle exec sidekiq -C config/sidekiq.yml'
Restart=always
RestartSec=10
StandardOutput=append:${APP_DIR}/log/sidekiq.log
StandardError=append:${APP_DIR}/log/sidekiq.log
SyslogIdentifier=veracity-sidekiq

# Security
PrivateTmp=true
# Note: NoNewPrivileges must be false to allow Salt commands via sudo

[Install]
WantedBy=multi-user.target
EOF

  success "Sidekiq service installed"
}

#######################################
# Reload systemd daemon
#######################################
reload_systemd() {
  step "Reloading systemd daemon..."
  execute systemctl daemon-reload
  success "Systemd daemon reloaded"
}

#######################################
# Enable and start services
#######################################
start_services() {
  step "Enabling and starting services..."

  # Enable services
  execute systemctl enable server-manager
  execute systemctl enable server-manager-sidekiq

  # Start Puma
  execute systemctl start server-manager

  if wait_for_service server-manager; then
    success "Puma service started"
  else
    error "Failed to start Puma service"
    systemctl status server-manager --no-pager -l || true
    return 1
  fi

  # Start Sidekiq
  execute systemctl start server-manager-sidekiq

  if wait_for_service server-manager-sidekiq; then
    success "Sidekiq service started"
  else
    error "Failed to start Sidekiq service"
    systemctl status server-manager-sidekiq --no-pager -l || true
    return 1
  fi
}

#######################################
# Display service status
#######################################
display_service_status() {
  section "Service Status"

  systemctl status server-manager --no-pager -l | head -15
  echo ""
  systemctl status server-manager-sidekiq --no-pager -l | head -15
}

#######################################
# Setup systemd services
#######################################
setup_systemd() {
  install_systemd_services
  reload_systemd
  start_services
  display_service_status

  success "Systemd services setup complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_systemd
fi
