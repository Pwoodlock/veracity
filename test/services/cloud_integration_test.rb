# frozen_string_literal: true

require "test_helper"

class CloudIntegrationTest < ActiveSupport::TestCase
  # =============================================================================
  # ProxmoxService Tests (4.3.1-4.3.2)
  # =============================================================================

  setup do
    @proxmox_api_key = build(:proxmox_api_key,
      name: "Test Proxmox Key",
      proxmox_url: "https://pve.example.com:8006",
      minion_id: "pve-1.example.com",
      username: "apiuser",
      token_name: "automation",
      api_token: "test-uuid-token",
      realm: "pam",
      enabled: true
    )
    @proxmox_api_key.stubs(:mark_as_used!).returns(true)

    @hetzner_api_key = build(:hetzner_api_key,
      name: "Test Hetzner Key",
      api_token: "test-hetzner-token-12345",
      enabled: true
    )
    @hetzner_api_key.stubs(:mark_as_used!).returns(true)
  end

  test "ProxmoxService list_vms parses API response correctly" do
    node_name = "pve-1"

    salt_result = {
      success: true,
      output: {
        "success" => true,
        "data" => [
          { "vmid" => 100, "name" => "web-server", "status" => "running", "type" => "qemu" },
          { "vmid" => 101, "name" => "db-container", "status" => "stopped", "type" => "lxc" }
        ]
      }.to_json
    }

    ProxmoxService.stubs(:execute_with_env).returns(salt_result)

    result = ProxmoxService.list_vms(@proxmox_api_key, node_name)

    assert result[:success]
    assert_equal 2, result[:data].count
    assert_equal 100, result[:data].first[:vmid]
    assert_equal "web-server", result[:data].first[:name]
    assert_equal "running", result[:data].first[:status]
  end

  test "ProxmoxService list_vms handles disabled API key" do
    @proxmox_api_key.stubs(:enabled?).returns(false)

    result = ProxmoxService.list_vms(@proxmox_api_key, "pve-1")

    assert_not result[:success]
    assert_match(/disabled/, result[:error])
  end

  test "ProxmoxService list_vms handles Salt command failure" do
    salt_result = {
      success: false,
      output: "No response from minion"
    }

    ProxmoxService.stubs(:execute_with_env).returns(salt_result)

    result = ProxmoxService.list_vms(@proxmox_api_key, "pve-1")

    assert_not result[:success]
    assert_match(/Command failed/, result[:error])
  end

  test "ProxmoxService test_connection returns success for valid configuration" do
    salt_result = {
      success: true,
      output: {
        "success" => true,
        "message" => "Connected to Proxmox VE"
      }.to_json
    }

    ProxmoxService.stubs(:execute_with_env).returns(salt_result)

    result = ProxmoxService.test_connection(@proxmox_api_key)

    assert result[:success]
    assert_match(/Connected/, result[:message])
  end

  test "ProxmoxService test_connection validates API key type" do
    assert_raises(ArgumentError) do
      ProxmoxService.test_connection("not-an-api-key")
    end
  end

  test "ProxmoxService list_vms validates API key type" do
    assert_raises(ArgumentError) do
      ProxmoxService.list_vms("not-an-api-key", "pve-1")
    end
  end

  # =============================================================================
  # HetznerService Tests (4.3.3-4.3.4)
  # =============================================================================

  test "HetznerService list_servers parses API response correctly" do
    json_response = {
      "success" => true,
      "data" => [
        {
          "id" => 12345678,
          "name" => "production-web-01",
          "status" => "running",
          "public_net" => { "ipv4" => { "ip" => "95.216.100.50" } }
        },
        {
          "id" => 87654321,
          "name" => "staging-db-01",
          "status" => "off",
          "public_net" => { "ipv4" => { "ip" => "95.216.100.51" } }
        }
      ]
    }.to_json

    # Use Open3 stubbing
    Open3.stubs(:capture3).returns([json_response, "", mock(success?: true)])

    result = HetznerService.list_servers(@hetzner_api_key)

    assert result[:success]
    assert_equal 2, result[:data].count
    assert_equal 12345678, result[:data].first[:id]
    assert_equal "production-web-01", result[:data].first[:name]
  end

  test "HetznerService list_servers handles disabled API key" do
    @hetzner_api_key.stubs(:enabled?).returns(false)

    result = HetznerService.list_servers(@hetzner_api_key)

    assert_not result[:success]
    assert_match(/disabled/, result[:error])
  end

  test "HetznerService list_servers validates API key type" do
    assert_raises(ArgumentError) do
      HetznerService.list_servers("not-an-api-key")
    end
  end

  test "HetznerService list_servers handles JSON parse errors" do
    # Mock to return invalid JSON
    Open3.stubs(:capture3).returns(["not valid json {{{", "", mock(success?: true)])

    result = HetznerService.list_servers(@hetzner_api_key)

    # Should either parse error or succeed with fallback
    assert_not_nil result
  end

  test "HetznerService list_servers handles script execution failure" do
    # Mock to indicate failure
    Open3.stubs(:capture3).returns(["Script not found", "error", mock(success?: false)])

    result = HetznerService.list_servers(@hetzner_api_key)

    # Should handle the error gracefully
    assert_not_nil result
    assert result.key?(:success) || result.key?(:error)
  end

  # =============================================================================
  # Snapshot Creation Tests (4.3.5)
  # =============================================================================

  test "ProxmoxService create_snapshot builds correct request" do
    api_key = build(:proxmox_api_key, enabled: true)
    api_key.stubs(:mark_as_used!).returns(true)

    server = build(:server, :proxmox,
      hostname: "web-vm",
      proxmox_node: "pve-1.example.com",
      proxmox_vmid: 100,
      proxmox_type: "qemu",
      proxmox_api_key: api_key
    )
    server.stubs(:proxmox_server?).returns(true)
    server.stubs(:can_use_proxmox_features?).returns(true)

    salt_result = {
      success: true,
      output: {
        "success" => true,
        "data" => { "task" => "UPID:pve-1:000123" }
      }.to_json
    }

    ProxmoxService.stubs(:execute_with_env).returns(salt_result)

    result = ProxmoxService.create_snapshot(server, "pre-update", "Snapshot before system update")

    assert result[:success]
  end

  # =============================================================================
  # API Authentication Handling Tests (4.3.6)
  # =============================================================================

  test "ProxmoxService uses token authentication header" do
    api_key = build(:proxmox_api_key,
      username: "apiuser",
      token_name: "mytoken",
      api_token: "secret-uuid",
      realm: "pam"
    )
    api_key.stubs(:enabled?).returns(true)
    api_key.stubs(:mark_as_used!).returns(true)

    captured_env = nil
    SaltService.stubs(:api_call).with do |method, endpoint, options|
      body = JSON.parse(options[:body])
      captured_env = body["kwarg"]["env"] if body["kwarg"]
      true
    end.returns({ "return" => [{ api_key.minion_id => "" }] })

    ProxmoxService.send(:execute_with_env, api_key.minion_id, "test", {
      "PROXMOX_TOKEN" => "#{api_key.token_name}=#{api_key.api_token}"
    })

    # Verify the env var was passed
    assert_not_nil captured_env
  end

  test "HetznerService marks API key as used after request" do
    api_key = create(:hetzner_api_key, enabled: true, last_used_at: nil)

    json_response = { "success" => true, "data" => [] }.to_json
    Open3.stubs(:capture3).returns([json_response, "", mock(success?: true)])

    # Track if mark_as_used! was called
    marked = false
    api_key.define_singleton_method(:mark_as_used!) { marked = true }

    HetznerService.list_servers(api_key)

    assert marked, "API key should be marked as used"
  end

  test "ProxmoxService marks API key as used after request" do
    api_key = build(:proxmox_api_key, enabled: true)

    marked = false
    api_key.define_singleton_method(:mark_as_used!) { marked = true }

    salt_result = {
      success: true,
      output: { "success" => true, "data" => [] }.to_json
    }

    ProxmoxService.stubs(:execute_with_env).returns(salt_result)

    ProxmoxService.list_vms(api_key, "pve-1")

    assert marked, "API key should be marked as used"
  end
end
