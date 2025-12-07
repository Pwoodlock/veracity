# frozen_string_literal: true

require "test_helper"

class SaltServiceTest < ActiveSupport::TestCase
  setup do
    # Clear any cached tokens before each test
    Rails.cache.clear
  end

  # =============================================================================
  # Test 4.1.1: ping_minion with mocked API response
  # =============================================================================
  test "ping_minion returns successful response for online minion" do
    minion_id = "web-server-01"
    expected_response = { "return" => [{ minion_id => true }] }

    SaltService.stubs(:api_call).returns(expected_response)

    result = SaltService.ping_minion(minion_id)

    assert_equal expected_response, result
    assert result["return"].first[minion_id]
  end

  test "ping_minion returns false for offline minion" do
    minion_id = "offline-server"
    expected_response = { "return" => [{ minion_id => false }] }

    SaltService.stubs(:api_call).returns(expected_response)

    result = SaltService.ping_minion(minion_id)

    assert_equal false, result["return"].first[minion_id]
  end

  test "ping_minion supports glob patterns" do
    expected_response = {
      "return" => [{
        "web-01" => true,
        "web-02" => true,
        "db-01" => false
      }]
    }

    SaltService.stubs(:api_call).returns(expected_response)

    result = SaltService.ping_minion("*")

    assert_equal 3, result["return"].first.keys.count
    assert result["return"].first["web-01"]
    assert_not result["return"].first["db-01"]
  end

  # =============================================================================
  # Test 4.1.2: list_keys returns structured key data
  # =============================================================================
  test "list_keys returns structured key data" do
    expected_response = {
      "return" => [{
        "data" => {
          "return" => {
            "minions" => ["minion-1", "minion-2", "minion-3"],
            "minions_pre" => ["pending-minion"],
            "minions_rejected" => ["rejected-minion"],
            "minions_denied" => []
          }
        }
      }]
    }

    SaltService.stubs(:api_call).returns(expected_response)

    result = SaltService.list_keys

    keys_data = result["return"].first["data"]["return"]
    assert_equal 3, keys_data["minions"].count
    assert_includes keys_data["minions"], "minion-1"
    assert_equal 1, keys_data["minions_pre"].count
    assert_equal "pending-minion", keys_data["minions_pre"].first
    assert_empty keys_data["minions_denied"]
  end

  test "list_keys includes all key states" do
    expected_response = {
      "return" => [{
        "data" => {
          "return" => {
            "minions" => ["accepted-1"],
            "minions_pre" => ["pending-1", "pending-2"],
            "minions_rejected" => ["rejected-1"],
            "minions_denied" => ["denied-1"]
          }
        }
      }]
    }

    SaltService.stubs(:api_call).returns(expected_response)

    result = SaltService.list_keys
    keys_data = result["return"].first["data"]["return"]

    assert keys_data.key?("minions"), "Should have accepted minions key"
    assert keys_data.key?("minions_pre"), "Should have pending minions key"
    assert keys_data.key?("minions_rejected"), "Should have rejected minions key"
    assert keys_data.key?("minions_denied"), "Should have denied minions key"
  end

  # =============================================================================
  # Test 4.1.3: get_grains parses grain data correctly
  # =============================================================================
  test "get_grains parses grain data correctly" do
    minion_id = "test-minion"
    expected_response = {
      "return" => [{
        minion_id => {
          "os" => "Ubuntu",
          "os_family" => "Debian",
          "osrelease" => "22.04",
          "ip4_interfaces" => { "eth0" => ["192.168.1.10"] },
          "mem_total" => 8192,
          "num_cpus" => 4,
          "kernel" => "Linux",
          "kernelrelease" => "5.15.0-91-generic"
        }
      }]
    }

    SaltService.stubs(:api_call).returns(expected_response)

    result = SaltService.get_grains(minion_id)
    grains = result["return"].first[minion_id]

    assert_equal "Ubuntu", grains["os"]
    assert_equal "Debian", grains["os_family"]
    assert_equal "22.04", grains["osrelease"]
    assert_equal 8192, grains["mem_total"]
    assert_equal 4, grains["num_cpus"]
    assert_includes grains["ip4_interfaces"]["eth0"], "192.168.1.10"
  end

  test "get_grains returns empty hash for unreachable minion" do
    minion_id = "unreachable-minion"
    expected_response = { "return" => [{ minion_id => {} }] }

    SaltService.stubs(:api_call).returns(expected_response)

    result = SaltService.get_grains(minion_id)

    assert_empty result["return"].first[minion_id]
  end

  # =============================================================================
  # Test 4.1.4: run_command builds correct API request
  # =============================================================================
  test "run_command builds correct API request and returns parsed result" do
    minion_id = "test-server"
    command = "test.ping"

    api_response = { "return" => [{ minion_id => true }] }
    SaltService.stubs(:api_call).returns(api_response)

    result = SaltService.run_command(minion_id, command)

    assert result[:success]
    assert_includes result[:output], "True"
  end

  test "run_command handles glob patterns with multiple results" do
    api_response = {
      "return" => [{
        "web-01" => "command output 1",
        "web-02" => "command output 2"
      }]
    }
    SaltService.stubs(:api_call).returns(api_response)

    result = SaltService.run_command("web-*", "cmd.run", ["echo hello"])

    assert result[:success]
    assert_includes result[:output], "web-01"
    assert_includes result[:output], "web-02"
  end

  test "run_command returns failure for no response" do
    minion_id = "offline-server"
    api_response = { "return" => [{ minion_id => nil }] }

    SaltService.stubs(:api_call).returns(api_response)

    result = SaltService.run_command(minion_id, "test.ping")

    assert_not result[:success]
    assert_match(/No response/, result[:output])
  end

  test "run_command handles command returning false" do
    minion_id = "test-server"
    api_response = { "return" => [{ minion_id => false }] }

    SaltService.stubs(:api_call).returns(api_response)

    result = SaltService.run_command(minion_id, "service.status", ["nginx"])

    assert_not result[:success]
    assert_match(/returned false/, result[:output])
  end

  # =============================================================================
  # Test 4.1.5: write_minion_pillar creates pillar files
  # =============================================================================
  test "write_minion_pillar creates pillar file structure" do
    minion_id = "test-minion"
    pillar_name = "netbird"
    pillar_data = { "setup_key" => "test-key-12345", "enabled" => true }

    # Create a temp directory structure for testing
    pillar_dir = "/srv/pillar/minions/#{minion_id}"
    pillar_file = "#{pillar_dir}/#{pillar_name}.sls"
    top_file = "/srv/pillar/top.sls"

    # Mock file operations
    FileUtils.stubs(:mkdir_p).with(pillar_dir).returns(true)
    File.stubs(:write).with(pillar_file, anything).returns(true)
    File.stubs(:chmod).with(0644, pillar_file).returns(0)
    File.stubs(:exist?).with(top_file).returns(false)
    File.stubs(:write).with(top_file, anything).returns(true)
    File.stubs(:chmod).with(0644, top_file).returns(0)

    result = SaltService.write_minion_pillar(minion_id, pillar_name, pillar_data)

    assert result[:success]
    assert_equal pillar_file, result[:pillar_file]
  end

  test "write_minion_pillar handles errors gracefully" do
    minion_id = "test-minion"
    pillar_name = "test"
    pillar_data = { "key" => "value" }

    # Simulate permission error
    FileUtils.stubs(:mkdir_p).raises(Errno::EACCES.new("Permission denied"))

    result = SaltService.write_minion_pillar(minion_id, pillar_name, pillar_data)

    assert_not result[:success]
    assert_match(/Permission denied/, result[:error])
  end

  # =============================================================================
  # Test 4.1.6: Error handling for API failures
  # =============================================================================
  test "api_call raises ConnectionError on timeout" do
    SaltService.stubs(:auth_token).returns("test-token")
    SaltService.stubs(:post).raises(Net::ReadTimeout.new("Connection timed out"))

    assert_raises(SaltService::ConnectionError) do
      SaltService.api_call(:post, "/test")
    end
  end

  test "api_call raises AuthenticationError on 401 response with retry exhausted" do
    SaltService.stubs(:auth_token).returns("expired-token")

    # First call fails with 401, retry also fails
    mock_response = mock
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(401)
    mock_response.stubs(:parsed_response).returns({ "error" => "Unauthorized" })
    mock_response.stubs(:message).returns("Unauthorized")

    SaltService.stubs(:post).returns(mock_response)
    SaltService.stubs(:clear_token!).returns(nil)
    SaltService.stubs(:authenticate!).raises(SaltService::AuthenticationError.new("Auth failed"))

    assert_raises(SaltService::AuthenticationError) do
      SaltService.api_call(:post, "/test", { body: {}.to_json })
    end
  end

  test "run_command catches exceptions and returns error hash" do
    minion_id = "test-server"

    SaltService.stubs(:api_call).raises(StandardError.new("Unexpected error"))

    result = SaltService.run_command(minion_id, "test.ping")

    assert_not result[:success]
    assert_match(/Unexpected error/, result[:output])
  end

  test "token_expired? returns true when no token exists" do
    Rails.cache.clear

    assert SaltService.token_expired?
  end

  test "token_expired? returns false for valid token" do
    Rails.cache.write("salt_api_auth_token", "valid-token", expires_in: 1.hour)
    Rails.cache.write("salt_api_token_expires_at", 1.hour.from_now, expires_in: 1.hour)

    assert_not SaltService.token_expired?
  end
end
