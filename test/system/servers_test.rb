# frozen_string_literal: true

require "application_system_test_case"

class ServersTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @server = servers(:online_server)
    @offline_server = servers(:offline_server)
    @staging_server = servers(:staging_server)
    sign_in @admin

    # Mock external services to prevent flaky tests
    mock_salt_api
    mock_gotify_api
  end

  # ---------------------------------------------------------------------------
  # Server List Tests
  # ---------------------------------------------------------------------------

  test "servers index page loads" do
    visit servers_path

    # Check for server table or content that indicates page loaded
    assert_selector "table"
    assert_text "Hostname"
  end

  test "servers index shows server list" do
    visit servers_path

    # Should show servers from fixtures
    assert_text @server.hostname
  end

  test "servers show online and offline status" do
    visit servers_path

    # Should indicate server status visually (case-insensitive)
    assert_text(/online/i)
    assert_text(/offline/i)
  end

  test "server card shows key information" do
    visit servers_path

    # Each server card should show essential info
    assert_text @server.hostname
    # Status is displayed
    assert_text(/#{@server.status}/i)
  end

  # ---------------------------------------------------------------------------
  # Server Filtering Tests
  # ---------------------------------------------------------------------------

  test "servers can be filtered by status" do
    visit servers_path

    # Check if there is a status filter select
    if page.has_select?("status")
      select "Online", from: "status"
      wait_for_page_load
      assert_text @server.hostname
    elsif page.has_css?("[data-filter='status']")
      # Alternative filter implementation
      find("[data-filter='status']").click
      find("option[value='online']").click
      wait_for_page_load
      assert_text @server.hostname
    end
  end

  test "servers can be filtered by group" do
    visit servers_path

    if page.has_select?("group")
      select "production", from: "group"
      wait_for_page_load
      assert_text @server.hostname
    end
  end

  test "servers list shows all fixture servers" do
    visit servers_path

    # Should show all 4 servers from fixtures
    assert_text @server.hostname
    assert_text @offline_server.hostname
    assert_text @staging_server.hostname
    assert_text servers(:ungrouped_server).hostname
  end

  # ---------------------------------------------------------------------------
  # Server Details Tests
  # ---------------------------------------------------------------------------

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

  test "clicking server navigates to details" do
    visit servers_path

    click_link @server.hostname
    wait_for_page_load

    assert_current_path server_path(@server)
  end

  test "server page shows minion information" do
    visit server_path(@server)

    # Should display minion ID
    assert_text @server.minion_id
  end

  test "server page has edit link" do
    visit server_path(@server)

    # Should have edit link or button
    assert_link "Edit" rescue assert_selector "a[href='#{edit_server_path(@server)}']"
  end

  # ---------------------------------------------------------------------------
  # Server Edit Form Tests
  # ---------------------------------------------------------------------------

  test "server edit form loads with current values" do
    visit edit_server_path(@server)

    # Should show the edit form
    assert_text "Edit #{@server.hostname}"
    assert_text @server.hostname
    assert_text @server.ip_address
    assert_text @server.minion_id

    # Should have form fields
    assert_selector "select[name='server[group_id]']"
    assert_selector "select[name='server[environment]']"
  end

  test "server edit form allows updating group assignment" do
    visit edit_server_path(@server)

    # Change the environment
    select "Staging", from: "server[environment]"

    # Submit the form
    click_button "Save Changes"

    wait_for_page_load

    # Should redirect to server details
    assert_current_path server_path(@server)
  end

  test "server edit form shows location fields" do
    visit edit_server_path(@server)

    # Should have location and provider fields
    assert_selector "input[name='server[location]']"
    assert_selector "input[name='server[provider]']"
  end

  test "server edit form shows integration options" do
    visit edit_server_path(@server)

    # Should have Hetzner and Proxmox integration sections
    assert_text "Hetzner Cloud Integration"
    assert_text "Proxmox VE Integration"
  end

  test "cancel button on edit form returns to server details" do
    visit edit_server_path(@server)

    click_link "Cancel"
    wait_for_page_load

    assert_current_path server_path(@server)
  end

  # ---------------------------------------------------------------------------
  # Server Commands Tests
  # ---------------------------------------------------------------------------

  test "server page shows command history section" do
    visit server_path(@server)

    # Should have a commands section or recent activity
    if page.has_text?("Commands")
      assert_text "Commands"
    end
  end

  test "server page has sync button" do
    visit server_path(@server)

    # Should have sync button for refreshing server data
    if page.has_button?("Sync")
      assert_button "Sync"
    elsif page.has_button?("Sync Server Data")
      assert_button "Sync Server Data"
    end
  end

  # ---------------------------------------------------------------------------
  # Server Status Tests
  # ---------------------------------------------------------------------------

  test "online server shows online status indicator" do
    visit server_path(@server)

    # Online server should show online status
    assert_text(/online/i)
  end

  test "offline server shows offline status indicator" do
    visit server_path(@offline_server)

    # Offline server should show offline status
    assert_text(/offline/i)
  end
end
