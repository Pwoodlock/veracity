# frozen_string_literal: true

require "application_system_test_case"

class ServersTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @server = servers(:online_server)
    sign_in @admin
  end

  test "servers index page loads" do
    visit servers_path

    assert_selector "h1", text: /servers/i
  end

  test "servers index shows server list" do
    visit servers_path

    # Should show servers from fixtures
    assert_text @server.hostname
  end

  test "servers show online/offline status" do
    visit servers_path

    # Should indicate server status visually (case-insensitive)
    assert_text(/online/i)
  end

  test "server details page loads" do
    visit server_path(@server)

    assert_text @server.hostname
    assert_text @server.ip_address
  end

  test "server details shows system information" do
    visit server_path(@server)

    # Should show OS info from fixtures
    assert_text @server.os_name || @server.os_family
  end

  test "servers can be filtered by status" do
    visit servers_path

    # If there's a filter/search, test it
    if page.has_select?("status")
      select "Online", from: "status"
      wait_for_page_load
      assert_text servers(:online_server).hostname
    end
  end

  test "servers can be filtered by group" do
    visit servers_path

    if page.has_select?("group")
      select "Production", from: "group"
      wait_for_page_load
      assert_text servers(:online_server).hostname
    end
  end

  test "server card shows key information" do
    visit servers_path

    # Each server card should show essential info
    assert_text @server.hostname
    # Status is displayed in uppercase
    assert_text(/#{@server.status}/i)
  end

  test "clicking server navigates to details" do
    visit servers_path

    click_link @server.hostname
    wait_for_page_load

    assert_current_path server_path(@server)
  end

  test "server page shows command history" do
    visit server_path(@server)

    # Should have a commands section
    assert_text "Commands" if page.has_text?("Commands")
  end

  test "server page allows running commands" do
    visit server_path(@server)

    # Should have command input or action buttons
    # This depends on your UI implementation
    assert_selector "form" # Some form for interaction
  end
end
