#!/bin/bash
#
# nodejs.sh - Node.js and Yarn installation
# Installs Node.js 24 LTS and Yarn package manager
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SERVICE_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/validators.sh
source "${SERVICE_SCRIPT_DIR}/../lib/validators.sh"

# Node.js version
readonly NODE_MAJOR="24"

#######################################
# Install Node.js
# Globals:
#   OS_ID
#######################################
install_nodejs() {
  section "Installing Node.js ${NODE_MAJOR} LTS"

  # Detect OS if not already set (handles resume scenario)
  if [ -z "${OS_ID:-}" ]; then
    info "OS not detected, detecting now..."
    if [ -f /etc/os-release ]; then
      # shellcheck source=/dev/null
      . /etc/os-release
      export OS_ID="$ID"
      export OS_NAME="$NAME"
      export OS_VERSION="${VERSION_ID:-unknown}"
    else
      fatal "Cannot detect operating system. /etc/os-release not found."
    fi
  fi

  case "${OS_ID}" in
    ubuntu|debian)
      install_nodejs_debian
      ;;
    rocky|almalinux|rhel)
      install_nodejs_rhel
      ;;
    *)
      fatal "Unsupported OS for Node.js installation: ${OS_ID}"
      ;;
  esac
}

#######################################
# Install Node.js on Debian/Ubuntu
#######################################
install_nodejs_debian() {
  step "Installing Node.js for Debian/Ubuntu..."

  # Install prerequisites
  install_packages ca-certificates curl gnupg

  # Add NodeSource repository
  info "Adding NodeSource repository..."

  execute curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh
  execute bash /tmp/nodesource_setup.sh
  execute rm /tmp/nodesource_setup.sh

  # Install Node.js
  spinner "Installing Node.js" install_packages nodejs

  success "Node.js installed"
}

#######################################
# Install Node.js on RHEL/Rocky
#######################################
install_nodejs_rhel() {
  step "Installing Node.js for RHEL/Rocky..."

  # Add NodeSource repository
  info "Adding NodeSource repository..."

  execute curl -fsSL "https://rpm.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh
  execute bash /tmp/nodesource_setup.sh
  execute rm /tmp/nodesource_setup.sh

  # Install Node.js
  spinner "Installing Node.js" install_packages nodejs

  success "Node.js installed"
}

#######################################
# Install Yarn package manager
#######################################
install_yarn() {
  step "Installing Yarn package manager..."

  # Enable corepack (includes Yarn)
  if command_exists corepack; then
    execute corepack enable

    # Pre-download yarn to avoid interactive prompts later
    # Use COREPACK_ENABLE_DOWNLOAD_PROMPT=0 to disable prompts
    info "Downloading Yarn package manager..."
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    execute corepack prepare yarn@stable --activate

    success "Yarn enabled via corepack"
  else
    # Fallback: install via npm
    execute npm install -g yarn
    success "Yarn installed via npm"
  fi
}

#######################################
# Verify Node.js and Yarn installation
#######################################
verify_nodejs() {
  step "Verifying Node.js installation..."

  local node_version
  node_version=$(node --version)
  info "Node.js version: ${node_version}"

  local npm_version
  npm_version=$(npm --version)
  info "npm version: ${npm_version}"

  # Ensure Corepack doesn't prompt during verification
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  local yarn_version
  yarn_version=$(yarn --version)
  info "Yarn version: ${yarn_version}"

  # Check if versions meet requirements
  local node_major_installed
  node_major_installed=$(node --version | grep -oP '\d+' | head -1)

  if [ "$node_major_installed" -ge "$NODE_MAJOR" ]; then
    success "Node.js ${node_major_installed} verified (>= ${NODE_MAJOR})"
  else
    fatal "Node.js version ${node_major_installed} is too old (minimum: ${NODE_MAJOR})"
  fi
}

#######################################
# Configure npm for global packages
#######################################
configure_npm() {
  step "Configuring npm..."

  # Set npm cache directory
  execute mkdir -p /var/cache/npm
  execute npm config set cache /var/cache/npm --global

  # Disable npm update notifier (less noise)
  execute npm config set update-notifier false --global

  success "npm configured"
}

#######################################
# Setup Node.js for Veracity
# Main function that orchestrates Node.js setup
#######################################
setup_nodejs() {
  install_nodejs
  install_yarn
  configure_npm
  verify_nodejs

  success "Node.js setup complete!"
  info "Node.js: $(node --version)"
  info "npm: $(npm --version)"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  info "Yarn: $(yarn --version)"
}

# If script is executed directly, run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_nodejs
fi
