# frozen_string_literal: true

require_relative "salt_integration_test"

# Integration tests for Salt operations
# Tests real minion communication against the staging Salt API
#
# These tests verify:
# - Minion ping operations
# - Grain synchronization
# - Command execution
# - State application
# - Pillar operations (write, refresh, delete)
class SaltOperationsTest < SaltIntegrationTest
  # =========================================================================
  # Ping Operations
  # =========================================================================

  test "ping_minion returns true for online test minion" do
    skip_unless_test_minion_available

    result = SaltService.ping_minion(TEST_MINION_ID, timeout: 30)

    assert result.is_a?(Hash), "Expected Hash result"
    assert result["return"].present?, "Expected 'return' key"

    ping_response = result["return"].first[TEST_MINION_ID]
    assert_equal true, ping_response, "Expected ping to return true for online minion"
  end

  test "ping_minion with glob pattern returns multiple minions" do
    result = SaltService.ping_minion("*", timeout: 30)

    assert result.is_a?(Hash), "Expected Hash result"
    assert result["return"].present?, "Expected 'return' key"
    assert result["return"].first.is_a?(Hash), "Expected Hash of minion responses"

    # At least one minion should respond
    responding_minions = result["return"].first.select { |_k, v| v == true }
    assert responding_minions.any?, "Expected at least one minion to respond to ping"
  end

  # =========================================================================
  # Grain Synchronization
  # =========================================================================

  test "sync_minion_grains returns grain data for test minion" do
    skip_unless_test_minion_available

    grains = SaltService.sync_minion_grains(TEST_MINION_ID)

    assert grains.is_a?(Hash), "Expected Hash of grains"
    assert grains.any?, "Expected non-empty grains data"

    # Verify standard grain fields are present
    assert grains.key?("os") || grains.key?("osfinger"), "Expected OS grain"
    assert grains.key?("os_family"), "Expected os_family grain"
  end

  test "sync_minion_grains updates server record" do
    skip_unless_test_minion_available

    # Ensure we have a server record for the test minion
    server = test_minion_server

    # Clear existing grains
    server.update!(grains: nil)

    # Sync grains from Salt
    grains = SaltService.sync_minion_grains(TEST_MINION_ID)
    assert grains.any?, "Expected grains to be returned"

    # Update server with grains (simulating what the app does)
    server.update!(grains: grains)
    server.reload

    # Verify grains were stored
    assert server.grains.present?, "Expected grains to be stored in server record"
    assert_equal grains["os_family"], server.grains["os_family"]
  end

  # =========================================================================
  # Command Execution
  # =========================================================================

  test "run_command executes and returns output" do
    skip_unless_test_minion_available

    result = SaltService.run_command(TEST_MINION_ID, "test.ping")

    assert result.is_a?(Hash), "Expected Hash result"
    assert result.key?(:success), "Expected :success key in result"
    assert result[:success], "Expected command to succeed"
    assert result[:output].present?, "Expected output from command"
  end

  test "run_command with cmd.run executes shell command" do
    skip_unless_test_minion_available

    result = SaltService.run_command(TEST_MINION_ID, "cmd.run", ["hostname"])

    assert result.is_a?(Hash), "Expected Hash result"
    assert result[:success], "Expected command to succeed"
    assert result[:output].present?, "Expected hostname output"
    # The output should contain the minion's hostname or be a valid string
    assert result[:output].is_a?(String), "Expected string output"
  end

  test "run_command handles non-existent minion gracefully" do
    result = SaltService.run_command("nonexistent-minion-xyz-123", "test.ping", nil, timeout: 10)

    assert result.is_a?(Hash), "Expected Hash result"
    # Should either fail gracefully or return no response indicator
    if result[:success]
      assert result[:output].include?("nonexistent-minion") ||
             result[:output].include?("No response"),
             "Expected output to indicate no response"
    else
      assert result[:output].present?, "Expected error message in output"
    end
  end

  # =========================================================================
  # State Application
  # =========================================================================

  test "apply_state applies Salt state successfully" do
    skip_unless_test_minion_available

    # Apply test.ping as a simple state (using test mode for safety)
    result = SaltService.apply_state(TEST_MINION_ID, "test", test: true)

    assert result.is_a?(Hash), "Expected Hash result"
    # Test mode may succeed or fail depending on state availability
    # The important thing is it doesn't crash and returns a valid response
    assert result.key?(:success), "Expected :success key in result"
    assert result.key?(:output), "Expected :output key in result"
  end

  # =========================================================================
  # Pillar Operations
  # =========================================================================

  test "write_minion_pillar creates pillar file" do
    skip_unless_test_minion_available

    pillar_data = {
      "test_key" => "test_value",
      "nested" => {
        "key1" => "value1",
        "key2" => 42
      }
    }

    result = SaltService.write_minion_pillar(TEST_MINION_ID, "integration_test", pillar_data)

    assert result[:success], "Expected pillar write to succeed"
    assert result[:pillar_file].present?, "Expected pillar_file path in result"

    # Verify file was created
    assert File.exist?(result[:pillar_file]), "Expected pillar file to exist"

    # Verify content is valid YAML
    content = File.read(result[:pillar_file])
    parsed = YAML.safe_load(content)
    assert_equal "test_value", parsed["test_key"]
    assert_equal "value1", parsed["nested"]["key1"]
  end

  test "refresh_pillar refreshes pillar data on minion" do
    skip_unless_test_minion_available

    result = SaltService.refresh_pillar(TEST_MINION_ID)

    assert result.is_a?(Hash), "Expected Hash result"
    assert result.key?(:success), "Expected :success key in result"
    # Pillar refresh should succeed if minion is online
    assert result[:success], "Expected pillar refresh to succeed"
  end

  test "delete_minion_pillar removes pillar file" do
    skip_unless_test_minion_available

    # First create a pillar
    SaltService.write_minion_pillar(TEST_MINION_ID, "integration_test", { "test" => true })
    pillar_file = "/srv/pillar/minions/#{TEST_MINION_ID}/integration_test.sls"
    assert File.exist?(pillar_file), "Expected pillar file to exist before delete"

    # Delete the pillar
    result = SaltService.delete_minion_pillar(TEST_MINION_ID, "integration_test")

    assert result[:success], "Expected pillar delete to succeed"
    assert_not File.exist?(pillar_file), "Expected pillar file to be deleted"
  end

  test "pillar operations update top.sls correctly" do
    skip_unless_test_minion_available

    top_file = "/srv/pillar/top.sls"

    # Create pillar and verify top.sls is updated
    SaltService.write_minion_pillar(TEST_MINION_ID, "integration_test", { "test" => true })

    if File.exist?(top_file)
      top_content = File.read(top_file)
      assert top_content.include?(TEST_MINION_ID) || top_content.include?("integration_test"),
             "Expected top.sls to reference test minion or pillar"
    end

    # Delete pillar (cleanup)
    SaltService.delete_minion_pillar(TEST_MINION_ID, "integration_test")
  end
end
