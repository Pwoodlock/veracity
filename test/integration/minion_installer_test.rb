# frozen_string_literal: true

require "test_helper"

# Integration tests for Salt Minion Installer Script
# Tests the actual behavior and logic of the generated installation script
#
# These tests verify:
# - Script syntax and structure
# - Connection fix logic (universal restart)
# - Fingerprint retrieval with retry
# - OS-specific package installation
# - Error handling and edge cases
#
# NOTE: These are static analysis tests of the script itself, not
# execution tests (which would require actual VM/container environments)
class MinionInstallerTest < ActionDispatch::IntegrationTest
  setup do
    @script = get_installer_script
  end

  # =========================================================================
  # Script Structure and Validation
  # =========================================================================

  test "installer script has valid bash shebang" do
    assert_match(/^#!\/bin\/bash\n/, @script)
  end

  test "installer script has exit on error enabled" do
    assert_match(/^set -e/, @script)
  end

  test "installer script has all required sections" do
    required_sections = [
      "Configuration",
      "Detecting operating system",
      "Checking for existing Salt minion",
      "Installing Salt",
      "Configuring Salt minion",
      "Starting Salt minion service",
      "Getting minion key fingerprint"
    ]

    required_sections.each do |section|
      assert_match(/#{Regexp.escape(section)}/i, @script,
                   "Script should include '#{section}' section")
    end
  end

  # =========================================================================
  # Connection Fix - Universal Restart Logic
  # =========================================================================

  test "connection fix applies to all OS families" do
    # Should NOT have Debian-specific conditional
    refute_match(/if\s+\[\s+"\$OS_FAMILY"\s+=\s+"debian"\s+\].*restart/m, @script,
                 "Connection fix should not be Debian-specific")

    # Should have universal restart comment
    assert_match(/Universal fix.*ALL OS families/m, @script)
  end

  test "connection fix includes proper timing" do
    # Verify sleep before restart
    assert_match(/sleep 3.*Give initial start time to settle/, @script)

    # Verify sleep after restart
    assert_match(/systemctl restart salt-minion.*sleep 3/m, @script)
  end

  test "connection fix verifies service is running" do
    assert_match(/systemctl is-active.*salt-minion/, @script)
    assert_match(/Salt minion service is running/, @script)
  end

  test "connection fix uses timeout for reliability" do
    assert_match(/timeout \d+ systemctl restart salt-minion/, @script,
                 "Restart should use timeout to prevent hanging")
  end

  # =========================================================================
  # Fingerprint Retrieval with Retry Logic
  # =========================================================================

  test "fingerprint retrieval checks if key file exists" do
    assert_match(/if \[ -f \/etc\/salt\/pki\/minion\/minion.pub \]/, @script)
  end

  test "fingerprint retrieval uses salt-call with error suppression" do
    assert_match(/salt-call --local key.finger.*2>\/dev\/null/, @script,
                 "Should suppress stderr to handle initialization gracefully")
  end

  test "fingerprint retrieval validates output is not empty" do
    assert_match(/if \[ -n "\$FINGERPRINT" \]/, @script,
                 "Should check if fingerprint variable is not empty")
  end

  test "fingerprint retrieval has retry logic" do
    assert_match(/Retry once/, @script)
    assert_match(/sleep 2/, @script, "Should wait before retry")

    # Should have two checks for minion.pub (initial + retry)
    pub_checks = @script.scan(/if \[ -f \/etc\/salt\/pki\/minion\/minion.pub \]/).length
    assert_operator pub_checks, :>=, 2, "Should check for key file at least twice"
  end

  test "fingerprint retrieval provides helpful error messages" do
    error_messages = [
      "Could not retrieve fingerprint",
      "Key not generated yet",
      "Key generation delayed"
    ]

    error_messages.each do |message|
      assert_match(/#{Regexp.escape(message)}/i, @script,
                   "Should include error message: '#{message}'")
    end
  end

  test "fingerprint retrieval shows preview on success" do
    assert_match(/FINGERPRINT:0:20/, @script,
                 "Should show first 20 chars of fingerprint as preview")
  end

  # =========================================================================
  # OS Detection and Package Installation
  # =========================================================================

  test "installer detects OS from /etc/os-release" do
    assert_match(/\/etc\/os-release/, @script)
    assert_match(/OS=\$ID/, @script)
    assert_match(/VER=\$VERSION_ID/, @script)
  end

  test "installer maps OS to package manager family" do
    os_families = {
      "debian" => %w[ubuntu debian],
      "redhat" => %w[rhel centos almalinux rocky fedora],
      "suse" => %w[sles opensuse],
      "arch" => %w[arch manjaro]
    }

    os_families.each do |family, distros|
      distros.each do |distro|
        assert_match(/#{distro}.*OS_FAMILY="#{family}"/m, @script,
                     "Should map #{distro} to #{family} family")
      end
    end
  end

  test "installer uses correct package manager for each family" do
    package_managers = {
      "debian" => "apt-get",
      "redhat" => "dnf|yum",
      "suse" => "zypper",
      "arch" => "pacman"
    }

    package_managers.each do |family, pm_pattern|
      assert_match(/#{family}.*#{pm_pattern}/mi, @script,
                   "Should use #{pm_pattern} for #{family}")
    end
  end

  # =========================================================================
  # Cleanup Function
  # =========================================================================

  test "cleanup function stops and disables service" do
    cleanup_section = extract_function("cleanup_salt_minion")

    assert_match(/systemctl stop salt-minion/, cleanup_section)
    assert_match(/systemctl disable salt-minion/, cleanup_section)
  end

  test "cleanup function kills remaining processes" do
    cleanup_section = extract_function("cleanup_salt_minion")

    assert_match(/pkill.*salt-minion/, cleanup_section)
    assert_match(/killall.*salt-minion/, cleanup_section)
  end

  test "cleanup function removes packages for all OS families" do
    cleanup_section = extract_function("cleanup_salt_minion")

    assert_match(/apt-get remove.*salt-minion/, cleanup_section)
    assert_match(/dnf remove.*salt-minion/, cleanup_section)
    assert_match(/zypper remove.*salt-minion/, cleanup_section)
    assert_match(/pacman.*salt/, cleanup_section)
  end

  test "cleanup function removes all config and data directories" do
    cleanup_section = extract_function("cleanup_salt_minion")

    directories = [
      "/etc/salt",
      "/var/cache/salt",
      "/var/log/salt",
      "/var/run/salt"
    ]

    directories.each do |dir|
      assert_match(/rm -rf #{Regexp.escape(dir)}/, cleanup_section,
                   "Should remove #{dir}")
    end
  end

  test "cleanup function verifies complete removal" do
    cleanup_section = extract_function("cleanup_salt_minion")

    assert_match(/Verifying complete removal/, cleanup_section)
    assert_match(/command -v salt-minion/, cleanup_section)
    assert_match(/pgrep.*salt-minion/, cleanup_section)
  end

  # =========================================================================
  # Security and Configuration
  # =========================================================================

  test "installer requires root privileges" do
    assert_match(/if \[ "\$EUID" -ne 0 \]/, @script)
    assert_match(/must be run as root/i, @script)
  end

  test "installer configures master hostname from request" do
    assert_match(/SALT_MASTER=/, @script)
    assert_match(/master: \$\{SALT_MASTER\}/, @script)
  end

  test "installer sets minion ID to hostname" do
    assert_match(/id: \$\(hostname -f\)/, @script)
  end

  test "installer includes security warnings" do
    assert_match(/Always verify the fingerprint/i, @script)
    assert_match(/Security Note/i, @script)
  end

  # =========================================================================
  # Master Package Prevention
  # =========================================================================

  test "installer prevents salt-master installation for all OS families" do
    # Debian
    assert_match(/apt-mark hold salt-master/, @script)
    assert_match(/apt-get remove.*salt-master/, @script)

    # RedHat
    assert_match(/versionlock add salt-master/, @script)
    assert_match(/dnf.*remove.*salt-master/, @script)

    # SUSE
    assert_match(/zypper remove.*salt-master/, @script)

    # Arch
    assert_match(/systemctl mask salt-master/, @script)
  end

  test "installer stops and disables salt-master service" do
    assert_match(/systemctl stop salt-master/, @script)
    assert_match(/systemctl disable salt-master/, @script)
  end

  # =========================================================================
  # Troubleshooting Section
  # =========================================================================

  test "troubleshooting section includes universal restart command" do
    troubleshooting_section = extract_troubleshooting_section

    assert_match(/systemctl restart salt-minion/, troubleshooting_section)
    refute_match(/if.*OS_FAMILY/, troubleshooting_section,
                 "Troubleshooting should not have OS-specific conditionals")
  end

  test "troubleshooting section includes log locations" do
    troubleshooting_section = extract_troubleshooting_section

    assert_match(/\/var\/log\/salt\/minion/, troubleshooting_section)
    assert_match(/tail -f/, troubleshooting_section)
  end

  test "troubleshooting section includes service status command" do
    troubleshooting_section = extract_troubleshooting_section

    assert_match(/systemctl status salt-minion/, troubleshooting_section)
  end

  # =========================================================================
  # Salt Version Configuration
  # =========================================================================

  test "installer uses Salt 3007 LTS version" do
    assert_match(/SALT_VERSION="3007"/, @script)
  end

  # =========================================================================
  # Error Handling
  # =========================================================================

  test "installer handles missing /etc/os-release" do
    assert_match(/Cannot detect OS.*os-release not found/i, @script)
    assert_match(/exit 1/, @script)
  end

  test "installer handles unsupported OS families" do
    assert_match(/Unsupported OS/i, @script)
  end

  test "installer uses || true for non-critical failures" do
    # Should not fail on cleanup operations
    assert_match(/pkill.*\|\| true/, @script)
    assert_match(/systemctl.*\|\| true/, @script)
  end

  # =========================================================================
  # Helper Methods
  # =========================================================================

  private

  def get_installer_script
    get install_minion_url
    assert_response :success
    response.body
  end

  def extract_function(function_name)
    # Extract function from script for targeted testing
    match = @script.match(/^#{function_name}\(\).*?^\}/m)
    assert match, "Function '#{function_name}' not found in script"
    match[0]
  end

  def extract_troubleshooting_section
    # Extract troubleshooting section for targeted testing
    match = @script.match(/Logs & Troubleshooting.*?echo ""/m)
    assert match, "Troubleshooting section not found in script"
    match[0]
  end
end
