#!/bin/bash
#
# postgresql.sh - PostgreSQL installation and configuration
# Installs PostgreSQL 14+, creates database and user
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SERVICE_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/validators.sh
source "${SERVICE_SCRIPT_DIR}/../lib/validators.sh"

#######################################
# Install PostgreSQL
# Globals:
#   OS_ID
# Returns:
#   0 on success, 1 on failure
#######################################
install_postgresql() {
  section "Installing PostgreSQL"

  case "${OS_ID}" in
    ubuntu|debian)
      install_postgresql_debian
      ;;
    rocky|almalinux|rhel)
      install_postgresql_rhel
      ;;
    *)
      fatal "Unsupported OS for PostgreSQL installation: ${OS_ID}"
      ;;
  esac
}

#######################################
# Verify PostgreSQL is ready to accept connections
# Returns:
#   0 if ready, 1 otherwise
#######################################
wait_for_postgresql_ready() {
  local max_attempts=30
  local attempt=1

  info "Waiting for PostgreSQL to be ready to accept connections..."

  while [ $attempt -le $max_attempts ]; do
    if sudo -u postgres psql -c "SELECT 1" &>> "${LOG_FILE}"; then
      success "PostgreSQL is ready"
      return 0
    fi

    if [ $attempt -eq 1 ]; then
      info "PostgreSQL service is starting, waiting for it to accept connections..."
    fi

    sleep 2
    ((attempt++))
  done

  error "PostgreSQL did not become ready within $((max_attempts * 2)) seconds"
  return 1
}

#######################################
# Install PostgreSQL on Debian/Ubuntu
#######################################
install_postgresql_debian() {
  step "Installing PostgreSQL for Debian/Ubuntu..."

  # Install PostgreSQL
  spinner "Installing PostgreSQL packages" install_packages \
    postgresql postgresql-contrib libpq-dev

  # Start and enable PostgreSQL
  execute systemctl start postgresql
  execute systemctl enable postgresql

  # Wait for systemd service
  if wait_for_service postgresql; then
    info "PostgreSQL service is active"
  else
    fatal "Failed to start PostgreSQL service"
  fi

  # Verify PostgreSQL is actually ready to accept connections
  if wait_for_postgresql_ready; then
    success "PostgreSQL installed and ready"
  else
    fatal "PostgreSQL service started but not accepting connections"
  fi
}

#######################################
# Install PostgreSQL on RHEL/Rocky
#######################################
install_postgresql_rhel() {
  step "Installing PostgreSQL for RHEL/Rocky..."

  # Install PostgreSQL
  spinner "Installing PostgreSQL packages" install_packages \
    postgresql-server postgresql-contrib postgresql-devel

  # Initialize database
  if [ ! -f /var/lib/pgsql/data/postgresql.conf ]; then
    info "Initializing PostgreSQL database..."
    execute postgresql-setup --initdb
  fi

  # Start and enable PostgreSQL
  execute systemctl start postgresql
  execute systemctl enable postgresql

  # Wait for systemd service
  if wait_for_service postgresql; then
    info "PostgreSQL service is active"
  else
    fatal "Failed to start PostgreSQL service"
  fi

  # Verify PostgreSQL is actually ready to accept connections
  if wait_for_postgresql_ready; then
    success "PostgreSQL installed and ready"
  else
    fatal "PostgreSQL service started but not accepting connections"
  fi
}

#######################################
# Create PostgreSQL user
# Arguments:
#   $1 - Username
#   $2 - Password
# Returns:
#   0 on success, 1 on failure
#######################################
create_postgres_user() {
  local username="$1"
  local password="$2"

  step "Creating PostgreSQL user: ${username}..."

  # Check if user exists
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${username}'" | grep -q 1; then
    warning "User ${username} already exists, updating password"

    sudo -u postgres psql -c \
      "ALTER USER ${username} WITH PASSWORD '${password}' CREATEDB;" &>> "${LOG_FILE}"
  else
    sudo -u postgres psql -c \
      "CREATE USER ${username} WITH PASSWORD '${password}' CREATEDB;" &>> "${LOG_FILE}"
  fi

  success "PostgreSQL user ${username} created"
}

#######################################
# Create PostgreSQL database
# Arguments:
#   $1 - Database name
#   $2 - Owner username
# Returns:
#   0 on success, 1 on failure
#######################################
create_postgres_database() {
  local dbname="$1"
  local owner="$2"

  step "Creating PostgreSQL database: ${dbname}..."

  # Check if database exists
  if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${dbname}'" | grep -q 1; then
    warning "Database ${dbname} already exists, skipping creation"
  else
    sudo -u postgres psql -c \
      "CREATE DATABASE ${dbname} OWNER ${owner};" &>> "${LOG_FILE}"

    # Grant privileges
    sudo -u postgres psql -c \
      "GRANT ALL PRIVILEGES ON DATABASE ${dbname} TO ${owner};" &>> "${LOG_FILE}"

    success "Database ${dbname} created"
  fi
}

#######################################
# Configure PostgreSQL
# Configures pg_hba.conf for local and network access
#######################################
configure_postgresql() {
  step "Configuring PostgreSQL..."

  local pg_hba_conf
  local pg_conf

  # Find PostgreSQL configuration files
  if [ -f /etc/postgresql/*/main/pg_hba.conf ]; then
    pg_hba_conf=$(ls /etc/postgresql/*/main/pg_hba.conf | head -1)
    pg_conf=$(ls /etc/postgresql/*/main/postgresql.conf | head -1)
  elif [ -f /var/lib/pgsql/data/pg_hba.conf ]; then
    pg_hba_conf="/var/lib/pgsql/data/pg_hba.conf"
    pg_conf="/var/lib/pgsql/data/postgresql.conf"
  else
    fatal "Could not find PostgreSQL configuration files"
  fi

  info "PostgreSQL config: ${pg_hba_conf}"

  # Backup original config
  if [ ! -f "${pg_hba_conf}.backup" ]; then
    execute cp "${pg_hba_conf}" "${pg_hba_conf}.backup"
  fi

  # Configure authentication for local connections
  # Allow password authentication for local connections
  if ! grep -q "# Veracity installer" "${pg_hba_conf}"; then
    cat >> "${pg_hba_conf}" << EOF

# Veracity installer - Allow password authentication
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
EOF
    success "Configured PostgreSQL authentication"
  else
    info "PostgreSQL authentication already configured"
  fi

  # Reload PostgreSQL
  execute systemctl reload postgresql

  success "PostgreSQL configuration complete"
}

#######################################
# Test PostgreSQL connection
# Arguments:
#   $1 - Database name
#   $2 - Username
#   $3 - Password
# Returns:
#   0 on success, 1 on failure
#######################################
test_postgresql() {
  local dbname="$1"
  local username="$2"
  local password="$3"

  step "Testing PostgreSQL connection..."

  if test_database_connection "localhost" "5432" "${dbname}" "${username}" "${password}"; then
    success "PostgreSQL connection test passed"
    return 0
  else
    fatal "PostgreSQL connection test failed"
  fi
}

#######################################
# Setup PostgreSQL for Veracity
# Main function that orchestrates PostgreSQL setup
# Globals:
#   DB_NAME, DB_USER, DB_PASSWORD, DB_HOST
#######################################
setup_postgresql() {
  install_postgresql
  configure_postgresql
  create_postgres_user "${DB_USER}" "${DB_PASSWORD}"
  create_postgres_database "${DB_NAME}" "${DB_USER}"
  test_postgresql "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}"

  success "PostgreSQL setup complete!"
}

# If script is executed directly, run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Check prerequisites
  if [ -z "${DB_NAME:-}" ] || [ -z "${DB_USER:-}" ] || [ -z "${DB_PASSWORD:-}" ]; then
    fatal "Required environment variables not set: DB_NAME, DB_USER, DB_PASSWORD"
  fi

  setup_postgresql
fi
