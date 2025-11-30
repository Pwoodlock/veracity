#!/bin/bash
#
# salt.sh - SaltStack Master and API installation
# Installs Salt Master, Salt API, and configures authentication
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SERVICE_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/validators.sh
source "${SERVICE_SCRIPT_DIR}/../lib/validators.sh"

#######################################
# Install SaltStack using official bootstrap script
# Globals:
#   OS_ID
# Returns:
#   0 on success, 1 on failure
#######################################
install_salt() {
  section "Installing SaltStack"

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

  step "Installing SaltStack via official bootstrap script..."

  # Install prerequisite packages
  info "Installing prerequisites..."
  case "${OS_ID}" in
    ubuntu|debian)
      install_packages curl gnupg python3-cherrypy3
      ;;
    rocky|almalinux|rhel)
      install_packages curl gnupg python3-cherrypy
      ;;
    *)
      fatal "Unsupported OS for Salt installation: ${OS_ID}"
      ;;
  esac

  # Download official Salt bootstrap script (new location as of Oct 2024)
  info "Downloading Salt bootstrap script..."
  execute curl -L https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh -o /tmp/bootstrap-salt.sh

  # Install Salt Master and Salt API (without starting services yet)
  # -M = Install Salt Master
  # -N = Do NOT install Salt Minion
  # -X = Do NOT start services (we'll start them with proper config)
  info "Running Salt bootstrap (this may take a few minutes)..."
  spinner "Installing Salt Master and API" execute sh /tmp/bootstrap-salt.sh -M -N -X

  # Clean up bootstrap script
  execute rm -f /tmp/bootstrap-salt.sh

  success "Salt packages installed via official bootstrap"

  # Install python-pam for Salt's bundled Python (required for PAM authentication)
  step "Installing python-pam for Salt's Python..."
  if [ -x /opt/saltstack/salt/bin/pip3 ]; then
    /opt/saltstack/salt/bin/pip3 install python-pam 2>> "${LOG_FILE}" || warning "Failed to install python-pam for Salt Python"
  fi

  # Also install for system Python (Salt may spawn subprocesses using system Python)
  info "Installing python-pam for system Python..."
  pip3 install --break-system-packages python-pam 2>> "${LOG_FILE}" || warning "Failed to install python-pam for system Python"

  # Add salt user to shadow group (required for PAM to read /etc/shadow)
  if getent group shadow &>/dev/null; then
    usermod -aG shadow salt 2>/dev/null || warning "Failed to add salt user to shadow group"
    info "Added salt user to shadow group for PAM authentication"
  fi

  success "python-pam installed"

  # Verify installation and create symlinks if needed (onedir installation)
  if ! command -v salt-master >/dev/null 2>&1; then
    # Check onedir location
    if [ -x /opt/saltstack/salt/salt-master ]; then
      warning "salt-master found in onedir location, creating symlink..."
      ln -sf /opt/saltstack/salt/salt-master /usr/bin/salt-master
    else
      fatal "Salt Master installation failed - salt-master not found"
    fi
  fi

  if ! command -v salt-api >/dev/null 2>&1; then
    # Check onedir location
    if [ -x /opt/saltstack/salt/salt-api ]; then
      info "salt-api found in onedir location, creating symlink..."
      ln -sf /opt/saltstack/salt/salt-api /usr/bin/salt-api
    else
      fatal "Salt API installation failed - salt-api not found"
    fi
  fi

  # Verify both are now available
  if command -v salt-master >/dev/null 2>&1 && command -v salt-api >/dev/null 2>&1; then
    local salt_version
    salt_version=$(salt --version 2>/dev/null | head -1 || echo "unknown")
    info "Salt version: ${salt_version}"
  else
    fatal "Salt installation verification failed"
  fi
}

#######################################
# Create Salt API user
# Arguments:
#   $1 - Username
#   $2 - Password
#######################################
create_salt_api_user() {
  local username="$1"
  local password="$2"

  step "Creating Salt API user: ${username}..."

  # Create system user for Salt API
  # NOTE: Using /bin/bash instead of /sbin/nologin to allow PAM authentication
  if ! user_exists "${username}"; then
    execute useradd -r -s /bin/bash -c "Salt API User" "${username}"
    success "Created system user: ${username}"
  else
    info "User ${username} already exists"
  fi

  # Set password for PAM authentication
  info "Setting password for Salt API user..."

  # Use chpasswd - the standard and reliable method
  if echo "${username}:${password}" | chpasswd 2>> "${LOG_FILE}"; then
    success "Password set via chpasswd"
  else
    # Fallback: try passwd --stdin (works on some RHEL systems)
    if echo "${password}" | passwd --stdin "${username}" &>> "${LOG_FILE}"; then
      success "Password set via passwd --stdin"
    else
      error "Failed to set password for ${username}"
      fatal "Cannot continue without Salt API user password"
    fi
  fi

  # Verify password was set by checking shadow file has a password hash
  info "Verifying password was set..."
  local shadow_entry
  shadow_entry=$(grep "^${username}:" /etc/shadow 2>/dev/null || true)

  if [ -z "${shadow_entry}" ]; then
    fatal "User ${username} not found in /etc/shadow"
  fi

  # Extract the password field (second field, colon-separated)
  local password_hash
  password_hash=$(echo "${shadow_entry}" | cut -d: -f2)

  # Check password is not empty, locked (!), or disabled (*)
  if [ -z "${password_hash}" ] || [ "${password_hash}" = "!" ] || [ "${password_hash}" = "*" ] || [ "${password_hash}" = "!!" ]; then
    error "Password hash invalid for ${username}: ${password_hash}"
    fatal "Password was not set correctly for Salt API user"
  fi

  success "Password verified in /etc/shadow (hash present)"

  # Verify PAM authentication works using Salt's Python (which has python-pam installed)
  info "Verifying PAM authentication..."
  if [ -x /opt/saltstack/salt/bin/python3 ]; then
    if /opt/saltstack/salt/bin/python3 << PYEOF 2>> "${LOG_FILE}"
import pam
p = pam.pam()
if p.authenticate('${username}', '${password}', service='login'):
    print("PAM authentication verified successfully")
    exit(0)
else:
    print("PAM authentication failed: " + str(p.reason))
    exit(1)
PYEOF
    then
      success "PAM authentication verified with python-pam"
    else
      warning "PAM authentication test failed - will retry after services start"
    fi
  else
    info "Salt Python not yet available - PAM verification will happen during API test"
  fi

  # Configure PAM authentication for salt-api
  info "Configuring PAM authentication for salt-api..."

  # Detect OS and use appropriate PAM includes
  # Ubuntu/Debian use common-auth, RHEL/Rocky use system-auth
  if [ -f /etc/pam.d/common-auth ]; then
    # Debian/Ubuntu style
    cat > /etc/pam.d/salt-api << 'PAMEOF'
auth       include      common-auth
account    include      common-account
PAMEOF
    success "PAM configuration created for salt-api (Debian/Ubuntu style)"
  else
    # RHEL/CentOS/Rocky style
    cat > /etc/pam.d/salt-api << 'PAMEOF'
auth       include      system-auth
account    required     pam_nologin.so
account    include      system-auth
password   include      system-auth
session    include      system-auth
PAMEOF
    success "PAM configuration created for salt-api (RHEL style)"
  fi

  success "Salt API user configured"
}

#######################################
# Configure Salt Master
#######################################
configure_salt_master() {
  step "Configuring Salt Master..."

  local master_config="/etc/salt/master.d/veracity.conf"

  # Create master.d directory if it doesn't exist
  mkdir -p /etc/salt/master.d

  # Create Salt Master configuration
  cat > "${master_config}" << EOF
# Veracity - Salt Master Configuration
# Auto-generated by Veracity installer

# Interface to bind to
interface: 0.0.0.0

# Publishing port
publish_port: 4505

# Return port
ret_port: 4506

# Worker threads
worker_threads: 5

# File roots
file_roots:
  base:
    - /srv/salt
    - /srv/salt/states

# Pillar roots
pillar_roots:
  base:
    - /srv/pillar

# Accept new minions automatically (disable for production)
auto_accept: False

# Keep jobs for 24 hours
keep_jobs: 24

# Timeout for minion responses
timeout: 10

# Log level
log_level: info
log_file: /var/log/salt/master

# Event publisher
event_publisher_workers: 5
EOF

  success "Salt Master configuration created"
}

#######################################
# Configure Salt API
#######################################
configure_salt_api() {
  step "Configuring Salt API..."

  local api_config="/etc/salt/master.d/api.conf"

  # Create Salt API configuration
  cat > "${api_config}" << EOF
# Veracity - Salt API Configuration
# Auto-generated by Veracity installer

rest_cherrypy:
  port: 8001
  host: 127.0.0.1
  disable_ssl: True
  webhook_disable_auth: False

external_auth:
  pam:
    ${SALT_API_USER}:
      - .*
      - '@wheel'
      - '@runner'
      - '@jobs'

# Enable netapi clients (required for Salt 3007+)
netapi_enable_clients:
  - local
  - local_async
  - runner
  - runner_async
  - wheel
  - wheel_async
EOF

  success "Salt API configuration created"
}

#######################################
# Create Salt directories
#######################################
create_salt_directories() {
  step "Creating Salt directories..."

  # Create directories
  mkdir -p /srv/salt/states
  mkdir -p /srv/pillar
  mkdir -p /var/log/salt

  # Set permissions
  chown -R root:root /srv/salt /srv/pillar
  chmod -R 755 /srv/salt /srv/pillar

  success "Salt directories created"
}

#######################################
# Start Salt services
#######################################
start_salt_services() {
  step "Starting Salt services..."

  # Create salt-api systemd service file if it doesn't exist
  # (bootstrap script doesn't create this for onedir installations)
  if [ ! -f /usr/lib/systemd/system/salt-api.service ]; then
    info "Creating salt-api systemd service file..."
    cat > /usr/lib/systemd/system/salt-api.service << 'EOF'
[Unit]
Description=Salt API
Documentation=man:salt-api(1)
After=salt-master.service network-online.target
Wants=network-online.target
Requires=salt-master.service

[Service]
Type=simple
ExecStart=/usr/bin/salt-api
User=root
Group=root
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    success "Created salt-api.service file"
  fi

  # Add systemd configuration override for additional settings
  mkdir -p /etc/systemd/system/salt-api.service.d
  cat > /etc/systemd/system/salt-api.service.d/override.conf << EOF
[Service]
# Ensure CherryPy runs in foreground
Environment="PYTHONUNBUFFERED=1"
# Give Salt Master time to be fully ready
ExecStartPre=/bin/sleep 10
# Always restart on failure
Restart=always
StartLimitInterval=0
# Increase timeout for CherryPy startup
TimeoutStartSec=90
TimeoutStopSec=30
EOF

  execute systemctl daemon-reload

  # Enable and start Salt Master
  execute systemctl enable salt-master
  execute systemctl start salt-master

  if wait_for_service salt-master; then
    success "Salt Master service started"
  else
    fatal "Failed to start Salt Master"
  fi

  # Wait for Salt Master to be fully operational
  info "Waiting for Salt Master to bind to ports..."
  local max_attempts=30
  local attempt=0
  local master_ready=false

  while [ $attempt -lt $max_attempts ]; do
    # Check if Salt Master is listening on both ports
    if ss -tln | grep -q ":4505 " && ss -tln | grep -q ":4506 "; then
      success "Salt Master is listening on ports 4505 and 4506"
      master_ready=true
      break
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  if [ "$master_ready" != "true" ]; then
    error "Salt Master did not bind to ports after ${max_attempts} seconds"
    info "Checking Salt Master status..."
    systemctl status salt-master --no-pager -l || true
    info "Checking Salt Master logs..."
    journalctl -u salt-master -n 30 --no-pager || true
    fatal "Salt Master failed to start properly"
  fi

  # Additional wait for Salt Master to be fully ready
  info "Waiting for Salt Master to fully initialize..."
  sleep 5

  # Enable and start Salt API with retry logic (CherryPy can be slow to start)
  execute systemctl enable salt-api

  local salt_api_attempts=0
  local salt_api_max_attempts=3
  local salt_api_started=false

  while [ $salt_api_attempts -lt $salt_api_max_attempts ]; do
    info "Starting Salt API (attempt $((salt_api_attempts + 1))/${salt_api_max_attempts})..."

    if [ $salt_api_attempts -gt 0 ]; then
      # Restart on subsequent attempts
      execute systemctl restart salt-api
    else
      # First attempt - normal start
      execute systemctl start salt-api
    fi

    # Give Salt API time to initialize (CherryPy needs this)
    sleep 5

    if wait_for_service salt-api 60; then
      success "Salt API service is active"
      salt_api_started=true
      break
    fi

    salt_api_attempts=$((salt_api_attempts + 1))

    if [ $salt_api_attempts -lt $salt_api_max_attempts ]; then
      warning "Salt API not ready, will retry after checking logs..."
      info "Salt API status:"
      systemctl status salt-api --no-pager -l | head -20 || true
      sleep 3
    fi
  done

  if [ "$salt_api_started" != "true" ]; then
    error "Salt API failed to start after ${salt_api_max_attempts} attempts"
    info "Checking Salt API logs:"
    journalctl -u salt-api -n 50 --no-pager || true
    fatal "Failed to start Salt API - check CherryPy requirements and PAM configuration"
  fi
}

#######################################
# Test Salt API
# Tests authentication and basic functionality
#######################################
test_salt_api() {
  step "Testing Salt API..."

  # Wait for port 8001 to be listening (Salt API takes 10-15 seconds to fully start)
  local max_attempts=30
  local attempt=0

  info "Waiting for Salt API to start serving on port 8001..."
  while [ $attempt -lt $max_attempts ]; do
    if ss -tln | grep -q ":8001 "; then
      success "Salt API is listening on port 8001"
      break
    fi

    attempt=$((attempt + 1))
    sleep 1
  done

  if [ $attempt -eq $max_attempts ]; then
    error "Salt API did not start listening on port 8001 after ${max_attempts} seconds"
    info "Checking Salt API service status..."
    systemctl status salt-api --no-pager -l || true
    info "Checking Salt API logs..."
    journalctl -u salt-api -n 20 --no-pager || true
    fatal "Salt API failed to start properly"
  fi

  # Additional wait for API to be fully ready (CherryPy initialization)
  info "Waiting for CherryPy to finish initialization..."
  sleep 5

  # Test API endpoint is accessible with retry
  local api_ready=false
  local api_attempts=0
  local api_max_attempts=10

  while [ $api_attempts -lt $api_max_attempts ]; do
    if curl -sSf --connect-timeout 5 --max-time 10 "http://127.0.0.1:8001" -o /dev/null 2>&1; then
      success "Salt API endpoint is accessible"
      api_ready=true
      break
    fi

    api_attempts=$((api_attempts + 1))
    if [ $api_attempts -lt $api_max_attempts ]; then
      info "Salt API not responding yet, waiting... (attempt ${api_attempts}/${api_max_attempts})"
      sleep 3
    fi
  done

  if [ "$api_ready" != "true" ]; then
    error "Salt API endpoint not accessible after $((api_max_attempts * 3)) seconds"
    error "Port is listening but CherryPy is not responding"
    fatal "Salt API is not accessible at http://127.0.0.1:8001"
  fi

  # Test authentication with retry
  local token=""
  local auth_attempts=0
  local auth_max_attempts=3
  local services_restarted=false

  while [ $auth_attempts -lt $auth_max_attempts ]; do
    token=$(curl -sSk --connect-timeout 5 --max-time 10 "http://127.0.0.1:8001/login" \
      -H "Accept: application/json" \
      -d username="${SALT_API_USER}" \
      -d password="${SALT_API_PASSWORD}" \
      -d eauth=pam \
      2>/dev/null | grep -o '"token": "[^"]*"' | cut -d'"' -f4 || true)

    if [ -n "$token" ]; then
      success "Salt API authentication successful"
      info "Auth token (truncated): ${token:0:20}..."
      return 0
    fi

    auth_attempts=$((auth_attempts + 1))

    # If first attempt fails and we haven't restarted services, do so now
    # This ensures PAM picks up any password changes
    if [ $auth_attempts -eq 1 ] && [ "$services_restarted" != "true" ]; then
      warning "Authentication failed, restarting Salt services to ensure PAM reload..."
      systemctl restart salt-master 2>/dev/null || true
      sleep 5
      systemctl restart salt-api 2>/dev/null || true
      sleep 10
      services_restarted=true
      info "Services restarted, retrying authentication..."
      continue
    fi

    if [ $auth_attempts -lt $auth_max_attempts ]; then
      warning "Authentication failed, retrying... (attempt ${auth_attempts}/${auth_max_attempts})"
      sleep 3
    fi
  done

  error "Salt API authentication failed after ${auth_max_attempts} attempts"
  error "Please check credentials and PAM configuration"
  info "Debugging information:"
  info "  Username: ${SALT_API_USER}"
  info "  Password length: ${#SALT_API_PASSWORD} characters"

  # Check if user exists and has password
  if grep -q "^${SALT_API_USER}:" /etc/shadow 2>/dev/null; then
    info "  User exists in /etc/shadow: YES"
  else
    error "  User exists in /etc/shadow: NO"
  fi

  # Test PAM directly
  info "Testing PAM authentication directly..."
  if [ -x /opt/saltstack/salt/bin/python3 ]; then
    /opt/saltstack/salt/bin/python3 << PYEOF || true
import pam
p = pam.pam()
result = p.authenticate('${SALT_API_USER}', '${SALT_API_PASSWORD}', service='login')
print(f"  PAM auth result: {result}")
if not result:
    print(f"  PAM reason: {p.reason}")
PYEOF
  fi

  info "Checking Salt Master logs for eauth errors:"
  journalctl -u salt-master -n 20 --no-pager 2>/dev/null | grep -i "eauth\|auth\|pam" || true

  info "Checking Salt API logs:"
  journalctl -u salt-api -n 20 --no-pager || true
  return 1
}

#######################################
# Generate minion install script
# Creates a script that can be used to install minions
#######################################
generate_minion_install_script() {
  step "Generating minion install script..."

  local minion_script="/opt/veracity/app/public/install-minion.sh"
  local master_ip
  master_ip=$(hostname -I | awk '{print $1}')

  mkdir -p /opt/veracity/app/public

  cat > "${minion_script}" << 'MINION_EOF'
#!/bin/bash
#
# Veracity Minion Installation Script
# Installs and configures Salt minion to connect to Veracity master
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Veracity - Minion Installation${NC}"
echo ""

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Error: This script must be run as root${NC}"
  exit 1
fi

# Get master IP (will be replaced by application)
MASTER_IP="__MASTER_IP__"

if [ "$MASTER_IP" == "__MASTER_IP__" ]; then
  read -rp "Enter Salt Master IP address: " MASTER_IP
fi

# Detect OS
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo -e "${RED}Cannot detect operating system${NC}"
  exit 1
fi

echo -e "${GREEN}Installing Salt Minion...${NC}"

# Install based on OS
case "${OS_ID}" in
  ubuntu|debian)
    curl -fsSL https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public -o /usr/share/keyrings/salt-archive-keyring.pgp
    echo "deb [signed-by=/usr/share/keyrings/salt-archive-keyring.pgp arch=amd64] https://packages.broadcom.com/artifactory/saltproject-deb/ stable main" > /etc/apt/sources.list.d/salt.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq salt-minion
    ;;
  rocky|almalinux|rhel|centos)
    cat > /etc/yum.repos.d/salt.repo << EOF
[salt-repo]
name=Salt Repository
baseurl=https://packages.broadcom.com/artifactory/saltproject-rpm/
gpgcheck=1
gpgkey=https://packages.broadcom.com/artifactory/api/security/keypair/SaltProjectKey/public
enabled=1
EOF
    dnf install -y -q salt-minion
    ;;
  *)
    echo -e "${RED}Unsupported OS: ${OS_ID}${NC}"
    exit 1
    ;;
esac

# Configure minion
cat > /etc/salt/minion.d/veracity.conf << EOF
master: ${MASTER_IP}
master_port: 4506
id: $(hostname -f)
EOF

# Start and enable minion
systemctl enable salt-minion
systemctl restart salt-minion

echo -e "${GREEN}Salt Minion installed successfully!${NC}"
echo ""
echo -e "Minion ID: $(hostname -f)"
echo -e "Master IP: ${MASTER_IP}"
echo ""
echo -e "Next steps:"
echo -e "1. Accept this minion's key on the master:"
echo -e "   ${BLUE}salt-key -a $(hostname -f)${NC}"
echo -e "2. Test connection:"
echo -e "   ${BLUE}salt $(hostname -f) test.ping${NC}"
MINION_EOF

  chmod 755 "${minion_script}"

  # Replace master IP placeholder if we know it
  if [ -n "${master_ip}" ]; then
    sed -i "s/__MASTER_IP__/${master_ip}/" "${minion_script}"
  fi

  success "Minion install script generated: ${minion_script}"
}

#######################################
# Setup SaltStack for Veracity
# Main function that orchestrates Salt setup
# Globals:
#   SALT_API_USER, SALT_API_PASSWORD
#######################################
setup_salt() {
  install_salt
  create_salt_api_user "${SALT_API_USER}" "${SALT_API_PASSWORD}"
  configure_salt_master
  configure_salt_api
  create_salt_directories
  start_salt_services
  test_salt_api
  generate_minion_install_script

  # Display Salt info
  info "Salt version: $(salt --version | head -1)"
  info "Salt Master: http://127.0.0.1:8001"
  info "Salt API User: ${SALT_API_USER}"

  success "SaltStack setup complete!"
}

# If script is executed directly, run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ -z "${SALT_API_USER:-}" ] || [ -z "${SALT_API_PASSWORD:-}" ]; then
    fatal "Required environment variables not set: SALT_API_USER, SALT_API_PASSWORD"
  fi

  setup_salt
fi
