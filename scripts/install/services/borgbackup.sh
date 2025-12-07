#!/bin/bash
#
# borgbackup.sh - BorgBackup installation
# Installs BorgBackup for the backup/clone features
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SERVICE_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/validators.sh
source "${SERVICE_SCRIPT_DIR}/../lib/validators.sh"

#######################################
# Install BorgBackup
# Globals:
#   OS_ID
#######################################
install_borgbackup() {
  section "Installing BorgBackup"

  # Detect OS if not already set
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
      spinner "Installing BorgBackup" install_packages borgbackup
      ;;
    rocky|almalinux|rhel)
      # EPEL required for BorgBackup on RHEL-based systems
      if ! rpm -q epel-release &>/dev/null; then
        info "Installing EPEL repository..."
        execute dnf install -y epel-release || execute yum install -y epel-release
      fi
      spinner "Installing BorgBackup" install_packages borgbackup
      ;;
    *)
      warning "Unsupported OS for BorgBackup auto-installation: ${OS_ID}"
      warning "BorgBackup must be installed manually for backup features to work"
      return 0
      ;;
  esac

  success "BorgBackup installed"
}

#######################################
# Verify BorgBackup installation
#######################################
verify_borgbackup() {
  step "Verifying BorgBackup installation..."

  if ! command -v borg &>/dev/null; then
    warning "BorgBackup command 'borg' not found in PATH"
    warning "Backup features will not work until BorgBackup is installed"
    return 1
  fi

  local borg_version
  borg_version=$(borg --version 2>/dev/null | awk '{print $2}')

  if [ -n "$borg_version" ]; then
    success "BorgBackup ${borg_version} verified"
    return 0
  else
    warning "BorgBackup installed but version could not be determined"
    return 1
  fi
}

#######################################
# Setup BorgBackup for Veracity
# Main function that orchestrates BorgBackup setup
#######################################
setup_borgbackup() {
  install_borgbackup

  if verify_borgbackup; then
    success "BorgBackup setup complete!"
    local version
    version=$(borg --version 2>/dev/null | awk '{print $2}')
    info "BorgBackup version: ${version}"
  else
    warning "BorgBackup verification failed"
    warning "Backup/clone features may not work properly"
  fi
}

# If script is executed directly, run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_borgbackup
fi
