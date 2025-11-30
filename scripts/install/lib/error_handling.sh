#!/bin/bash
#
# error_handling.sh - Comprehensive error handling and recovery system
# Provides checkpointing, rollback, and recovery capabilities
#

# Prevent multiple sourcing
[[ -n "${VERACITY_ERROR_HANDLING_SOURCED:-}" ]] && return 0
readonly VERACITY_ERROR_HANDLING_SOURCED=1

# State directory for checkpoints and recovery
readonly STATE_DIR="/var/lib/veracity-installer"
readonly CHECKPOINT_FILE="${STATE_DIR}/checkpoints"
readonly ERROR_LOG="${STATE_DIR}/errors.log"
readonly ROLLBACK_SCRIPT="${STATE_DIR}/rollback.sh"

# Current installation phase
CURRENT_PHASE=""
CURRENT_STEP=""

#######################################
# Initialize error handling system
#######################################
init_error_handling() {
  # Create state directory
  mkdir -p "${STATE_DIR}"
  chmod 700 "${STATE_DIR}"

  # Initialize checkpoint file
  if [ ! -f "${CHECKPOINT_FILE}" ]; then
    echo "# Veracity Installation Checkpoints" > "${CHECKPOINT_FILE}"
    echo "# Format: timestamp|phase|status" >> "${CHECKPOINT_FILE}"
  fi

  # Initialize rollback script
  cat > "${ROLLBACK_SCRIPT}" << 'EOF'
#!/bin/bash
# Auto-generated rollback script
set -euo pipefail

echo "Rolling back Veracity installation..."

EOF
  chmod 700 "${ROLLBACK_SCRIPT}"

  # Set up error traps
  trap 'handle_error ${LINENO} "$BASH_COMMAND" $?' ERR
  trap 'handle_exit' EXIT INT TERM

  log_message "INFO" "Error handling system initialized"
}

#######################################
# Log a message with timestamp and level
# Arguments:
#   $1 - Level (INFO, WARN, ERROR, FATAL)
#   $2 - Message
#######################################
log_message() {
  local level="${1:-INFO}"
  local message="${2:-}"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Ensure state directory exists before logging
  if [ ! -d "${STATE_DIR}" ]; then
    mkdir -p "${STATE_DIR}" 2>/dev/null || true
  fi

  # Log to file
  echo "[${timestamp}] [${level}] ${message}" >> "${ERROR_LOG}" 2>/dev/null || true

  # Also log to main log if available
  if [[ -n "${LOG_FILE:-}" ]] && [[ -f "${LOG_FILE}" ]]; then
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
  fi
}

#######################################
# Handle errors
# Arguments:
#   $1 - Line number where error occurred
#   $2 - Command that failed
#   $3 - Exit code
#######################################
handle_error() {
  local line_number="${1:-0}"
  local command="${2:-unknown}"
  local exit_code="${3:-1}"

  # Don't handle errors from subshells or ignored commands
  [[ $exit_code -eq 0 ]] && return 0

  log_message "ERROR" "Command failed at line ${line_number}: ${command} (exit code: ${exit_code})"

  # Display error to user
  echo ""
  echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║                     INSTALLATION ERROR                         ║${NC}"
  echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${YELLOW}Phase:${NC} ${CURRENT_PHASE}"
  echo -e "${YELLOW}Step:${NC} ${CURRENT_STEP}"
  echo -e "${YELLOW}Line:${NC} ${line_number}"
  echo -e "${YELLOW}Exit Code:${NC} ${exit_code}"
  echo ""
  echo -e "${YELLOW}Command that failed:${NC}"
  echo "  ${command}"
  echo ""

  # Provide context-specific error information
  provide_error_context "${CURRENT_PHASE}" "${exit_code}"

  # Show recent log entries
  echo -e "${YELLOW}Recent log entries:${NC}"
  if [[ -f "${LOG_FILE:-}" ]]; then
    tail -n 10 "${LOG_FILE}" 2>/dev/null | sed 's/^/  /' || true
  fi
  echo ""

  # Offer recovery options
  echo -e "${CYAN}Recovery options:${NC}"
  echo "  1. Check the error log: ${ERROR_LOG}"
  echo "  2. Review installation log: ${LOG_FILE:-/var/log/veracity-install.log}"
  echo "  3. Check service status: systemctl status <service-name>"
  echo "  4. View recent system logs: journalctl -n 50 --no-pager"
  echo "  5. Run rollback script: ${ROLLBACK_SCRIPT}"
  echo ""
  echo -e "${YELLOW}To resume installation after fixing issues:${NC}"
  echo "  sudo ./install.sh --resume"
  echo ""

  # Mark checkpoint as failed
  mark_checkpoint_failed "${CURRENT_PHASE}"

  # Set flag to prevent duplicate error messages from EXIT trap
  export ERROR_SHOWN=1

  # Exit immediately with the error code
  exit ${exit_code}
}

#######################################
# Provide context-specific error information
# Arguments:
#   $1 - Phase that failed
#   $2 - Exit code
#######################################
provide_error_context() {
  local phase="${1:-Unknown}"
  local exit_code="${2:-1}"

  echo -e "${YELLOW}Likely causes:${NC}"

  case "${phase}" in
    "Prerequisites")
      echo "  • System doesn't meet minimum requirements"
      echo "  • Not running as root"
      echo "  • Network connectivity issues"
      echo "  • Unsupported operating system"
      ;;
    "PostgreSQL")
      echo "  • PostgreSQL repository not accessible"
      echo "  • Port 5432 already in use"
      echo "  • Insufficient disk space"
      echo "  • Database initialization failed"
      ;;
    "Redis")
      echo "  • Redis repository not accessible"
      echo "  • Port 6379 already in use"
      echo "  • Service failed to start"
      ;;
    "SaltStack")
      echo "  • Salt repository not accessible"
      echo "  • Salt API failed to bind to port 8001"
      echo "  • PAM authentication configuration failed"
      echo "  • Check: journalctl -u salt-api -n 50"
      ;;
    "Ruby")
      echo "  • rbenv installation failed"
      echo "  • Ruby build dependencies missing"
      echo "  • Ruby compilation timeout or failure"
      echo "  • Insufficient memory for compilation"
      ;;
    "Node.js")
      echo "  • NodeSource repository not accessible"
      echo "  • Node.js package installation failed"
      ;;
    "Caddy")
      echo "  • Caddy repository not accessible"
      echo "  • Port 80 or 443 already in use"
      echo "  • Invalid domain name"
      echo "  • Let's Encrypt rate limit reached"
      ;;
    "Application")
      echo "  • Git clone failed"
      echo "  • Bundle install failed (dependency issues)"
      echo "  • Database migration failed"
      echo "  • Asset precompilation failed"
      ;;
    "Systemd")
      echo "  • Service file creation failed"
      echo "  • Service failed to start"
      echo "  • Check: systemctl status server-manager"
      echo "  • Check: systemctl status server-manager-sidekiq"
      ;;
    *)
      echo "  • Unknown error in phase: ${phase}"
      echo "  • Check error log for details"
      ;;
  esac
  echo ""

  # Provide specific diagnostic commands
  echo -e "${YELLOW}Diagnostic commands:${NC}"
  case "${phase}" in
    "PostgreSQL")
      echo "  sudo systemctl status postgresql"
      echo "  sudo -u postgres psql -l"
      ;;
    "Redis")
      echo "  sudo systemctl status redis-server"
      echo "  redis-cli ping"
      ;;
    "SaltStack")
      echo "  sudo systemctl status salt-master"
      echo "  sudo systemctl status salt-api"
      echo "  sudo ss -tlnp | grep 8001"
      echo "  sudo journalctl -u salt-api -n 50 --no-pager"
      ;;
    "Application")
      echo "  cd /opt/veracity/app && sudo -u deploy bundle check"
      echo "  cd /opt/veracity/app && sudo -u deploy RAILS_ENV=production bundle exec rails db:version"
      ;;
  esac
  echo ""
}

#######################################
# Handle exit (cleanup)
#######################################
handle_exit() {
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    log_message "FATAL" "Installation failed with exit code ${exit_code}"

    # Don't show exit message if we already showed error
    if [ -z "${ERROR_SHOWN:-}" ]; then
      echo ""
      echo -e "${RED}Installation failed. Check the error log for details.${NC}"
      echo -e "${YELLOW}Error log:${NC} ${ERROR_LOG}"
      echo -e "${YELLOW}Installation log:${NC} ${LOG_FILE:-/var/log/veracity-install.log}"
      echo ""
    fi
  fi

  export ERROR_SHOWN=1
}

#######################################
# Create a checkpoint
# Arguments:
#   $1 - Phase name
#   $2 - Status (started|completed|failed)
#######################################
checkpoint() {
  local phase="${1:-unknown}"
  local status="${2:-unknown}"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  echo "${timestamp}|${phase}|${status}" >> "${CHECKPOINT_FILE}"
  log_message "INFO" "Checkpoint: ${phase} ${status}"

  if [[ "${status}" == "started" ]]; then
    CURRENT_PHASE="${phase}"
  fi
}

#######################################
# Mark checkpoint as failed
# Arguments:
#   $1 - Phase name
#######################################
mark_checkpoint_failed() {
  local phase="${1:-unknown}"
  checkpoint "${phase}" "failed"
}

#######################################
# Check if phase was completed
# Arguments:
#   $1 - Phase name
# Returns:
#   0 if completed, 1 otherwise
#######################################
is_phase_completed() {
  local phase="${1:-}"

  if [ ! -f "${CHECKPOINT_FILE}" ]; then
    return 1
  fi

  grep -q "^.*|${phase}|completed$" "${CHECKPOINT_FILE}" 2>/dev/null
}

#######################################
# Get last completed phase
# Returns:
#   Name of last completed phase, or empty string
#######################################
get_last_completed_phase() {
  if [ ! -f "${CHECKPOINT_FILE}" ]; then
    echo ""
    return
  fi

  grep "|completed$" "${CHECKPOINT_FILE}" 2>/dev/null | tail -1 | cut -d'|' -f2 || echo ""
}

#######################################
# Get failed phases
# Returns:
#   List of failed phases, one per line
#######################################
get_failed_phases() {
  if [ ! -f "${CHECKPOINT_FILE}" ]; then
    return
  fi

  grep "|failed$" "${CHECKPOINT_FILE}" 2>/dev/null | cut -d'|' -f2 || true
}

#######################################
# Add rollback command
# Adds a command to be executed during rollback
# Arguments:
#   $1 - Command description
#   $2 - Command to execute
#######################################
add_rollback() {
  local description="${1:-No description}"
  local command="${2:-true}"

  cat >> "${ROLLBACK_SCRIPT}" << EOF

# ${description}
echo "  • ${description}"
${command} 2>/dev/null || true

EOF
}

#######################################
# Execute rollback
#######################################
execute_rollback() {
  section "Rolling Back Installation"

  if [ ! -f "${ROLLBACK_SCRIPT}" ]; then
    warning "No rollback script found"
    return 1
  fi

  info "Executing rollback commands..."
  bash "${ROLLBACK_SCRIPT}" || true

  success "Rollback completed"
  info "You can now try installing again after resolving the issues"
}

#######################################
# Safe execution wrapper
# Executes a command with error handling
# Arguments:
#   $1 - Description of what the command does
#   $2+ - Command and arguments to execute
#######################################
safe_execute() {
  local description="${1:-Executing command}"
  shift
  local command=("$@")

  CURRENT_STEP="${description}"
  log_message "INFO" "Executing: ${description}"

  # Execute command and capture output
  local output
  local exit_code=0

  output=$("${command[@]}" 2>&1) || exit_code=$?

  if [ $exit_code -ne 0 ]; then
    log_message "ERROR" "${description} failed with exit code ${exit_code}"
    log_message "ERROR" "Output: ${output}"

    echo ""
    error "${description} failed!"
    echo ""
    echo -e "${YELLOW}Command output:${NC}"
    echo "${output}" | sed 's/^/  /'
    echo ""

    return ${exit_code}
  fi

  log_message "INFO" "${description} completed successfully"
  return 0
}

#######################################
# Run phase with error handling
# Executes a phase function with full error handling
# Arguments:
#   $1 - Phase name
#   $2 - Phase function to execute
#   $3 - Optional: "required" or "optional"
#######################################
run_phase() {
  local phase_name="${1:-unknown}"
  local phase_function="${2:-}"
  local phase_type="${3:-required}"

  # Check if already completed (resume support)
  if is_phase_completed "${phase_name}"; then
    info "Phase '${phase_name}' already completed, skipping..."
    return 0
  fi

  # Mark phase as started
  checkpoint "${phase_name}" "started"
  CURRENT_PHASE="${phase_name}"

  # Execute phase
  local exit_code=0
  ${phase_function} || exit_code=$?

  if [ $exit_code -ne 0 ]; then
    if [ "${phase_type}" == "optional" ]; then
      warning "Optional phase '${phase_name}' failed, continuing..."
      checkpoint "${phase_name}" "skipped"
      return 0
    else
      mark_checkpoint_failed "${phase_name}"
      return ${exit_code}
    fi
  fi

  # Mark phase as completed
  checkpoint "${phase_name}" "completed"
  success "Phase '${phase_name}' completed successfully"

  return 0
}

#######################################
# Show resume information
#######################################
show_resume_info() {
  section "Installation Resume Information"

  local last_completed
  last_completed=$(get_last_completed_phase)

  if [ -z "${last_completed}" ]; then
    info "No phases have been completed yet"
    return
  fi

  info "Last completed phase: ${last_completed}"
  echo ""

  local failed_phases
  failed_phases=$(get_failed_phases)

  if [ -n "${failed_phases}" ]; then
    warning "Failed phases:"
    echo "${failed_phases}" | sed 's/^/  • /'
    echo ""
  fi

  info "You can resume the installation after fixing any issues"
  echo ""
}

#######################################
# Validate system state before phase
# Performs pre-flight checks before each phase
# Arguments:
#   $1 - Phase name
# Returns:
#   0 if validation passed, 1 otherwise
#######################################
validate_phase_prerequisites() {
  local phase="${1:-unknown}"

  log_message "INFO" "Validating prerequisites for phase: ${phase}"

  case "${phase}" in
    "PostgreSQL")
      # Check port availability
      if ss -tln | grep -q ":5432 "; then
        error "Port 5432 is already in use"
        info "PostgreSQL or another service is already running on port 5432"
        return 1
      fi
      ;;

    "Redis")
      # Check port availability
      if ss -tln | grep -q ":6379 "; then
        error "Port 6379 is already in use"
        info "Redis or another service is already running on port 6379"
        return 1
      fi
      ;;

    "SaltStack")
      # Check port availability
      if ss -tln | grep -q ":4505 "; then
        warning "Port 4505 is already in use (Salt Publisher)"
      fi
      if ss -tln | grep -q ":4506 "; then
        warning "Port 4506 is already in use (Salt Request Server)"
      fi
      if ss -tln | grep -q ":8001 "; then
        error "Port 8001 is already in use"
        info "Salt API or another service is already running on port 8001"
        return 1
      fi
      ;;

    "Caddy")
      # Check port availability
      if ss -tln | grep -q ":80 " && ! systemctl is-active caddy >/dev/null 2>&1; then
        error "Port 80 is already in use"
        info "Another web server is running on port 80"
        return 1
      fi
      if ss -tln | grep -q ":443 " && ! systemctl is-active caddy >/dev/null 2>&1; then
        warning "Port 443 is already in use"
      fi
      ;;

    "Application")
      # Check if Ruby is installed (via mise for deploy user)
      if ! sudo -u deploy bash -c 'export PATH="$HOME/.local/bin:$PATH" && eval "$($HOME/.local/bin/mise activate bash)" && command -v ruby' >/dev/null 2>&1; then
        error "Ruby is not installed"
        return 1
      fi

      # Check if PostgreSQL is running
      if ! systemctl is-active postgresql >/dev/null 2>&1; then
        error "PostgreSQL is not running"
        return 1
      fi

      # Check if Redis is running
      if ! systemctl is-active redis-server >/dev/null 2>&1 && ! systemctl is-active redis >/dev/null 2>&1; then
        error "Redis is not running"
        return 1
      fi
      ;;
  esac

  log_message "INFO" "Phase prerequisites validated: ${phase}"
  return 0
}
