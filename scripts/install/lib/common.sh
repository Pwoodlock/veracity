#!/bin/bash
#
# common.sh - Common utility functions for Veracity installer
# Provides colored output, logging, error handling, and helper utilities
#

# Prevent multiple sourcing
[[ -n "${VERACITY_COMMON_SOURCED:-}" ]] && return 0
readonly VERACITY_COMMON_SOURCED=1

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color
readonly BOLD='\033[1m'

# Emoji/Unicode characters for better UX
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly INFO_MARK="ℹ"
readonly WARNING_MARK="⚠"
readonly ROCKET="🚀"
readonly GEAR="⚙"
readonly LOCK="🔒"
readonly KEY="🔑"

# Log file location
readonly LOG_DIR="/var/log/veracity-install"
readonly LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

#######################################
# Initialize logging
# Globals:
#   LOG_DIR, LOG_FILE
# Arguments:
#   None
#######################################
init_logging() {
  mkdir -p "${LOG_DIR}"
  touch "${LOG_FILE}"
  chmod 600 "${LOG_FILE}"
  log_message "Installation started at $(date)"
  log_message "Installer version: 1.0.0"
  log_message "Running on: $(uname -a)"
}

#######################################
# Log message to file
# Arguments:
#   Message to log
#######################################
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

#######################################
# Print info message
# Arguments:
#   Message to print
#######################################
info() {
  echo -e "${BLUE}${INFO_MARK}${NC} $*"
  log_message "INFO: $*"
}

#######################################
# Print success message
# Arguments:
#   Message to print
#######################################
success() {
  echo -e "${GREEN}${CHECK_MARK}${NC} ${GREEN}$*${NC}"
  log_message "SUCCESS: $*"
}

#######################################
# Print warning message
# Arguments:
#   Message to print
#######################################
warning() {
  echo -e "${YELLOW}${WARNING_MARK}${NC} ${YELLOW}$*${NC}"
  log_message "WARNING: $*"
}

#######################################
# Print error message
# Arguments:
#   Message to print
#######################################
error() {
  echo -e "${RED}${CROSS_MARK}${NC} ${RED}$*${NC}" >&2
  log_message "ERROR: $*"
}

#######################################
# Print step header
# Arguments:
#   Step description
#######################################
step() {
  echo ""
  echo -e "${BOLD}${CYAN}==>${NC} ${BOLD}$*${NC}"
  log_message "STEP: $*"
}

#######################################
# Print section header
# Arguments:
#   Section title
#######################################
section() {
  echo ""
  echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${MAGENTA}  $*${NC}"
  echo -e "${BOLD}${MAGENTA}═══════════════════════════════════════════════════════${NC}"
  log_message "SECTION: $*"
}

#######################################
# Fatal error - exit with error message
# Arguments:
#   Error message
#######################################
fatal() {
  error "$*"
  error "Installation failed. Check logs at: ${LOG_FILE}"
  exit 1
}

#######################################
# Prompt user for input with default value
# Arguments:
#   $1 - Prompt message
#   $2 - Default value (optional)
# Returns:
#   User input or default value
#######################################
prompt() {
  local prompt_msg="$1"
  local default_value="${2:-}"
  local user_input

  if [[ -n "$default_value" ]]; then
    read -rp "$(echo -e "${CYAN}?${NC} ${prompt_msg} [${default_value}]: ")" user_input
    echo "${user_input:-$default_value}"
  else
    read -rp "$(echo -e "${CYAN}?${NC} ${prompt_msg}: ")" user_input
    echo "${user_input}"
  fi
}

#######################################
# Prompt for password (hidden input)
# Arguments:
#   $1 - Prompt message
# Returns:
#   Password entered by user
#######################################
prompt_password() {
  local prompt_msg="$1"
  local password

  read -rsp "$(echo -e "${CYAN}?${NC} ${prompt_msg}: ")" password
  echo "" # New line after hidden input
  echo "${password}"
}

#######################################
# Prompt for yes/no confirmation
# Arguments:
#   $1 - Question to ask
#   $2 - Default (y/n)
# Returns:
#   0 if yes, 1 if no
#######################################
confirm() {
  local question="$1"
  local default="${2:-n}"
  local response

  if [[ "${default}" == "y" ]]; then
    read -rp "$(echo -e "${CYAN}?${NC} ${question} [Y/n]: ")" response
    response="${response:-y}"
  else
    read -rp "$(echo -e "${CYAN}?${NC} ${question} [y/N]: ")" response
    response="${response:-n}"
  fi

  case "${response,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

#######################################
# Generate secure random password
# Arguments:
#   $1 - Password length (default: 32)
# Returns:
#   Generated password
#######################################
generate_password() {
  local length="${1:-32}"
  openssl rand -base64 48 | tr -d '/+=' | head -c "${length}"
}

#######################################
# Generate hex string for SECRET_KEY_BASE
# Returns:
#   128-character hex string
#######################################
generate_secret_key_base() {
  openssl rand -hex 64
}

#######################################
# Check if command exists
# Arguments:
#   Command name
# Returns:
#   0 if command exists, 1 otherwise
#######################################
command_exists() {
  command -v "$1" &> /dev/null
}

#######################################
# Check if service is running
# Arguments:
#   Service name
# Returns:
#   0 if running, 1 otherwise
#######################################
is_service_running() {
  systemctl is-active --quiet "$1"
}

#######################################
# Check if service is enabled
# Arguments:
#   Service name
# Returns:
#   0 if enabled, 1 otherwise
#######################################
is_service_enabled() {
  systemctl is-enabled --quiet "$1"
}

#######################################
# Wait for service to start
# Arguments:
#   $1 - Service name
#   $2 - Timeout in seconds (default: 30)
# Returns:
#   0 if service started, 1 if timeout
#######################################
wait_for_service() {
  local service="$1"
  local timeout="${2:-30}"
  local counter=0

  info "Waiting for ${service} to start..."

  while [ $counter -lt $timeout ]; do
    if is_service_running "${service}"; then
      success "${service} is running"
      return 0
    fi
    sleep 1
    ((counter++))
  done

  error "Timeout waiting for ${service} to start"
  return 1
}

#######################################
# Execute command and log output
# Arguments:
#   Command to execute
# Returns:
#   Command exit code
#######################################
execute() {
  log_message "Executing: $*"
  "$@" >> "${LOG_FILE}" 2>&1
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    log_message "Command failed with exit code: ${exit_code}"
  fi

  return $exit_code
}

#######################################
# Run command with timeout
# Arguments:
#   $1 - Timeout in seconds
#   $2+ - Command to execute
# Returns:
#   Command exit code, or 124 if timeout
#######################################
run_with_timeout() {
  local timeout_duration="$1"
  shift
  local cmd=("$@")

  log_message "Running with ${timeout_duration}s timeout: ${cmd[*]}"

  # Check if timeout command is available
  if command_exists timeout; then
    timeout "${timeout_duration}" "${cmd[@]}" >> "${LOG_FILE}" 2>&1
    local exit_code=$?

    if [ $exit_code -eq 124 ]; then
      error "Command timed out after ${timeout_duration} seconds: ${cmd[*]}"
      log_message "TIMEOUT: Command exceeded ${timeout_duration}s limit"
    elif [ $exit_code -ne 0 ]; then
      log_message "Command failed with exit code: ${exit_code}"
    fi

    return $exit_code
  else
    # Fallback: run without timeout if command not available
    warning "timeout command not available, running without timeout"
    "${cmd[@]}" >> "${LOG_FILE}" 2>&1
    return $?
  fi
}

#######################################
# Retry command with exponential backoff
# Arguments:
#   $1 - Maximum number of attempts
#   $2 - Initial delay in seconds
#   $3+ - Command to execute
# Returns:
#   0 if command succeeds, 1 if all retries fail
#######################################
retry_command() {
  local max_attempts="$1"
  local initial_delay="$2"
  shift 2
  local cmd=("$@")
  local attempt=1
  local delay="$initial_delay"

  log_message "Retry wrapper: max_attempts=${max_attempts}, initial_delay=${initial_delay}s"

  while [ $attempt -le $max_attempts ]; do
    log_message "Attempt ${attempt}/${max_attempts}: ${cmd[*]}"

    if "${cmd[@]}" >> "${LOG_FILE}" 2>&1; then
      if [ $attempt -gt 1 ]; then
        success "Command succeeded on attempt ${attempt}"
      fi
      return 0
    fi

    if [ $attempt -lt $max_attempts ]; then
      warning "Attempt ${attempt} failed, retrying in ${delay}s..."
      sleep "$delay"
      # Exponential backoff: double the delay for next attempt
      delay=$((delay * 2))
    else
      error "Command failed after ${max_attempts} attempts: ${cmd[*]}"
      return 1
    fi

    ((attempt++))
  done
}

#######################################
# Show spinner while command runs
# Arguments:
#   $1 - Message to display
#   $@ - Command to execute
#######################################
spinner() {
  local message="$1"
  shift
  local pid
  local delay=0.1
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

  "$@" >> "${LOG_FILE}" 2>&1 &
  pid=$!

  while ps -p $pid &> /dev/null; do
    local temp=${spinstr#?}
    printf " [%c] %s" "$spinstr" "$message"
    spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\r"
  done

  wait $pid
  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    printf " ${GREEN}[${CHECK_MARK}]${NC} %s\n" "$message"
  else
    printf " ${RED}[${CROSS_MARK}]${NC} %s\n" "$message"
  fi

  return $exit_code
}

#######################################
# Print progress bar
# Arguments:
#   $1 - Current step
#   $2 - Total steps
#   $3 - Message
#######################################
progress_bar() {
  local current="$1"
  local total="$2"
  local message="$3"
  local percent=$((current * 100 / total))
  local filled=$((current * 50 / total))
  local empty=$((50 - filled))

  printf "\r["
  printf "%${filled}s" | tr ' ' '#'
  printf "%${empty}s" | tr ' ' '-'
  printf "] %3d%% - %s" "$percent" "$message"

  if [ "$current" -eq "$total" ]; then
    echo ""
  fi
}

#######################################
# Detect OS and version
# Globals:
#   OS_NAME, OS_VERSION, OS_ID
# Returns:
#   0 if supported OS, 1 otherwise
#######################################
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
    OS_ID="$ID"

    info "Detected OS: ${OS_NAME} ${OS_VERSION}"
    log_message "OS Details: ID=${OS_ID}, NAME=${OS_NAME}, VERSION=${OS_VERSION}"
    return 0
  else
    error "Cannot detect operating system"
    return 1
  fi
}

#######################################
# Check if OS is supported
# Returns:
#   0 if supported, 1 otherwise
#######################################
is_os_supported() {
  case "${OS_ID}" in
    ubuntu)
      if [[ "${OS_VERSION}" == "22.04" ]] || [[ "${OS_VERSION}" == "24.04" ]]; then
        return 0
      fi
      ;;
    debian)
      if [[ "${OS_VERSION}" == "11" ]] || [[ "${OS_VERSION}" == "12" ]]; then
        return 0
      fi
      ;;
    rocky|almalinux|rhel)
      if [[ "${OS_VERSION}" =~ ^9 ]]; then
        return 0
      fi
      ;;
  esac

  error "Unsupported OS: ${OS_NAME} ${OS_VERSION}"
  error "Supported: Ubuntu 22.04/24.04, Debian 11/12, Rocky Linux 9"
  return 1
}

#######################################
# Get package manager command
# Returns:
#   Package manager command (apt-get or dnf)
#######################################
get_package_manager() {
  case "${OS_ID}" in
    ubuntu|debian)
      echo "apt-get"
      ;;
    rocky|almalinux|rhel)
      echo "dnf"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

#######################################
# Update system packages
#######################################
update_system_packages() {
  local pkg_mgr
  pkg_mgr=$(get_package_manager)

  step "Updating system packages..."

  case "${pkg_mgr}" in
    apt-get)
      spinner "Updating package lists" execute apt-get update -qq
      ;;
    dnf)
      spinner "Updating package lists" execute dnf check-update -q
      ;;
  esac

  success "System packages updated"

  # Install essential base packages needed by installer
  step "Installing base packages..."
  case "${pkg_mgr}" in
    apt-get)
      spinner "Installing base tools" execute apt-get install -y -qq curl wget git unzip gnupg ca-certificates
      ;;
    dnf)
      spinner "Installing base tools" execute dnf install -y -q curl wget git unzip gnupg2 ca-certificates
      ;;
  esac

  success "Base packages installed"
}

#######################################
# Install system packages
# Arguments:
#   Package names
#######################################
install_packages() {
  local pkg_mgr
  pkg_mgr=$(get_package_manager)

  case "${pkg_mgr}" in
    apt-get)
      DEBIAN_FRONTEND=noninteractive execute apt-get install -y -qq "$@"
      ;;
    dnf)
      execute dnf install -y -q "$@"
      ;;
  esac
}

#######################################
# Save installation credentials
# Arguments:
#   Credentials file path
#######################################
save_credentials() {
  local creds_file="$1"

  cat > "${creds_file}" << EOF
================================================================================
VERACITY INSTALLATION CREDENTIALS
================================================================================
⚠️  SECURITY NOTICE: This file is stored in /tmp/ and will be automatically
    deleted on system reboot. Copy this file to a secure location immediately!

Installation completed: $(date)

ACCESS INFORMATION:
-------------------
Dashboard URL: ${INSTALL_URL}
Admin Email: ${ADMIN_EMAIL}
Admin Password: ${ADMIN_PASSWORD}

DATABASE:
---------
Database Name: ${DB_NAME}
Database User: ${DB_USER}
Database Password: ${DB_PASSWORD}
Database Host: ${DB_HOST}

SALT API:
---------
Salt API URL: ${SALT_API_URL}
Salt API User: ${SALT_API_USER}
Salt API Password: ${SALT_API_PASSWORD}

REDIS:
------
Redis URL: ${REDIS_URL}

SECURITY:
---------
Rails Secret Key Base: ${SECRET_KEY_BASE}

$(if [ "${GOTIFY_ENABLED}" = "true" ]; then
cat << GOTIFY
GOTIFY NOTIFICATIONS:
---------------------
Gotify URL: ${GOTIFY_URL}
$(if [ "${GOTIFY_INSTALL_LOCAL}" = "true" ]; then
echo "Gotify Admin Username: ${GOTIFY_ADMIN_USER}"
echo "Gotify Admin Password: ${GOTIFY_ADMIN_PASSWORD}"
echo "(Same credentials as Veracity admin)"
fi)
Gotify App Token: ${GOTIFY_APP_TOKEN:-Will be generated on first login}
GOTIFY
fi)

$(if [ "${OAUTH_ENABLED}" = "true" ]; then
cat << OAUTH
OAUTH2 / ZITADEL:
-----------------
Zitadel Issuer: ${ZITADEL_ISSUER}
Zitadel Client ID: ${ZITADEL_CLIENT_ID}
OAUTH
fi)

IMPORTANT SECURITY NOTES:
-------------------------
1. This file contains sensitive credentials - store it securely!
2. Remove this file after saving credentials to a password manager
3. Change default passwords immediately after first login
4. Enable 2FA for the admin account

NEXT STEPS:
-----------
1. Access the dashboard at: ${INSTALL_URL}
2. Log in with the admin credentials above
3. Configure additional settings in Settings page
4. Install minions on your servers using:
   curl -sSL ${INSTALL_URL}/install/minion.sh | sudo bash

SUPPORT:
--------
Documentation: https://github.com/Pwoodlock/veracity
Issues: https://github.com/Pwoodlock/veracity/issues

================================================================================
EOF

  chmod 600 "${creds_file}"
  success "Credentials saved to: ${creds_file}"
}

#######################################
# Print installation summary
#######################################
print_summary() {
  local creds_file="${1:-/tmp/veracity-install-credentials.txt}"

  section "Installation Complete! ${ROCKET}"
  echo ""
  echo -e "${GREEN}${BOLD}Veracity has been successfully installed!${NC}"
  echo ""
  echo -e "${BOLD}Access your dashboard:${NC}"
  echo -e "  ${CYAN}URL:${NC} ${INSTALL_URL}"
  echo -e "  ${CYAN}Email:${NC} ${ADMIN_EMAIL}"
  echo -e "  ${CYAN}Password:${NC} ${ADMIN_PASSWORD}"
  echo ""
  if [ "${GOTIFY_INSTALL_LOCAL:-}" = "true" ]; then
    echo -e "${BOLD}Gotify Push Notifications:${NC}"
    echo -e "  ${CYAN}URL:${NC} ${GOTIFY_URL}"
    echo -e "  ${CYAN}Username:${NC} ${GOTIFY_ADMIN_USER}"
    echo -e "  ${CYAN}Password:${NC} (same as Veracity admin)"
    echo ""
  fi
  echo -e "${BOLD}Installation Details:${NC}"
  echo -e "  ${CYAN}Application:${NC} /opt/veracity/app"
  echo -e "  ${CYAN}Logs:${NC} /opt/veracity/app/log/production.log"
  echo ""
  echo -e "${RED}${BOLD}⚠️  IMPORTANT - CREDENTIALS FILE:${NC}"
  echo -e "  ${CYAN}Location:${NC} ${creds_file}"
  echo -e "  ${RED}${BOLD}⚠️  THIS FILE IS IN /tmp/ AND WILL BE DELETED ON REBOOT!${NC}"
  echo -e "  ${YELLOW}→ COPY THIS FILE TO A SECURE LOCATION NOW:${NC}"
  echo -e "    ${BLUE}scp root@$(hostname):${creds_file} ~/veracity-credentials.txt${NC}"
  echo -e "  ${YELLOW}→ OR VIEW IT NOW:${NC}"
  echo -e "    ${BLUE}cat ${creds_file}${NC}"
  echo -e "  ${YELLOW}→ THEN DELETE IT:${NC}"
  echo -e "    ${BLUE}rm ${creds_file}${NC}"
  echo ""
  echo -e "${BOLD}Services Status:${NC}"
  systemctl status server-manager --no-pager -l | head -3
  systemctl status server-manager-sidekiq --no-pager -l | head -3
  echo ""
  echo -e "${BOLD}Next Steps:${NC}"
  echo -e "  ${GREEN}1.${NC} ${BOLD}COPY THE CREDENTIALS FILE (see warning above)${NC}"
  echo -e "  ${GREEN}2.${NC} Access the dashboard and log in"
  echo -e "  ${GREEN}3.${NC} Enable 2FA for security"
  echo -e "  ${GREEN}4.${NC} Configure optional integrations (Gotify, Hetzner, Proxmox)"
  echo -e "  ${GREEN}5.${NC} Install minions on your servers:"
  echo -e "     ${BLUE}curl -sSL ${INSTALL_URL}/install/minion.sh | sudo bash${NC}"
  echo -e "  ${GREEN}6.${NC} Accept minion keys in the Onboarding page"
  echo ""
  echo -e "${YELLOW}${LOCK} Remember to:${NC}"
  echo -e "  - Change default passwords after first login"
  echo -e "  - Configure backup strategy"
  echo -e "  - Set up monitoring and alerts"
  echo ""
  echo -e "${CYAN}Installation log: ${LOG_FILE}${NC}"
  echo ""
}

# Export functions for use in other scripts
export -f init_logging log_message info success warning error fatal
export -f step section prompt prompt_password confirm
export -f generate_password generate_secret_key_base
export -f command_exists is_service_running is_service_enabled wait_for_service
export -f execute run_with_timeout retry_command spinner progress_bar
export -f detect_os is_os_supported get_package_manager
export -f update_system_packages install_packages
export -f save_credentials print_summary
