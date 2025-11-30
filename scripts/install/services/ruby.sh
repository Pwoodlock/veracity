#!/bin/bash
#
# ruby.sh - Ruby installation via Mise (per Rails official documentation)
# Reference: https://guides.rubyonrails.org/install_ruby_on_rails.html
#

set -euo pipefail

# Source common functions
SERVICE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SERVICE_SCRIPT_DIR}/../lib/common.sh"
# shellcheck source=../lib/validators.sh
source "${SERVICE_SCRIPT_DIR}/../lib/validators.sh"

# Ruby version to install (per Rails 8.1 documentation)
readonly RUBY_VERSION="3.3.6"
readonly DEPLOY_USER="deploy"
readonly DEPLOY_HOME="/home/${DEPLOY_USER}"

#######################################
# Create deploy user
#######################################
create_deploy_user() {
  step "Creating deploy user..."

  if user_exists "${DEPLOY_USER}"; then
    info "User ${DEPLOY_USER} already exists"
    return 0
  fi

  # Create deploy user with home directory
  execute useradd -m -s /bin/bash -c "Veracity Deploy User" "${DEPLOY_USER}"

  # Add deploy user to necessary groups
  if getent group www-data &>/dev/null; then
    execute usermod -aG www-data "${DEPLOY_USER}"
  fi

  # Configure passwordless sudo for Salt commands
  info "Configuring sudo access for Salt commands..."
  echo "${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/salt, /usr/bin/salt-key, /usr/bin/salt-call, /usr/bin/salt-run" > /etc/sudoers.d/deploy-salt
  chmod 440 /etc/sudoers.d/deploy-salt

  success "Deploy user created: ${DEPLOY_USER}"
}

#######################################
# Install system dependencies for Ruby
# Per Rails guide: build-essential, rustc, libssl-dev, libyaml-dev, zlib1g-dev, libgmp-dev
#######################################
install_ruby_dependencies() {
  step "Installing Ruby build dependencies..."

  case "${OS_ID}" in
    ubuntu|debian)
      install_packages build-essential rustc libssl-dev libyaml-dev zlib1g-dev libgmp-dev git curl
      ;;
    rocky|almalinux|rhel)
      install_packages gcc make rust openssl-devel libyaml-devel zlib-devel gmp-devel git curl
      ;;
    *)
      fatal "Unsupported OS for Ruby installation: ${OS_ID}"
      ;;
  esac

  success "Ruby dependencies installed"
}

#######################################
# Install Mise version manager
# Per Rails guide: curl https://mise.run | sh
#######################################
install_mise() {
  step "Installing Mise version manager..."

  # Install Mise as deploy user
  if sudo -u "${DEPLOY_USER}" bash -c "command -v mise" &>/dev/null; then
    info "Mise already installed"
    return 0
  fi

  # Install Mise via official installer with retry logic
  local max_attempts=5
  local attempt=1
  local delay=5

  while [ $attempt -le $max_attempts ]; do
    info "Attempting to download Mise installer (attempt ${attempt}/${max_attempts})..."

    # Download and execute the installer with proper error handling
    if sudo -u "${DEPLOY_USER}" bash -c "curl -fsSL --retry 3 --retry-delay 2 https://mise.run | sh"; then
      # Verify mise was actually installed
      if sudo -u "${DEPLOY_USER}" bash -c "test -x \"\$HOME/.local/bin/mise\""; then
        success "Mise installed"
        return 0
      else
        error "Mise installer ran but binary not found"
      fi
    else
      error "Failed to download/install Mise (attempt ${attempt}/${max_attempts})"
    fi

    if [ $attempt -lt $max_attempts ]; then
      info "Retrying in ${delay} seconds..."
      sleep $delay
      delay=$((delay * 2))  # Exponential backoff
    fi

    attempt=$((attempt + 1))
  done

  fatal "Failed to install Mise after ${max_attempts} attempts. The mise.run service may be temporarily unavailable."
}

#######################################
# Configure Mise in bashrc
# Per Rails guide: Add mise activation to ~/.bashrc
#######################################
configure_mise() {
  step "Configuring Mise for ${DEPLOY_USER}..."

  # Add mise activation to bashrc if not already present
  if ! grep -q 'mise activate' "${DEPLOY_HOME}/.bashrc" 2>/dev/null; then
    execute sudo -u "${DEPLOY_USER}" bash -c "echo 'eval \"\$(\$HOME/.local/bin/mise activate bash)\"' >> ${DEPLOY_HOME}/.bashrc"
    success "Mise activation added to .bashrc"
  else
    info "Mise already configured in .bashrc"
  fi

  # Ensure .bash_profile sources .bashrc
  if [ ! -f "${DEPLOY_HOME}/.bash_profile" ]; then
    cat > "${DEPLOY_HOME}/.bash_profile" << 'EOF'
# Source .bashrc if it exists
if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
EOF
    execute chown "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_HOME}/.bash_profile"
  fi

  success "Mise configured"
}

#######################################
# Install Ruby via Mise
# Per Rails guide: mise use --global ruby@3
#######################################
install_ruby_via_mise() {
  step "Installing Ruby ${RUBY_VERSION} via Mise..."

  info "This may take 10-15 minutes as Ruby is compiled from source..."
  info "Compilation steps:"
  info "  • Downloading Ruby ${RUBY_VERSION} source"
  info "  • Configuring build (checking dependencies)"
  info "  • Compiling Ruby (~200,000 lines of C code)"
  info "  • Building standard library"
  info "  • Installing to ~/.local/share/mise/"
  echo ""

  # Install Ruby using Mise
  if ! execute sudo -u "${DEPLOY_USER}" bash -c "export PATH=\"\$HOME/.local/bin:\$PATH\" && mise use --global ruby@${RUBY_VERSION}"; then
    error "Failed to install Ruby ${RUBY_VERSION} via Mise"
    error "Check ${LOG_FILE} for detailed error messages"
    fatal "Ruby installation failed"
  fi

  success "Ruby ${RUBY_VERSION} installed via Mise"
}

#######################################
# Install bundler
#######################################
install_bundler() {
  step "Installing bundler..."

  execute sudo -u "${DEPLOY_USER}" bash -c "export PATH=\"\$HOME/.local/bin:\$PATH\" && eval \"\$(\$HOME/.local/bin/mise activate bash)\" && gem install bundler --no-document"

  success "Bundler installed"
}

#######################################
# Configure gem settings
#######################################
configure_gem_settings() {
  step "Configuring gem settings..."

  # Create .gemrc to skip documentation
  cat > "${DEPLOY_HOME}/.gemrc" << EOF
---
gem: --no-document
install: --no-document
update: --no-document
EOF

  execute chown "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_HOME}/.gemrc"

  success "Gem settings configured"
}

#######################################
# Verify Ruby installation
#######################################
verify_ruby() {
  step "Verifying Ruby installation..."

  # Use full path to mise for non-interactive shell
  local ruby_cmd="export PATH=\"\$HOME/.local/bin:\$PATH\" && eval \"\$(\$HOME/.local/bin/mise activate bash)\" && "

  local ruby_version
  ruby_version=$(sudo -u "${DEPLOY_USER}" bash -c "${ruby_cmd} ruby -v")
  info "Ruby version: ${ruby_version}"

  local gem_version
  gem_version=$(sudo -u "${DEPLOY_USER}" bash -c "${ruby_cmd} gem -v")
  info "RubyGems version: ${gem_version}"

  local bundler_version
  bundler_version=$(sudo -u "${DEPLOY_USER}" bash -c "${ruby_cmd} bundler -v")
  info "Bundler version: ${bundler_version}"

  # Verify correct Ruby version
  if sudo -u "${DEPLOY_USER}" bash -c "${ruby_cmd} ruby -v" | grep -q "${RUBY_VERSION}"; then
    success "Ruby ${RUBY_VERSION} verified successfully"
  else
    fatal "Ruby version mismatch"
  fi
}

#######################################
# Setup Ruby for Veracity
# Main function that orchestrates Ruby setup
#######################################
setup_ruby() {
  section "Installing Ruby ${RUBY_VERSION} via Mise (Rails Recommended)"

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

  # Create deploy user
  create_deploy_user

  # Install dependencies
  install_ruby_dependencies

  # Install and configure Mise
  install_mise
  configure_mise

  # Install Ruby
  install_ruby_via_mise

  # Configure gems and install bundler
  configure_gem_settings
  install_bundler

  # Verify installation
  verify_ruby

  success "Ruby setup complete via Mise!"
  info "Deploy user: ${DEPLOY_USER}"
  info "Ruby version: ${RUBY_VERSION}"
  info "Installed via: Mise (Rails recommended method)"
  info "Ruby location: ${DEPLOY_HOME}/.local/share/mise/installs/ruby/${RUBY_VERSION}"
}

# If script is executed directly, run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  setup_ruby
fi
