#!/bin/bash
#
# firewall.sh - UFW firewall configuration
# Configures firewall rules for Veracity
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SERVICE_SCRIPT_DIR}/lib/common.sh"

#######################################
# Install UFW if needed
#######################################
install_ufw() {
  if command_exists ufw; then
    info "UFW is already installed"
    return 0
  fi

  step "Installing UFW..."
  install_packages ufw
  success "UFW installed"
}

#######################################
# Configure firewall rules
#######################################
configure_firewall() {
  section "Configuring Firewall"

  step "Setting up UFW rules..."

  # Default policies
  execute ufw --force default deny incoming
  execute ufw --force default allow outgoing

  # Allow SSH (CRITICAL - do this first!)
  execute ufw allow 22/tcp comment "SSH"
  success "SSH allowed (port 22)"

  # Allow HTTP and HTTPS for web access
  execute ufw allow 80/tcp comment "HTTP"
  execute ufw allow 443/tcp comment "HTTPS"
  success "HTTP/HTTPS allowed (ports 80, 443)"

  # Allow Salt ports for minion communication
  execute ufw allow 4505/tcp comment "Salt Publisher"
  execute ufw allow 4506/tcp comment "Salt Request Server"
  success "Salt ports allowed (4505, 4506)"

  # Gotify port is NOT exposed - it's behind Caddy reverse proxy
  # Only accessible via ${GOTIFY_URL} with HTTPS
  info "Gotify running on localhost:${GOTIFY_PORT:-8080} (behind Caddy, not exposed)"

  # Enable UFW
  if ! is_firewall_active; then
    execute ufw --force enable
    success "UFW enabled"
  else
    execute ufw reload
    success "UFW reloaded"
  fi
}

#######################################
# Display firewall status
#######################################
display_firewall_status() {
  section "Firewall Status"
  ufw status verbose
}

#######################################
# Setup firewall
#######################################
setup_firewall() {
  install_ufw
  configure_firewall
  display_firewall_status

  success "Firewall setup complete!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_firewall
fi
