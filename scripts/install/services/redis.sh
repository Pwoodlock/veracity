#!/bin/bash
#
# redis.sh - Redis installation and configuration
# Installs Redis 7+, configures for production use
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SERVICE_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/validators.sh
source "${SERVICE_SCRIPT_DIR}/../lib/validators.sh"

#######################################
# Install Redis
# Globals:
#   OS_ID
# Returns:
#   0 on success, 1 on failure
#######################################
install_redis() {
  section "Installing Redis"

  case "${OS_ID}" in
    ubuntu|debian)
      install_redis_debian
      ;;
    rocky|almalinux|rhel)
      install_redis_rhel
      ;;
    *)
      fatal "Unsupported OS for Redis installation: ${OS_ID}"
      ;;
  esac
}

#######################################
# Verify Redis is ready to accept connections
# Returns:
#   0 if ready, 1 otherwise
#######################################
wait_for_redis_ready() {
  local max_attempts=15
  local attempt=1

  info "Waiting for Redis to be ready..."

  while [ $attempt -le $max_attempts ]; do
    if redis-cli ping &>> "${LOG_FILE}"; then
      success "Redis is ready"
      return 0
    fi

    sleep 1
    ((attempt++))
  done

  error "Redis did not become ready within ${max_attempts} seconds"
  return 1
}

#######################################
# Install Redis on Debian/Ubuntu
#######################################
install_redis_debian() {
  step "Installing Redis for Debian/Ubuntu..."

  spinner "Installing Redis packages" install_packages redis-server

  # Start and enable Redis
  execute systemctl start redis-server
  execute systemctl enable redis-server

  # Wait for systemd service
  if wait_for_service redis-server; then
    info "Redis service is active"
  else
    fatal "Failed to start Redis service"
  fi

  # Verify Redis is actually ready
  if wait_for_redis_ready; then
    success "Redis installed and ready"
  else
    fatal "Redis service started but not accepting connections"
  fi
}

#######################################
# Install Redis on RHEL/Rocky
#######################################
install_redis_rhel() {
  step "Installing Redis for RHEL/Rocky..."

  spinner "Installing Redis packages" install_packages redis

  # Start and enable Redis
  execute systemctl start redis
  execute systemctl enable redis

  # Wait for systemd service
  if wait_for_service redis; then
    info "Redis service is active"
  else
    fatal "Failed to start Redis service"
  fi

  # Verify Redis is actually ready
  if wait_for_redis_ready; then
    success "Redis installed and ready"
  else
    fatal "Redis service started but not accepting connections"
  fi
}

#######################################
# Configure Redis for production
# Sets memory limits, persistence, and systemd supervision
#######################################
configure_redis() {
  step "Configuring Redis for production..."

  local redis_conf

  # Find Redis configuration file
  if [ -f /etc/redis/redis.conf ]; then
    redis_conf="/etc/redis/redis.conf"
  elif [ -f /etc/redis.conf ]; then
    redis_conf="/etc/redis.conf"
  else
    fatal "Could not find Redis configuration file"
  fi

  info "Redis config: ${redis_conf}"

  # Backup original config
  if [ ! -f "${redis_conf}.backup" ]; then
    execute cp "${redis_conf}" "${redis_conf}.backup"
  fi

  # Configure memory limit
  if ! grep -q "# Veracity installer - maxmemory" "${redis_conf}"; then
    cat >> "${redis_conf}" << EOF

# Veracity installer - maxmemory configuration
maxmemory 256mb
maxmemory-policy allkeys-lru
EOF
    success "Configured Redis memory limits"
  fi

  # Configure systemd supervision
  if ! grep -q "supervised systemd" "${redis_conf}"; then
    sed -i 's/^supervised.*/supervised systemd/' "${redis_conf}" || {
      echo "supervised systemd" >> "${redis_conf}"
    }
    success "Configured Redis systemd supervision"
  fi

  # Ensure bind to localhost
  if ! grep -q "^bind 127.0.0.1" "${redis_conf}"; then
    sed -i 's/^bind.*/bind 127.0.0.1/' "${redis_conf}" || {
      echo "bind 127.0.0.1" >> "${redis_conf}"
    }
    success "Configured Redis to bind to localhost"
  fi

  # Disable protected mode for local development
  if grep -q "^protected-mode yes" "${redis_conf}"; then
    sed -i 's/^protected-mode yes/protected-mode no/' "${redis_conf}"
  fi

  # Restart Redis to apply changes
  local redis_service
  if systemctl list-unit-files | grep -q "redis-server.service"; then
    redis_service="redis-server"
  else
    redis_service="redis"
  fi

  execute systemctl restart "${redis_service}"

  if wait_for_service "${redis_service}"; then
    success "Redis restarted with new configuration"
  else
    fatal "Failed to restart Redis"
  fi

  success "Redis configuration complete"
}

#######################################
# Test Redis connection
# Arguments:
#   $1 - Redis URL (optional, default: redis://localhost:6379/0)
# Returns:
#   0 on success, 1 on failure
#######################################
test_redis() {
  local redis_url="${1:-redis://localhost:6379/0}"

  step "Testing Redis connection..."

  if redis-cli ping &> /dev/null; then
    success "Redis connection test passed"

    # Test basic operations
    redis-cli SET veracity_test "installation" &> /dev/null
    local value
    value=$(redis-cli GET veracity_test 2>/dev/null)

    if [ "$value" == "installation" ]; then
      success "Redis read/write test passed"
      redis-cli DEL veracity_test &> /dev/null
      return 0
    else
      warning "Redis read/write test failed"
      return 1
    fi
  else
    fatal "Redis connection test failed"
  fi
}

#######################################
# Get Redis service name for this OS
# Returns:
#   Redis service name (redis-server or redis)
#######################################
get_redis_service_name() {
  if systemctl list-unit-files | grep -q "redis-server.service"; then
    echo "redis-server"
  else
    echo "redis"
  fi
}

#######################################
# Setup Redis for Veracity
# Main function that orchestrates Redis setup
# Globals:
#   REDIS_URL
#######################################
setup_redis() {
  install_redis
  configure_redis
  test_redis "${REDIS_URL:-redis://localhost:6379/0}"

  # Display Redis info
  info "Redis version: $(redis-cli --version)"
  info "Redis service: $(get_redis_service_name)"

  success "Redis setup complete!"
}

# If script is executed directly, run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_redis
fi
