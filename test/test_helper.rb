# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"
require "webmock/minitest"

# Code coverage
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/vendor/"

  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Channels", "app/channels"
  add_group "Helpers", "app/helpers"
end

# =============================================================================
# Shared Test Helper Methods Module
# =============================================================================
# These helpers are shared between unit tests and integration tests
module TestHelperMethods
  # Helper to create a test server
  def create_test_server(attributes = {})
    Server.create!({
      hostname: "test-server-#{SecureRandom.hex(4)}",
      minion_id: "test-minion-#{SecureRandom.hex(4)}",
      ip_address: "192.168.1.#{rand(1..254)}",
      status: "online"
    }.merge(attributes))
  end

  # Helper to create a test command
  def create_test_command(server, attributes = {})
    Command.create!({
      server: server,
      command_type: "shell",
      command: "cmd.run",
      arguments: { args: ["echo test"] },
      status: "pending",
      started_at: Time.current
    }.merge(attributes))
  end

  # =============================================================================
  # Mock External API Helpers
  # =============================================================================

  # Mock SaltService API for testing Salt operations
  # @param options [Hash] Configuration options
  #   - :ping_response [Hash] Response for ping_minion
  #   - :grains_response [Hash] Response for get_grains
  #   - :command_response [Hash] Response for run_command
  #   - :keys_response [Hash] Response for list_keys
  # @return [void]
  def mock_salt_api(options = {})
    default_ping = { "return" => [{ "minion-id" => true }] }
    default_grains = {
      "return" => [{
        "minion-id" => {
          "os" => "Ubuntu",
          "os_family" => "Debian",
          "osrelease" => "22.04",
          "ip4_interfaces" => { "eth0" => ["192.168.1.10"] },
          "mem_total" => 8192,
          "num_cpus" => 4
        }
      }]
    }
    default_command = {
      success: true,
      output: "Command executed successfully"
    }
    default_keys = {
      "return" => [{
        "data" => {
          "return" => {
            "minions" => ["minion-1", "minion-2"],
            "minions_pre" => [],
            "minions_rejected" => [],
            "minions_denied" => []
          }
        }
      }]
    }

    SaltService.stubs(:ping_minion).returns(options[:ping_response] || default_ping)
    SaltService.stubs(:get_grains).returns(options[:grains_response] || default_grains)
    SaltService.stubs(:run_command).returns(options[:command_response] || default_command)
    SaltService.stubs(:run_command_raw).returns(options[:command_response] || { "return" => [{}] })
    SaltService.stubs(:list_keys).returns(options[:keys_response] || default_keys)
    SaltService.stubs(:accept_key).returns({ "return" => [{ "data" => { "success" => true } }] })
    SaltService.stubs(:reject_key).returns({ "return" => [{ "data" => { "success" => true } }] })
    SaltService.stubs(:delete_key).returns({ "return" => [{ "data" => { "success" => true } }] })
    SaltService.stubs(:apply_state).returns({ success: true, output: "State applied" })
    SaltService.stubs(:write_minion_pillar).returns({ success: true })
    SaltService.stubs(:delete_minion_pillar).returns({ success: true })
    SaltService.stubs(:refresh_pillar).returns({ success: true })
    SaltService.stubs(:sync_minion_grains).returns({
      "os" => "Ubuntu",
      "osrelease" => "22.04",
      "num_cpus" => 4,
      "mem_total" => 8192
    })
    SaltService.stubs(:remove_minion_completely).returns({
      success: true,
      message: "Minion removed successfully"
    })
  end

  # Mock GotifyNotificationService for testing notifications
  # @param options [Hash] Configuration options
  #   - :enabled [Boolean] Whether Gotify is enabled (default: true)
  #   - :send_response [NotificationHistory, nil] Response for send_notification
  #   - :test_response [Hash] Response for test_connection
  # @return [void]
  def mock_gotify_api(options = {})
    enabled = options.fetch(:enabled, true)

    GotifyNotificationService.stubs(:enabled?).returns(enabled)

    if enabled
      notification_history = options[:send_response] || NotificationHistory.new(
        notification_type: "test",
        title: "Test",
        message: "Test message",
        status: "sent"
      )
      GotifyNotificationService.stubs(:send_notification).returns(notification_history)
      GotifyNotificationService.stubs(:send_alert).returns(notification_history)
      GotifyNotificationService.stubs(:notify_server_event).returns(notification_history)
      GotifyNotificationService.stubs(:notify_cve_alert).returns(notification_history)
    else
      GotifyNotificationService.stubs(:send_notification).returns(nil)
      GotifyNotificationService.stubs(:send_alert).returns(nil)
      GotifyNotificationService.stubs(:notify_server_event).returns(nil)
      GotifyNotificationService.stubs(:notify_cve_alert).returns(nil)
    end

    test_response = options[:test_response] || {
      success: true,
      message: "Connection successful"
    }
    GotifyNotificationService.stubs(:test_connection).returns(test_response)
  end

  # Mock external cloud APIs (Proxmox and Hetzner)
  # @param options [Hash] Configuration options
  #   - :proxmox [Hash] ProxmoxService mock options
  #     - :list_vms [Hash] Response for list_vms
  #     - :test_connection [Hash] Response for test_connection
  #     - :get_vm_status [Hash] Response for get_vm_status
  #   - :hetzner [Hash] HetznerService mock options
  #     - :list_servers [Hash] Response for list_servers
  # @return [void]
  def mock_external_apis(options = {})
    proxmox_opts = options[:proxmox] || {}
    hetzner_opts = options[:hetzner] || {}

    # Default Proxmox responses
    default_proxmox_vms = {
      success: true,
      data: [
        { vmid: 100, name: "vm-01", status: "running", type: "qemu" },
        { vmid: 101, name: "container-01", status: "stopped", type: "lxc" }
      ],
      timestamp: Time.current.iso8601
    }
    default_proxmox_connection = {
      success: true,
      message: "Connected to Proxmox VE",
      timestamp: Time.current.iso8601
    }
    default_proxmox_status = {
      success: true,
      data: { vmid: 100, status: "running", uptime: 3600 },
      timestamp: Time.current.iso8601
    }

    ProxmoxService.stubs(:list_vms).returns(proxmox_opts[:list_vms] || default_proxmox_vms)
    ProxmoxService.stubs(:test_connection).returns(proxmox_opts[:test_connection] || default_proxmox_connection)
    ProxmoxService.stubs(:get_vm_status).returns(proxmox_opts[:get_vm_status] || default_proxmox_status)
    ProxmoxService.stubs(:start_vm).returns({ success: true, message: "VM started" })
    ProxmoxService.stubs(:stop_vm).returns({ success: true, message: "VM stopped" })
    ProxmoxService.stubs(:list_snapshots).returns({ success: true, data: [] })

    # Default Hetzner responses
    default_hetzner_servers = {
      success: true,
      data: [
        { id: 1, name: "server-01", status: "running", public_net: { ipv4: { ip: "1.2.3.4" } } },
        { id: 2, name: "server-02", status: "off", public_net: { ipv4: { ip: "5.6.7.8" } } }
      ],
      timestamp: Time.current.iso8601
    }

    HetznerService.stubs(:list_servers).returns(hetzner_opts[:list_servers] || default_hetzner_servers)
    HetznerService.stubs(:get_server_status).returns({ success: true, data: { status: "running" } })
    HetznerService.stubs(:start_server).returns({ success: true, message: "Server started" })
    HetznerService.stubs(:stop_server).returns({ success: true, message: "Server stopped" })
  end

  # Enable Rack::Attack for rate limit testing
  # By default, Rack::Attack is disabled in test environment
  # @yield Block to execute with Rack::Attack enabled
  # @return [void]
  def with_rack_attack_enabled
    original_enabled = Rack::Attack.enabled
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

    yield
  ensure
    Rack::Attack.enabled = original_enabled
    Rack::Attack.reset!
  end

  # Reset Rack::Attack throttle counters
  # Useful between tests that check rate limiting
  # @return [void]
  def reset_rack_attack!
    Rack::Attack.reset! if defined?(Rack::Attack)
  end

  # Stub HTTP requests to external APIs
  # Uses WebMock to prevent actual HTTP calls
  # @param url_pattern [String, Regexp] URL pattern to stub
  # @param response [Hash] Response options
  #   - :status [Integer] HTTP status code (default: 200)
  #   - :body [String, Hash] Response body
  #   - :headers [Hash] Response headers
  # @return [WebMock::RequestStub]
  def stub_external_http(url_pattern, response = {})
    status = response[:status] || 200
    body = response[:body].is_a?(Hash) ? response[:body].to_json : response[:body]
    headers = { "Content-Type" => "application/json" }.merge(response[:headers] || {})

    stub_request(:any, url_pattern).to_return(
      status: status,
      body: body,
      headers: headers
    )
  end
end

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order
  fixtures :all

  # Include FactoryBot methods
  include FactoryBot::Syntax::Methods

  # Include ActionCable test helpers for broadcast assertions
  include ActionCable::TestHelper

  # Include shared test helper methods
  include TestHelperMethods

  # Helper to sign in a user for controller tests (non-Devise)
  def sign_in(user)
    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password123!"
      }
    }
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include FactoryBot::Syntax::Methods
  include ActionCable::TestHelper
  include TestHelperMethods
end

# ActionCable Channel tests configuration
class ActionCable::Channel::TestCase
  include FactoryBot::Syntax::Methods
end
