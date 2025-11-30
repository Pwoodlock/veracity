#!/bin/bash
#
# gotify.sh - Gotify push notification server installation
# Installs Gotify via official binary (no Docker)
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SERVICE_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/validators.sh
source "${SERVICE_SCRIPT_DIR}/../lib/validators.sh"

# Default configuration
readonly GOTIFY_PORT="${GOTIFY_PORT:-8080}"
readonly GOTIFY_DATA_DIR="${GOTIFY_DATA_DIR:-/var/lib/gotify}"
readonly GOTIFY_INSTALL_DIR="/opt/gotify"
readonly GOTIFY_USER="gotify"
readonly GOTIFY_ADMIN_USER="${GOTIFY_ADMIN_USER:-admin}"

#######################################
# Detect platform for Gotify binary
#######################################
detect_platform() {
  local arch
  arch=$(uname -m)

  case "$arch" in
    x86_64)
      echo "linux-amd64"
      ;;
    i386|i686)
      echo "linux-386"
      ;;
    armv7l)
      echo "linux-arm-7"
      ;;
    aarch64|arm64)
      echo "linux-arm64"
      ;;
    *)
      fatal "Unsupported architecture: $arch"
      ;;
  esac
}

#######################################
# Get latest Gotify version from GitHub
#######################################
get_latest_version() {
  local version
  version=$(curl -sSf https://api.github.com/repos/gotify/server/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

  if [ -z "$version" ]; then
    fatal "Failed to get latest Gotify version"
  fi

  echo "$version"
}

#######################################
# Create Gotify user
#######################################
create_gotify_user() {
  step "Creating Gotify user..."

  if user_exists "${GOTIFY_USER}"; then
    info "User ${GOTIFY_USER} already exists"
    return 0
  fi

  # Create gotify user
  execute useradd -r -s /bin/false -c "Gotify Server" "${GOTIFY_USER}"

  success "Gotify user created: ${GOTIFY_USER}"
}

#######################################
# Setup Gotify directories
#######################################
setup_gotify_directories() {
  step "Creating Gotify directories..."

  execute mkdir -p "${GOTIFY_INSTALL_DIR}"
  execute mkdir -p "${GOTIFY_DATA_DIR}"
  execute chown -R "${GOTIFY_USER}:${GOTIFY_USER}" "${GOTIFY_DATA_DIR}"

  success "Gotify directories created"
}

#######################################
# Download and install Gotify binary
#######################################
install_gotify_binary() {
  step "Installing Gotify binary..."

  # Ensure unzip is installed
  if ! command -v unzip &>/dev/null; then
    info "Installing unzip..."
    install_packages unzip
  fi

  local platform
  platform=$(detect_platform)
  info "Detected platform: ${platform}"

  local version
  version=$(get_latest_version)
  info "Latest Gotify version: ${version}"

  local download_url="https://github.com/gotify/server/releases/download/v${version}/gotify-${platform}.zip"
  local temp_dir
  temp_dir=$(mktemp -d)

  info "Downloading Gotify from ${download_url}..."
  if ! execute curl -sSL "${download_url}" -o "${temp_dir}/gotify.zip"; then
    rm -rf "${temp_dir}"
    fatal "Failed to download Gotify"
  fi

  info "Extracting Gotify binary..."
  execute unzip -q "${temp_dir}/gotify.zip" -d "${temp_dir}"

  # List extracted files for debugging
  info "Files extracted:"
  find "${temp_dir}" -type f | while read -r file; do
    info "  - $(basename "$file")"
  done

  # Find the gotify binary (name varies by platform and version)
  local binary_name
  # Try multiple possible patterns
  binary_name=$(find "${temp_dir}" -name "gotify-${platform}" -type f 2>/dev/null || true)

  # If not found, try without the platform suffix (some versions just use "gotify")
  if [ -z "$binary_name" ]; then
    binary_name=$(find "${temp_dir}" -name "gotify" -type f 2>/dev/null || true)
  fi

  # If still not found, try any executable file starting with "gotify"
  if [ -z "$binary_name" ]; then
    binary_name=$(find "${temp_dir}" -name "gotify*" -type f -perm /111 2>/dev/null | head -1 || true)
  fi

  if [ -z "$binary_name" ]; then
    error "Available files in archive:"
    find "${temp_dir}" -type f -exec ls -la {} \; 2>/dev/null || true
    rm -rf "${temp_dir}"
    fatal "Gotify binary not found in archive"
  fi

  info "Found binary: $(basename "$binary_name")"

  # Install binary
  execute mv "${binary_name}" "${GOTIFY_INSTALL_DIR}/gotify"
  execute chmod +x "${GOTIFY_INSTALL_DIR}/gotify"
  execute chown "${GOTIFY_USER}:${GOTIFY_USER}" "${GOTIFY_INSTALL_DIR}/gotify"

  # Cleanup
  rm -rf "${temp_dir}"

  success "Gotify binary installed to ${GOTIFY_INSTALL_DIR}/gotify"
}

#######################################
# Create Gotify configuration file
#######################################
create_gotify_config() {
  step "Creating Gotify configuration..."

  cat > "${GOTIFY_DATA_DIR}/config.yml" << EOF
server:
  listenaddr: "127.0.0.1"
  port: ${GOTIFY_PORT}
  ssl:
    enabled: false
  responseheaders:
    Access-Control-Allow-Origin: "*"
    Access-Control-Allow-Methods: "GET,POST"

database:
  dialect: sqlite3
  connection: ${GOTIFY_DATA_DIR}/gotify.db

defaultuser:
  name: ${GOTIFY_ADMIN_USER}
  pass: ${GOTIFY_ADMIN_PASSWORD}

passstrength: 10

uploadedimagesdir: ${GOTIFY_DATA_DIR}/images
EOF

  execute chown "${GOTIFY_USER}:${GOTIFY_USER}" "${GOTIFY_DATA_DIR}/config.yml"
  execute chmod 600 "${GOTIFY_DATA_DIR}/config.yml"

  success "Gotify configuration created"
}

#######################################
# Create Gotify systemd service
#######################################
create_gotify_service() {
  step "Creating Gotify systemd service..."

  cat > /etc/systemd/system/gotify.service << EOF
[Unit]
Description=Gotify Push Notification Server
After=network.target

[Service]
Type=simple
User=${GOTIFY_USER}
Group=${GOTIFY_USER}
WorkingDirectory=${GOTIFY_DATA_DIR}
ExecStart=${GOTIFY_INSTALL_DIR}/gotify
Environment="GOTIFY_SERVER_PORT=${GOTIFY_PORT}"
Environment="GOTIFY_SERVER_LISTENADDR=127.0.0.1"
Environment="GOTIFY_DATABASE_DIALECT=sqlite3"
Environment="GOTIFY_DATABASE_CONNECTION=${GOTIFY_DATA_DIR}/gotify.db"
Environment="GOTIFY_DEFAULTUSER_NAME=${GOTIFY_ADMIN_USER}"
Environment="GOTIFY_DEFAULTUSER_PASS=${GOTIFY_ADMIN_PASSWORD}"
Environment="GOTIFY_UPLOADEDIMAGESDIR=${GOTIFY_DATA_DIR}/images"
Restart=always
RestartSec=10
StandardOutput=append:/var/log/gotify/gotify.log
StandardError=append:/var/log/gotify/gotify.log
SyslogIdentifier=gotify

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${GOTIFY_DATA_DIR}
ReadWritePaths=/var/log/gotify

[Install]
WantedBy=multi-user.target
EOF

  # Create log directory
  execute mkdir -p /var/log/gotify
  execute chown "${GOTIFY_USER}:${GOTIFY_USER}" /var/log/gotify

  execute systemctl daemon-reload
  execute systemctl enable gotify

  success "Gotify systemd service created"
}

#######################################
# Start Gotify service
#######################################
start_gotify() {
  step "Starting Gotify service..."

  execute systemctl start gotify

  if wait_for_service gotify; then
    success "Gotify service started"
  else
    error "Failed to start Gotify service"
    systemctl status gotify --no-pager -l || true
    return 1
  fi
}

#######################################
# Test Gotify installation
#######################################
test_gotify() {
  step "Testing Gotify installation..."

  local max_attempts=30
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if curl -sSf "http://127.0.0.1:${GOTIFY_PORT}/health" -o /dev/null 2>&1; then
      success "Gotify is accessible at http://127.0.0.1:${GOTIFY_PORT}"
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 1
  done

  error "Gotify health check failed after ${max_attempts} attempts"
  return 1
}

#######################################
# Create Gotify application and get token
#######################################
create_gotify_app() {
  step "Creating Gotify application..."

  sleep 3  # Give Gotify time to initialize

  # Create application via API
  local response
  response=$(curl -sSf -X POST "http://127.0.0.1:${GOTIFY_PORT}/application" \
    -u "${GOTIFY_ADMIN_USER}:${GOTIFY_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d '{
      "name": "Veracity",
      "description": "Veracity Server Manager Notifications"
    }' 2>/dev/null || echo "")

  if [ -n "$response" ]; then
    # Extract app token from response
    GOTIFY_APP_TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$GOTIFY_APP_TOKEN" ]; then
      success "Gotify application created"
      info "App Token: ${GOTIFY_APP_TOKEN}"
      return 0
    fi
  fi

  warning "Could not automatically create Gotify application"
  warning "Please create an application manually and configure the token in Veracity"
  return 1
}

#######################################
# Display Gotify information
#######################################
display_gotify_info() {
  section "Gotify Configuration"

  info "Gotify Binary: ${GOTIFY_INSTALL_DIR}/gotify"
  info "Gotify Port: ${GOTIFY_PORT} (localhost only)"
  info "Admin Username: ${GOTIFY_ADMIN_USER}"
  info "Admin Password: ${GOTIFY_ADMIN_PASSWORD}"
  info "Data Directory: ${GOTIFY_DATA_DIR}"

  if [ -n "${GOTIFY_APP_TOKEN:-}" ]; then
    info "App Token: ${GOTIFY_APP_TOKEN}"
  fi

  echo ""
  info "Gotify is configured to run on 127.0.0.1:${GOTIFY_PORT}"
  info "Access via Caddy reverse proxy at: ${RAILS_PROTOCOL}://${RAILS_HOST}/gotify"
  info "Web UI available at: ${RAILS_PROTOCOL}://${RAILS_HOST}/gotify/"

  echo ""
  info "Service status: systemctl status gotify"
  info "Service logs: journalctl -u gotify -f"
}

#######################################
# Setup Gotify for Veracity
# Main function that orchestrates Gotify setup
#######################################
setup_gotify() {
  section "Installing Gotify Push Notification Server (Binary)"

  # Validate required variables
  if [ -z "${GOTIFY_ADMIN_PASSWORD:-}" ]; then
    fatal "GOTIFY_ADMIN_PASSWORD environment variable is required"
  fi

  create_gotify_user
  setup_gotify_directories
  install_gotify_binary
  create_gotify_config
  create_gotify_service
  start_gotify
  test_gotify
  create_gotify_app || true
  display_gotify_info

  success "Gotify setup complete!"

  # Export variables for use in .env
  export GOTIFY_URL="http://127.0.0.1:${GOTIFY_PORT}"
  export GOTIFY_ENABLED="true"
}

# If script is executed directly, run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_gotify
fi
