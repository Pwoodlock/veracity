#!/bin/bash
#
# health-check.sh - Post-installation health checks
# Verifies all services are running and accessible
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib/common.sh
source "${SERVICE_SCRIPT_DIR}/lib/common.sh"
# shellcheck source=./lib/validators.sh
source "${SERVICE_SCRIPT_DIR}/lib/validators.sh"

readonly APP_DIR="/opt/veracity/app"
readonly HEALTH_REPORT="/root/veracity-health-check.txt"

#######################################
# Check service status
#######################################
check_services() {
  section "Checking Services"

  local services=(
    "postgresql"
    "redis-server:redis"  # Try redis-server first, then redis
    "salt-master"
    "salt-api"
    "caddy"
    "server-manager"
    "server-manager-sidekiq"
  )

  local errors=0

  for service in "${services[@]}"; do
    # Handle alternative service names
    if [[ $service == *":"* ]]; then
      local primary="${service%%:*}"
      local fallback="${service##*:}"

      if is_service_running "$primary"; then
        success "$primary is running"
      elif is_service_running "$fallback"; then
        success "$fallback is running"
      else
        error "$primary/$fallback is not running"
        ((errors++))
      fi
    else
      if is_service_running "$service"; then
        success "$service is running"
      else
        error "$service is not running"
        ((errors++))
      fi
    fi
  done

  return $errors
}

#######################################
# Check database connectivity
#######################################
check_database() {
  section "Checking Database"

  if test_database_connection "${DB_HOST:-localhost}" "5432" \
    "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}"; then
    success "Database connection successful"
    return 0
  else
    error "Database connection failed"
    return 1
  fi
}

#######################################
# Check Redis connectivity
#######################################
check_redis() {
  section "Checking Redis"

  if test_redis_connection "${REDIS_URL:-redis://localhost:6379/0}"; then
    return 0
  else
    return 1
  fi
}

#######################################
# Check Salt API
#######################################
check_salt() {
  section "Checking Salt API"

  if test_salt_api "${SALT_API_URL:-http://localhost:8001}"; then
    return 0
  else
    return 1
  fi
}

#######################################
# Check Rails application
#######################################
check_rails() {
  section "Checking Rails Application"

  step "Testing /up endpoint..."

  local max_attempts=10
  local attempt=0

  while [ $attempt -lt $max_attempts ]; do
    if curl -sSf "http://localhost:3000/up" -o /dev/null 2>&1; then
      success "Rails application is responding"

      # Wait additional time for authentication system to fully initialize
      # Devise, session store, and other auth components need a moment after /up responds
      info "Waiting for authentication system to initialize..."
      sleep 5

      # Verify login page is accessible (tests routing + views + auth system)
      if curl -sSf "http://localhost:3000/users/sign_in" -o /dev/null 2>&1; then
        success "Authentication system is ready"
      else
        warning "Login page not yet accessible (will be ready shortly)"
      fi

      return 0
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  error "Rails application is not responding after ${max_attempts} attempts"
  return 1
}

#######################################
# Check Caddy reverse proxy
#######################################
check_caddy() {
  section "Checking Caddy Reverse Proxy"

  step "Testing Caddy..."

  if netstat -tuln | grep -q ":80 "; then
    success "Caddy is listening on port 80"
  else
    error "Caddy is not listening on port 80"
    return 1
  fi

  if [ "${RAILS_PROTOCOL}" == "https" ]; then
    if netstat -tuln | grep -q ":443 "; then
      success "Caddy is listening on port 443"
    else
      warning "Caddy is not yet listening on port 443 (certificate provisioning may be in progress)"
    fi
  fi

  return 0
}

#######################################
# Check disk space
#######################################
check_disk_space() {
  section "Checking Disk Space"

  local free_space_gb
  free_space_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')

  if [ "$free_space_gb" -lt 5 ]; then
    warning "Low disk space: ${free_space_gb}GB free"
  else
    success "Disk space: ${free_space_gb}GB free"
  fi
}

#######################################
# Check log files
#######################################
check_logs() {
  section "Checking Logs for Errors"

  local log_files=(
    "${APP_DIR}/log/production.log"
    "${APP_DIR}/log/puma.log"
    "${APP_DIR}/log/sidekiq.log"
  )

  for log_file in "${log_files[@]}"; do
    if [ -f "$log_file" ]; then
      local error_count
      error_count=$(grep -i "error\|fatal\|exception" "$log_file" 2>/dev/null | wc -l || echo "0")

      if [ "$error_count" -gt 10 ]; then
        warning "$(basename $log_file): ${error_count} errors found"
      else
        success "$(basename $log_file): ${error_count} errors"
      fi
    fi
  done
}

#######################################
# Generate health report
#######################################
generate_health_report() {
  step "Generating health report..."

  cat > "${HEALTH_REPORT}" << EOF
================================================================================
VERACITY HEALTH CHECK REPORT
================================================================================
Generated: $(date)

SYSTEM INFORMATION:
-------------------
Hostname: $(hostname)
IP Address: $(hostname -I | awk '{print $1}')
OS: ${OS_NAME} ${OS_VERSION}
Kernel: $(uname -r)

SERVICE STATUS:
---------------
$(systemctl is-active postgresql && echo "PostgreSQL: ✓ Running" || echo "PostgreSQL: ✗ Stopped")
$(systemctl is-active redis-server 2>/dev/null || systemctl is-active redis && echo "Redis: ✓ Running" || echo "Redis: ✗ Stopped")
$(systemctl is-active salt-master && echo "Salt Master: ✓ Running" || echo "Salt Master: ✗ Stopped")
$(systemctl is-active salt-api && echo "Salt API: ✓ Running" || echo "Salt API: ✗ Stopped")
$(systemctl is-active caddy && echo "Caddy: ✓ Running" || echo "Caddy: ✗ Stopped")
$(systemctl is-active server-manager && echo "Puma: ✓ Running" || echo "Puma: ✗ Stopped")
$(systemctl is-active server-manager-sidekiq && echo "Sidekiq: ✓ Running" || echo "Sidekiq: ✗ Stopped")

CONNECTIVITY TESTS:
-------------------
Database: $(test_database_connection "${DB_HOST:-localhost}" "5432" "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}" && echo "✓ OK" || echo "✗ Failed")
Redis: $(redis-cli ping >/dev/null 2>&1 && echo "✓ OK" || echo "✗ Failed")
Salt API: $(curl -sSf http://localhost:8001 -o /dev/null 2>&1 && echo "✓ OK" || echo "✗ Failed")
Rails App: $(curl -sSf http://localhost:3000/up -o /dev/null 2>&1 && echo "✓ OK" || echo "✗ Failed")

RESOURCE USAGE:
---------------
CPU Cores: $(nproc)
RAM: $(free -h | awk '/^Mem:/ {print $2 " total, " $3 " used, " $4 " free"}')
Disk: $(df -h / | awk 'NR==2 {print $2 " total, " $3 " used, " $4 " free"}')

CONFIGURATION:
--------------
Application: ${APP_DIR}
Domain: ${RAILS_HOST}
Protocol: ${RAILS_PROTOCOL}
Admin Email: ${ADMIN_EMAIL}

NEXT STEPS:
-----------
1. Access dashboard at: ${RAILS_PROTOCOL}://${RAILS_HOST}
2. Log in with admin credentials
3. Enable 2FA for security
4. Configure optional integrations
5. Install minions on your servers

================================================================================
EOF

  chmod 600 "${HEALTH_REPORT}"
  success "Health report saved to: ${HEALTH_REPORT}"
}

#######################################
# Run all health checks
#######################################
run_health_checks() {
  section "Running Health Checks"

  local errors=0

  check_services || ((errors++))
  check_database || ((errors++))
  check_redis || ((errors++))
  check_salt || ((errors++))
  check_rails || ((errors++))
  check_caddy || ((errors++))
  check_disk_space
  check_logs

  generate_health_report

  if [ $errors -eq 0 ]; then
    success "All health checks passed! ✓"
    return 0
  else
    warning "${errors} health check(s) failed"
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_health_checks
fi
