# frozen_string_literal: true

require "test_helper"

class ServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    @server = servers(:online_server)
  end

  test "should redirect to login when not authenticated" do
    get servers_path
    assert_redirected_to new_user_session_path
  end

  test "should get index" do
    sign_in @admin
    get servers_path
    assert_response :success
  end

  test "index shows servers" do
    sign_in @admin
    get servers_path

    assert_select "a", text: @server.hostname
  end

  test "should show server" do
    sign_in @admin
    get server_path(@server)
    assert_response :success
  end

  test "show displays server hostname" do
    sign_in @admin
    get server_path(@server)

    assert_match @server.hostname, response.body
  end

  test "show displays server IP address" do
    sign_in @admin
    get server_path(@server)

    assert_match @server.ip_address, response.body
  end

  test "should get edit" do
    sign_in @admin
    get edit_server_path(@server)
    assert_response :success
  end

  test "should update server" do
    sign_in @admin

    patch server_path(@server), params: {
      server: {
        environment: "staging"
      }
    }

    assert_redirected_to server_path(@server)
  end

  test "index can filter by status" do
    sign_in @admin
    get servers_path, params: { status: "online" }
    assert_response :success
  end

  test "index can filter by group" do
    sign_in @admin
    group = groups(:production)
    get servers_path, params: { group_id: group.id }
    assert_response :success
  end

  test "should destroy server" do
    sign_in @admin
    server_to_delete = create_test_server

    assert_difference("Server.count", -1) do
      delete server_path(server_to_delete)
    end

    assert_redirected_to servers_path
  end
end
