# frozen_string_literal: true

require "test_helper"

# Tests for InstallController
# Verifies that the minion installation script is properly generated and served
class InstallControllerTest < ActionDispatch::IntegrationTest
  # =========================================================================
  # Minion Installation Script Generation
  # =========================================================================

  test "minion endpoint returns shell script" do
    get install_minion_url

    assert_response :success
    assert_equal "text/plain; charset=utf-8", response.headers["Content-Type"]
    assert_match(/^#!\/bin\/bash/, response.body)
  end

  test "minion script includes required Salt components" do
    get install_minion_url

    assert_response :success

    # Verify script structure
    assert_match(/Salt Minion Installation Script/, response.body)
    assert_match(/set -e/, response.body, "Script should exit on error")

    # Verify OS detection
    assert_match(/Detecting operating system/, response.body)
    assert_match(/\/etc\/os-release/, response.body)

    # Verify cleanup function
    assert_match(/cleanup_salt_minion/, response.body)
    assert_match(/Performing Complete Salt Minion Cleanup/, response.body)

    # Verify package installation for each OS family
    assert_match(/debian.*apt-get.*salt-minion/m, response.body)
    assert_match(/redhat.*salt-minion/m, response.body)
    assert_match(/suse.*zypper.*salt-minion/m, response.body)
    assert_match(/arch.*pacman.*salt/m, response.body)
  end

  test "minion script includes universal connection fix" do
    get install_minion_url

    assert_response :success

    # Verify universal restart (not Debian-specific)
    assert_match(/Universal fix.*restart service/m, response.body)
    assert_match(/This applies to ALL OS families/, response.body)
    refute_match(/if.*OS_FAMILY.*=.*debian.*then/m, response.body,
                 "Should not have Debian-specific conditional for restart")

    # Verify restart sequence
    assert_match(/systemctl restart salt-minion/, response.body)
    assert_match(/sleep 3.*Give initial start time to settle/, response.body)

    # Verify service verification
    assert_match(/systemctl is-active.*salt-minion/, response.body)
  end

  test "minion script includes enhanced fingerprint retrieval" do
    get install_minion_url

    assert_response :success

    # Verify fingerprint retrieval with error handling
    assert_match(/salt-call --local key.finger/, response.body)
    assert_match(/\/etc\/salt\/pki\/minion\/minion.pub/, response.body)

    # Verify retry logic
    assert_match(/Retry once/, response.body)
    assert_match(/if.*-n.*FINGERPRINT/m, response.body, "Should check if fingerprint is not empty")

    # Verify error messages
    assert_match(/Could not retrieve fingerprint/, response.body)
    assert_match(/Key not generated yet/, response.body)
  end

  test "minion script configures master hostname correctly" do
    get install_minion_url

    assert_response :success

    # Verify master configuration uses request.host
    expected_master = request.host
    assert_match(/master: #{Regexp.escape(expected_master)}/, response.body)
    assert_match(/SALT_MASTER="#{Regexp.escape(expected_master)}"/, response.body)
  end

  test "minion script includes security warnings" do
    get install_minion_url

    assert_response :success

    # Verify fingerprint verification requirement
    assert_match(/MUST accept this key before the minion can be managed/, response.body)
    assert_match(/Always verify the fingerprint matches/, response.body)
    assert_match(/Security Note/, response.body)
  end

  test "minion script includes troubleshooting guidance" do
    get install_minion_url

    assert_response :success

    # Verify troubleshooting section
    assert_match(/Logs & Troubleshooting/, response.body)
    assert_match(/\/var\/log\/salt\/minion/, response.body)
    assert_match(/systemctl status salt-minion/, response.body)

    # Verify universal reconnect command (no OS-specific conditionals)
    assert_match(/systemctl restart salt-minion/, response.body)
    refute_match(/if.*OS_FAMILY.*!=.*debian/m, response.body,
                 "Should not have OS-specific troubleshooting conditionals")
  end

  test "minion script is idempotent on reinstall" do
    get install_minion_url

    assert_response :success

    # Verify reinstallation detection
    assert_match(/Checking for existing Salt minion/, response.body)
    assert_match(/REINSTALLATION DETECTED/, response.body)

    # Verify cleanup options
    assert_match(/Complete cleanup and fresh install/, response.body)
    assert_match(/Keep existing installation and reconfigure/, response.body)
  end

  test "minion script removes master package correctly" do
    get install_minion_url

    assert_response :success

    # Verify master removal for each OS family
    assert_match(/salt-master/, response.body)
    assert_match(/apt-get remove.*salt-master/m, response.body)
    assert_match(/dnf.*remove.*salt-master/m, response.body)
    assert_match(/zypper remove.*salt-master/m, response.body)

    # Verify master is disabled
    assert_match(/systemctl.*disable.*salt-master/, response.body)
    assert_match(/systemctl.*mask.*salt-master/, response.body)
  end

  test "minion script logs installation request" do
    assert_difference -> { Rails.logger.info("Test") && true }, 0 do
      # Capture log output
      original_logger = Rails.logger
      log_output = StringIO.new
      Rails.logger = Logger.new(log_output)

      get install_minion_url

      # Restore logger
      Rails.logger = original_logger

      # Verify logging
      assert_match(/Install script requested from IP/, log_output.string)
    end
  end

  test "minion endpoint does not require authentication" do
    # Don't sign in - this endpoint should be public
    get install_minion_url

    assert_response :success
    refute_match(/sign in/i, response.body, "Should not redirect to sign in")
  end

  test "minion script includes all supported OS families" do
    get install_minion_url

    assert_response :success

    # Verify all OS families are supported
    %w[debian redhat suse arch].each do |os_family|
      assert_match(/#{os_family}/i, response.body,
                   "Script should support #{os_family} OS family")
    end

    # Verify specific distros
    assert_match(/ubuntu|debian/i, response.body)
    assert_match(/centos|rocky|alma|rhel|fedora/i, response.body)
    assert_match(/sles|opensuse/i, response.body)
    assert_match(/arch|manjaro/i, response.body)
  end

  test "minion script has proper error handling" do
    get install_minion_url

    assert_response :success

    # Verify error handling
    assert_match(/set -e/, response.body, "Should exit on error")
    assert_match(/if.*EUID.*-ne 0/m, response.body, "Should check for root")
    assert_match(/Cannot detect OS/, response.body)
    assert_match(/Unsupported OS/, response.body)
  end

  test "minion script version matches Salt 3007 LTS" do
    get install_minion_url

    assert_response :success

    # Verify Salt version
    assert_match(/SALT_VERSION="3007"/, response.body)
    assert_match(/Updated to LTS version/, response.body)
  end
end
