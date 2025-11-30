#!/bin/bash
#
# validators.sh - Validation functions for Veracity installer
# Provides input validation, system checks, and prerequisite verification
#

# Prevent multiple sourcing
[[ -n "${VERACITY_VALIDATORS_SOURCED:-}" ]] && return 0
readonly VERACITY_VALIDATORS_SOURCED=1

# Source common functions if not already loaded
if ! command -v info &> /dev/null; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=./common.sh
  source "${SCRIPT_DIR}/common.sh"
fi

#######################################
# Validate email address format
# Arguments:
#   Email address
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_email() {
  local email="$1"
  local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"

  if [[ $email =~ $regex ]]; then
    return 0
  else
    error "Invalid email address: ${email}"
    return 1
  fi
}

#######################################
# Validate domain name format
# Arguments:
#   Domain name
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_domain() {
  local domain="$1"
  local regex="^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$"

  # Also accept localhost and IP addresses for development
  if [[ $domain == "localhost" ]] || [[ $domain =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 0
  fi

  if [[ $domain =~ $regex ]]; then
    return 0
  else
    error "Invalid domain name: ${domain}"
    return 1
  fi
}

#######################################
# Validate port number
# Arguments:
#   Port number
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_port() {
  local port="$1"

  if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
    return 0
  else
    error "Invalid port number: ${port}"
    return 1
  fi
}

#######################################
# Validate URL format
# Arguments:
#   URL
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_url() {
  local url="$1"
  local regex="^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$"

  if [[ $url =~ $regex ]]; then
    return 0
  else
    error "Invalid URL: ${url}"
    return 1
  fi
}

#######################################
# Check if port is available
# Arguments:
#   Port number
# Returns:
#   0 if available, 1 if in use
#######################################
is_port_available() {
  local port="$1"

  if netstat -tuln 2>/dev/null | grep -q ":${port} "; then
    warning "Port ${port} is already in use"
    return 1
  fi

  return 0
}

#######################################
# Check if running as root
# Returns:
#   0 if root, 1 otherwise
#######################################
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root"
    error "Please run: sudo $0 $*"
    return 1
  fi
  return 0
}

#######################################
# Check minimum system requirements
# Returns:
#   0 if requirements met, 1 otherwise
#######################################
check_system_requirements() {
  local errors=0

  step "Checking system requirements..."

  # Check CPU cores
  local cpu_cores
  cpu_cores=$(nproc)
  if [ "$cpu_cores" -lt 2 ]; then
    warning "Minimum 2 CPU cores recommended, found: ${cpu_cores}"
  else
    success "CPU cores: ${cpu_cores}"
  fi

  # Check RAM
  local total_ram_mb
  total_ram_mb=$(free -m | awk '/^Mem:/ {print $2}')
  if [ "$total_ram_mb" -lt 2048 ]; then
    error "Minimum 2GB RAM required, found: ${total_ram_mb}MB"
    ((errors++))
  else
    success "RAM: ${total_ram_mb}MB"
  fi

  # Check disk space
  local free_space_gb
  free_space_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
  if [ "$free_space_gb" -lt 10 ]; then
    error "Minimum 10GB free disk space required, found: ${free_space_gb}GB"
    ((errors++))
  else
    success "Free disk space: ${free_space_gb}GB"
  fi

  # Check internet connectivity
  if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
    success "Internet connectivity: OK"
  else
    error "No internet connectivity"
    ((errors++))
  fi

  return $errors
}

#######################################
# Check if database connection is valid
# Arguments:
#   $1 - Database host
#   $2 - Database port
#   $3 - Database name
#   $4 - Database user
#   $5 - Database password
# Returns:
#   0 if connection successful, 1 otherwise
#######################################
test_database_connection() {
  local host="$1"
  local port="${2:-5432}"
  local dbname="$3"
  local user="$4"
  local password="$5"

  export PGPASSWORD="$password"

  if psql -h "$host" -p "$port" -U "$user" -d "$dbname" -c "SELECT 1;" &> /dev/null; then
    success "Database connection successful"
    unset PGPASSWORD
    return 0
  else
    error "Database connection failed"
    unset PGPASSWORD
    return 1
  fi
}

#######################################
# Check if Redis connection is valid
# Arguments:
#   $1 - Redis URL (redis://host:port/db)
# Returns:
#   0 if connection successful, 1 otherwise
#######################################
test_redis_connection() {
  local redis_url="$1"

  # Extract host and port from URL
  local host
  local port

  host=$(echo "$redis_url" | sed -E 's|redis://([^:]+):([0-9]+)/.*|\1|')
  port=$(echo "$redis_url" | sed -E 's|redis://([^:]+):([0-9]+)/.*|\2|')

  if redis-cli -h "$host" -p "$port" ping &> /dev/null; then
    success "Redis connection successful"
    return 0
  else
    error "Redis connection failed"
    return 1
  fi
}

#######################################
# Check if Salt API is accessible
# Arguments:
#   $1 - Salt API URL
# Returns:
#   0 if accessible, 1 otherwise
#######################################
test_salt_api() {
  local salt_url="$1"

  if curl -sSf "${salt_url}" -o /dev/null 2>&1; then
    success "Salt API is accessible"
    return 0
  else
    error "Salt API is not accessible"
    return 1
  fi
}

#######################################
# Validate password strength
# Arguments:
#   Password to validate
# Returns:
#   0 if strong enough, 1 otherwise
#######################################
validate_password_strength() {
  local password="$1"
  local min_length=12

  if [ ${#password} -lt $min_length ]; then
    error "Password must be at least ${min_length} characters long"
    return 1
  fi

  # Check for at least one uppercase, one lowercase, one digit
  if ! [[ $password =~ [A-Z] ]] || ! [[ $password =~ [a-z] ]] || ! [[ $password =~ [0-9] ]]; then
    warning "Password should contain uppercase, lowercase, and numbers"
    return 1
  fi

  return 0
}

#######################################
# Check if user exists
# Arguments:
#   Username
# Returns:
#   0 if exists, 1 otherwise
#######################################
user_exists() {
  id "$1" &> /dev/null
}

#######################################
# Check if directory exists and is writable
# Arguments:
#   Directory path
# Returns:
#   0 if exists and writable, 1 otherwise
#######################################
check_directory_writable() {
  local dir="$1"

  if [ ! -d "$dir" ]; then
    error "Directory does not exist: ${dir}"
    return 1
  fi

  if [ ! -w "$dir" ]; then
    error "Directory is not writable: ${dir}"
    return 1
  fi

  return 0
}

#######################################
# Check if file exists
# Arguments:
#   File path
# Returns:
#   0 if exists, 1 otherwise
#######################################
check_file_exists() {
  local file="$1"

  if [ ! -f "$file" ]; then
    error "File does not exist: ${file}"
    return 1
  fi

  return 0
}

#######################################
# Validate PostgreSQL version
# Arguments:
#   Minimum required version (e.g., "14")
# Returns:
#   0 if version is adequate, 1 otherwise
#######################################
validate_postgres_version() {
  local min_version="$1"
  local current_version

  if ! command_exists psql; then
    error "PostgreSQL is not installed"
    return 1
  fi

  current_version=$(psql --version | grep -oP '\d+' | head -1)

  if [ "$current_version" -ge "$min_version" ]; then
    success "PostgreSQL version: ${current_version} (>= ${min_version})"
    return 0
  else
    error "PostgreSQL version ${current_version} is too old (minimum: ${min_version})"
    return 1
  fi
}

#######################################
# Validate Ruby version
# Arguments:
#   Required version (e.g., "3.3.5")
# Returns:
#   0 if version matches, 1 otherwise
#######################################
validate_ruby_version() {
  local required_version="$1"
  local current_version

  if ! command_exists ruby; then
    error "Ruby is not installed"
    return 1
  fi

  current_version=$(ruby -v | grep -oP '\d+\.\d+\.\d+' | head -1)

  if [ "$current_version" == "$required_version" ]; then
    success "Ruby version: ${current_version}"
    return 0
  else
    warning "Ruby version ${current_version} does not match required ${required_version}"
    return 1
  fi
}

#######################################
# Check if firewall is active
# Returns:
#   0 if active, 1 otherwise
#######################################
is_firewall_active() {
  if command_exists ufw; then
    if ufw status | grep -q "Status: active"; then
      return 0
    fi
  fi
  return 1
}

#######################################
# Validate environment file
# Arguments:
#   Path to .env file
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_env_file() {
  local env_file="$1"
  local errors=0

  if [ ! -f "$env_file" ]; then
    error "Environment file not found: ${env_file}"
    return 1
  fi

  step "Validating environment file..."

  # Check for required variables
  local required_vars=(
    "DATABASE_USERNAME"
    "DATABASE_PASSWORD"
    "DATABASE_HOST"
    "REDIS_URL"
    "SECRET_KEY_BASE"
    "SALT_API_URL"
    "SALT_API_USERNAME"
    "SALT_API_PASSWORD"
  )

  for var in "${required_vars[@]}"; do
    if ! grep -q "^${var}=" "$env_file"; then
      error "Missing required variable: ${var}"
      ((errors++))
    else
      success "Found: ${var}"
    fi
  done

  if [ $errors -eq 0 ]; then
    success "Environment file validation passed"
    return 0
  else
    error "Environment file validation failed with ${errors} errors"
    return 1
  fi
}

#######################################
# Check prerequisites before installation
# Returns:
#   0 if all prerequisites met, 1 otherwise
#######################################
check_prerequisites() {
  section "Prerequisites Check"

  local errors=0

  # Check if running as root
  if ! check_root; then
    ((errors++))
  fi

  # Detect and validate OS
  if ! detect_os; then
    ((errors++))
  else
    if ! is_os_supported; then
      ((errors++))
    fi
  fi

  # Check system requirements
  if ! check_system_requirements; then
    ((errors++))
  fi

  # Check for existing installations
  if [ -d "/opt/veracity/app" ]; then
    warning "Existing installation detected at /opt/veracity/app"
    if ! confirm "This will overwrite the existing installation. Continue?"; then
      fatal "Installation cancelled by user"
    fi
  fi

  if [ $errors -gt 0 ]; then
    fatal "Prerequisites check failed with ${errors} errors"
  fi

  success "All prerequisites checks passed!"
  return 0
}

#######################################
# Validate Hetzner API token
# Arguments:
#   API token
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_hetzner_token() {
  local token="$1"

  if curl -sSf -H "Authorization: Bearer ${token}" \
    "https://api.hetzner.cloud/v1/servers" -o /dev/null 2>&1; then
    success "Hetzner API token is valid"
    return 0
  else
    error "Invalid Hetzner API token"
    return 1
  fi
}

#######################################
# Validate Gotify URL and token
# Arguments:
#   $1 - Gotify URL
#   $2 - App token
# Returns:
#   0 if valid, 1 otherwise
#######################################
validate_gotify() {
  local url="$1"
  local token="$2"

  if curl -sSf "${url}/health" -o /dev/null 2>&1; then
    success "Gotify server is accessible"

    # Test token
    if curl -sSf -H "X-Gotify-Key: ${token}" \
      "${url}/message" -X POST -F "message=Test" -o /dev/null 2>&1; then
      success "Gotify app token is valid"
      return 0
    else
      error "Invalid Gotify app token"
      return 1
    fi
  else
    error "Gotify server is not accessible at: ${url}"
    return 1
  fi
}

# Export validation functions
export -f validate_email validate_domain validate_port validate_url
export -f is_port_available check_root check_system_requirements
export -f test_database_connection test_redis_connection test_salt_api
export -f validate_password_strength user_exists
export -f check_directory_writable check_file_exists
export -f validate_postgres_version validate_ruby_version
export -f is_firewall_active validate_env_file check_prerequisites
export -f validate_hetzner_token validate_gotify
