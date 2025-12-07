# frozen_string_literal: true

require "test_helper"

class ServerControllerIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:user, :admin)
    @operator = create(:user, :operator)
    @viewer = create(:user, :viewer)

    @production_group = create(:group, :production)
    @staging_group = create(:group, :staging)

    @online_server = create(:server, :online, group: @production_group)
    @offline_server = create(:server, :offline, group: @production_group)
    @staging_server = create(:server, :online, group: @staging_group)
    @ungrouped_server = create(:server, :online, group: nil)

    # Mock Salt API to avoid real API calls
    mock_salt_api
  end

  # =============================================================================
  # Authentication Tests
  # =============================================================================

  test "unauthenticated users are redirected to login" do
    get servers_path
    assert_redirected_to new_user_session_path
  end

  test "all roles can access servers index" do
    [@admin, @operator, @viewer].each do |user|
      sign_in user
      get servers_path
      assert_response :success, "#{user.role} should be able to access servers index"
      delete destroy_user_session_path
    end
  end

  # =============================================================================
  # Server Listing with Filtering
  # =============================================================================

  test "index displays all servers" do
    sign_in @admin
    get servers_path
    assert_response :success

    assert_match @online_server.hostname, response.body
    assert_match @offline_server.hostname, response.body
    assert_match @staging_server.hostname, response.body
  end

  test "index filters servers by status" do
    sign_in @admin
    get servers_path, params: { status: "online" }
    assert_response :success

    assert_match @online_server.hostname, response.body
    # Offline server should not appear
    assert_no_match(/#{@offline_server.hostname}/, response.body)
  end

  test "index filters servers by group_id" do
    sign_in @admin
    get servers_path, params: { group_id: @production_group.id }
    assert_response :success

    assert_match @online_server.hostname, response.body
    assert_match @offline_server.hostname, response.body
    # Staging server should not appear
    assert_no_match(/#{@staging_server.hostname}/, response.body)
  end

  test "index filters ungrouped servers" do
    sign_in @admin
    get servers_path, params: { group_id: "ungrouped" }
    assert_response :success

    assert_match @ungrouped_server.hostname, response.body
    assert_no_match(/#{@online_server.hostname}/, response.body)
  end

  test "index supports search by hostname" do
    sign_in @admin
    get servers_path, params: { search: @online_server.hostname[0..5] }
    assert_response :success

    assert_match @online_server.hostname, response.body
  end

  test "index supports search by IP address" do
    sign_in @admin
    get servers_path, params: { search: @online_server.ip_address }
    assert_response :success

    assert_match @online_server.hostname, response.body
  end

  test "index supports search by minion_id" do
    sign_in @admin
    get servers_path, params: { search: @online_server.minion_id[0..10] }
    assert_response :success

    assert_match @online_server.hostname, response.body
  end

  # =============================================================================
  # Server Status Updates
  # =============================================================================

  test "admin can sync server data" do
    sign_in @admin

    # Mock Salt API responses for sync
    SaltService.stubs(:ping_minion).returns({
      "return" => [{ @online_server.minion_id => true }]
    })
    SaltService.stubs(:sync_minion_grains).returns({
      "os" => "Ubuntu",
      "osrelease" => "24.04",
      "num_cpus" => 8,
      "mem_total" => 16384
    })

    post sync_server_path(@online_server)

    assert_redirected_to server_path(@online_server)
    follow_redirect!
    assert_match "Server data synced successfully", response.body
  end

  test "operator can sync server data" do
    sign_in @operator

    SaltService.stubs(:ping_minion).returns({
      "return" => [{ @online_server.minion_id => true }]
    })
    SaltService.stubs(:sync_minion_grains).returns({
      "os" => "Ubuntu",
      "osrelease" => "24.04"
    })

    post sync_server_path(@online_server)

    assert_redirected_to server_path(@online_server)
  end

  test "sync updates server status based on ping result" do
    sign_in @admin

    # Simulate offline server ping failure
    SaltService.stubs(:ping_minion).returns({
      "return" => [{ @online_server.minion_id => false }]
    })

    post sync_server_path(@online_server)

    @online_server.reload
    assert_equal "offline", @online_server.status
  end

  # =============================================================================
  # Group Assignment Operations
  # =============================================================================

  test "admin can update server group assignment" do
    sign_in @admin

    patch server_path(@ungrouped_server), params: {
      server: {
        group_id: @production_group.id
      }
    }

    assert_redirected_to server_path(@ungrouped_server)
    @ungrouped_server.reload
    assert_equal @production_group.id, @ungrouped_server.group_id
  end

  test "operator can update server group assignment" do
    sign_in @operator

    patch server_path(@ungrouped_server), params: {
      server: {
        group_id: @staging_group.id
      }
    }

    assert_redirected_to server_path(@ungrouped_server)
    @ungrouped_server.reload
    assert_equal @staging_group.id, @ungrouped_server.group_id
  end

  test "admin can remove server from group" do
    sign_in @admin
    server_in_group = create(:server, group: @production_group)

    patch server_path(server_in_group), params: {
      server: {
        group_id: ""
      }
    }

    assert_redirected_to server_path(server_in_group)
    server_in_group.reload
    assert_nil server_in_group.group_id
  end

  test "admin can update server environment" do
    sign_in @admin

    patch server_path(@online_server), params: {
      server: {
        environment: "staging"
      }
    }

    assert_redirected_to server_path(@online_server)
    @online_server.reload
    assert_equal "staging", @online_server.environment
  end

  # =============================================================================
  # Authorization Checks
  # =============================================================================

  test "viewer cannot edit server" do
    sign_in @viewer

    get edit_server_path(@online_server)

    # Viewer should be redirected due to authorization
    assert_redirected_to root_path
  end

  test "viewer cannot update server" do
    sign_in @viewer

    patch server_path(@online_server), params: {
      server: {
        group_id: @staging_group.id
      }
    }

    assert_redirected_to root_path
    @online_server.reload
    assert_equal @production_group.id, @online_server.group_id
  end

  test "viewer cannot delete server" do
    sign_in @viewer

    assert_no_difference("Server.count") do
      delete server_path(@online_server)
    end

    assert_redirected_to root_path
  end

  test "only admin can delete server" do
    sign_in @admin
    server_to_delete = create(:server)

    SaltService.stubs(:remove_minion_completely).returns({
      success: true,
      message: "Minion removed successfully"
    })

    assert_difference("Server.count", -1) do
      delete server_path(server_to_delete)
    end

    assert_redirected_to servers_path
  end

  test "operator cannot delete server" do
    sign_in @operator

    assert_no_difference("Server.count") do
      delete server_path(@online_server)
    end

    assert_redirected_to root_path
  end

  # =============================================================================
  # Server Detail View
  # =============================================================================

  test "show displays server details" do
    sign_in @admin

    get server_path(@online_server)
    assert_response :success

    assert_match @online_server.hostname, response.body
    assert_match @online_server.ip_address, response.body
    assert_match @online_server.minion_id, response.body
  end

  test "show displays recent commands" do
    sign_in @admin
    command = create(:command, :completed, server: @online_server)

    get server_path(@online_server)
    assert_response :success
  end
end
