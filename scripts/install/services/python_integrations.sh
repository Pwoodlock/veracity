#!/bin/bash
#
# python_integrations.sh - Python integration dependencies
# Installs all Python packages required for external API integrations
# - PyVulnerabilityLookup (CVE monitoring)
# - hcloud (Hetzner Cloud API)
# - proxmoxer (Proxmox VE API)
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SERVICE_SCRIPT_DIR}/../lib/common.sh"

# Configuration
# Application configuration (don't redeclare if already set)
if [[ -z "${APP_DIR:-}" ]]; then
  readonly APP_DIR="/opt/veracity/app"
fi
readonly INTEGRATIONS_VENV_DIR="${APP_DIR}/integrations_venv"
readonly PYTHON_WRAPPER="${APP_DIR}/bin/integration_python"
if [[ -z "${DEPLOY_USER:-}" ]]; then
  readonly DEPLOY_USER="deploy"
fi

#######################################
# Install Python 3 and venv
#######################################
install_python() {
  step "Installing Python 3 and virtual environment support..."

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
      install_packages python3 python3-venv python3-pip python3-full
      ;;

    rocky|almalinux|rhel)
      install_packages python3 python3-pip python3-virtualenv
      ;;

    *)
      fatal "Unsupported OS for Python installation: ${OS_ID}"
      ;;
  esac

  # Verify Python installation
  if ! command_exists python3; then
    fatal "Python 3 installation failed"
  fi

  local python_version
  python_version=$(python3 --version 2>&1 | awk '{print $2}')

  # Verify Python version >= 3.8 (required for all packages)
  local major=$(echo "$python_version" | cut -d. -f1)
  local minor=$(echo "$python_version" | cut -d. -f2)

  if [ "$major" -lt 3 ] || ([ "$major" -eq 3 ] && [ "$minor" -lt 8 ]); then
    fatal "Python 3.8+ required, found: ${python_version}"
  fi

  success "Python ${python_version} installed (>= 3.8 required)"
}

#######################################
# Create Python virtual environment
#######################################
create_virtualenv() {
  step "Creating Python virtual environment at ${INTEGRATIONS_VENV_DIR}..."

  # Remove existing venv if present
  if [ -d "${INTEGRATIONS_VENV_DIR}" ]; then
    warning "Existing virtual environment found, recreating..."
    rm -rf "${INTEGRATIONS_VENV_DIR}"
  fi

  # Create venv
  execute python3 -m venv "${INTEGRATIONS_VENV_DIR}"

  # Set ownership
  execute chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${INTEGRATIONS_VENV_DIR}"

  success "Virtual environment created"
}

#######################################
# Install all Python integration packages
#######################################
install_integration_packages() {
  step "Installing Python integration packages..."

  # Upgrade pip first with retry
  info "Upgrading pip..."
  if ! retry_command 3 5 "${INTEGRATIONS_VENV_DIR}/bin/pip" install --upgrade pip; then
    warning "Failed to upgrade pip, continuing with existing version"
  fi

  # Install all required packages with retry logic for network resilience
  info "Installing integration packages (with retry on failure):"
  echo "  • pyvulnerabilitylookup (CVE monitoring)"
  echo "  • hcloud (Hetzner Cloud API)"
  echo "  • proxmoxer (Proxmox VE API)"
  echo "  • urllib3 (HTTP library)"
  echo "  • requests (HTTP library)"
  echo ""

  if ! retry_command 3 5 "${INTEGRATIONS_VENV_DIR}/bin/pip" install \
    "pyvulnerabilitylookup>=2.0.0" \
    "hcloud>=1.33.0" \
    "proxmoxer>=2.0.0" \
    "urllib3>=2.0.0" \
    "requests>=2.28.0"; then
    error "Failed to install Python integration packages after multiple attempts"
    error "This may be due to:"
    error "  - Network connectivity issues"
    error "  - PyPI service unavailability"
    error "  - Python build dependencies missing"
    error "Check ${LOG_FILE} for detailed error messages"
    fatal "Failed to install Python integration packages"
  fi

  success "Python integration packages installed successfully"
}

#######################################
# Test package installations
#######################################
test_package_installations() {
  step "Testing Python package installations..."

  local all_ok=true

  # Test PyVulnerabilityLookup
  if "${INTEGRATIONS_VENV_DIR}/bin/python" -c "import pyvulnerabilitylookup; print('PyVulnerabilityLookup:', pyvulnerabilitylookup.__version__)" >> "${LOG_FILE}" 2>&1; then
    local pyvuln_version
    pyvuln_version=$(\"${INTEGRATIONS_VENV_DIR}/bin/python\" -c "import pyvulnerabilitylookup; print(pyvulnerabilitylookup.__version__)" 2>/dev/null)
    success "PyVulnerabilityLookup ${pyvuln_version} OK"
  else
    error "PyVulnerabilityLookup test failed"
    all_ok=false
  fi

  # Test hcloud
  if "${INTEGRATIONS_VENV_DIR}/bin/python" -c "import hcloud; print('hcloud:', hcloud.__version__)" >> "${LOG_FILE}" 2>&1; then
    local hcloud_version
    hcloud_version=$(\"${INTEGRATIONS_VENV_DIR}/bin/python\" -c "import hcloud; print(hcloud.__version__)" 2>/dev/null)
    success "hcloud ${hcloud_version} OK"
  else
    error "hcloud test failed"
    all_ok=false
  fi

  # Test proxmoxer
  if "${INTEGRATIONS_VENV_DIR}/bin/python" -c "import proxmoxer; print('proxmoxer:', proxmoxer.__version__)" >> "${LOG_FILE}" 2>&1; then
    local proxmoxer_version
    proxmoxer_version=$(\"${INTEGRATIONS_VENV_DIR}/bin/python\" -c "import proxmoxer; print(proxmoxer.__version__)" 2>/dev/null)
    success "proxmoxer ${proxmoxer_version} OK"
  else
    error "proxmoxer test failed"
    all_ok=false
  fi

  # Test urllib3
  if "${INTEGRATIONS_VENV_DIR}/bin/python" -c "import urllib3; print('urllib3:', urllib3.__version__)" >> "${LOG_FILE}" 2>&1; then
    success "urllib3 OK"
  else
    warning "urllib3 test failed (non-critical)"
  fi

  # Test requests
  if "${INTEGRATIONS_VENV_DIR}/bin/python" -c "import requests; print('requests:', requests.__version__)" >> "${LOG_FILE}" 2>&1; then
    success "requests OK"
  else
    warning "requests test failed (non-critical)"
  fi

  if [ "$all_ok" = true ]; then
    success "All critical packages verified"
    return 0
  else
    error "Some critical packages failed verification"
    return 1
  fi
}

#######################################
# Create Python wrapper script
#######################################
create_wrapper_script() {
  step "Creating Python wrapper script..."

  # Create bin directory if it doesn't exist
  mkdir -p "${APP_DIR}/bin"

  # Create wrapper script
  cat > "${PYTHON_WRAPPER}" << 'EOF'
#!/bin/bash
# Python wrapper for integrations (Hetzner, Proxmox, CVE monitoring)
# Uses the virtual environment with all integration packages
/opt/veracity/app/integrations_venv/bin/python "$@"
EOF

  # Make executable
  execute chmod +x "${PYTHON_WRAPPER}"
  execute chown "${DEPLOY_USER}:${DEPLOY_USER}" "${PYTHON_WRAPPER}"

  success "Wrapper script created at ${PYTHON_WRAPPER}"
}

#######################################
# Create symlinks for Python scripts
#######################################
create_python_script_symlinks() {
  step "Making Python integration scripts executable..."

  # Make hetzner_cloud.py executable
  if [ -f "${APP_DIR}/lib/scripts/hetzner_cloud.py" ]; then
    execute chmod +x "${APP_DIR}/lib/scripts/hetzner_cloud.py"
    # Update shebang to use our wrapper
    execute chown "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}/lib/scripts/hetzner_cloud.py"
    success "Hetzner Cloud script configured"
  else
    warning "Hetzner Cloud script not found (will be available after app deployment)"
  fi

  # Make proxmox_api.py executable
  if [ -f "${APP_DIR}/lib/scripts/proxmox_api.py" ]; then
    execute chmod +x "${APP_DIR}/lib/scripts/proxmox_api.py"
    execute chown "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}/lib/scripts/proxmox_api.py"
    success "Proxmox API script configured"
  else
    warning "Proxmox API script not found (will be available after app deployment)"
  fi
}

#######################################
# Display integration information
#######################################
display_integration_info() {
  section "Python Integration Configuration"

  info "Virtual Environment: ${INTEGRATIONS_VENV_DIR}"
  info "Python Wrapper: ${PYTHON_WRAPPER}"

  echo ""
  info "Installed Python packages:"
  echo "  • PyVulnerabilityLookup - CVE vulnerability scanning"
  echo "  • hcloud - Hetzner Cloud API client"
  echo "  • proxmoxer - Proxmox VE API client"
  echo "  • urllib3 - HTTP library"
  echo "  • requests - HTTP library"

  echo ""
  info "Integration features enabled:"
  echo "  • CVE vulnerability monitoring"
  echo "  • Hetzner Cloud server management"
  echo "  • Hetzner Cloud snapshot operations"
  echo "  • Proxmox VE VM/LXC control"
  echo "  • Proxmox VE snapshot management"

  echo ""
  info "Configure API keys via the web UI after installation"
}

#######################################
# Setup Python integrations for Veracity
# Main function that orchestrates Python setup
#######################################
setup_python_integrations() {
  section "Installing Python Integration Dependencies"

  install_python
  create_virtualenv
  install_integration_packages
  test_package_installations
  create_wrapper_script
  create_python_script_symlinks
  display_integration_info

  success "Python integrations setup complete!"

  # Export variables for use in .env
  export PYTHON_INTEGRATIONS_ENABLED="true"
  export PYTHON_INTEGRATIONS_PATH="${PYTHON_WRAPPER}"
  export VULNERABILITY_LOOKUP_ENABLED="true"
  export VULNERABILITY_LOOKUP_URL="${CVE_URL:-https://vulnerability.circl.lu}"
  export VULNERABILITY_LOOKUP_SCAN_SCHEDULE="${CVE_SCHEDULE:-0 2 * * *}"
  export VULNERABILITY_LOOKUP_PYTHON_PATH="${PYTHON_WRAPPER}"
  export VULNERABILITY_LOOKUP_TIMEOUT="60"
  export HETZNER_PYTHON_PATH="${PYTHON_WRAPPER}"
  export PROXMOX_PYTHON_PATH="${PYTHON_WRAPPER}"
}

# If script is executed directly, run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_python_integrations
fi
