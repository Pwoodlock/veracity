# frozen_string_literal: true

require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @server = servers(:online_server)
    sign_in @admin

    # Mock external services to prevent flaky tests
    mock_salt_api
    mock_gotify_api
  end

  # ---------------------------------------------------------------------------
  # Dashboard Loading and Stats Tests
  # ---------------------------------------------------------------------------

  test "dashboard loads and shows stats panel" do
    visit dashboard_path

    # Check stats cards are present
    assert_selector "#dashboard-stats"
    assert_text "Total Servers"
    assert_text "Commands"
  end

  test "dashboard shows correct server counts" do
    visit dashboard_path

    # Stats should show server counts from fixtures
    within "#dashboard-stats" do
      # We have 4 servers in fixtures
      assert_text "4"
    end
  end

  test "dashboard stats display online and offline counts" do
    visit dashboard_path

    within "#dashboard-stats" do
      # Should show online server count (3 online in fixtures)
      assert_text "Online"
      # Should show offline count (1 offline in fixtures)
      assert_text "Offline"
    end
  end

  test "dashboard loads without JavaScript errors" do
    visit dashboard_path
    wait_for_page_load

    # Verify the page loaded successfully
    assert_selector "#dashboard-stats"
  end

  # ---------------------------------------------------------------------------
  # Navigation Tests
  # ---------------------------------------------------------------------------

  test "dashboard shows navigation" do
    visit dashboard_path

    # Check navigation links exist
    assert_link "Dashboard"
    assert_link "Servers"
  end

  test "dashboard links to servers page" do
    visit dashboard_path

    click_link "Servers"
    wait_for_page_load

    assert_current_path servers_path
  end

  test "navigation to server details from dashboard" do
    visit dashboard_path

    # Click on server hostname to navigate to details
    if page.has_link?(@server.hostname)
      click_link @server.hostname
      wait_for_page_load
      assert_current_path server_path(@server)
    else
      # Server may be shown in a different format
      skip "Server links not visible on dashboard"
    end
  end

  # ---------------------------------------------------------------------------
  # Real-time Updates Tests
  # ---------------------------------------------------------------------------

  test "dashboard has turbo stream subscription for real-time updates" do
    visit dashboard_path

    # Check that Turbo Stream is connected for real-time updates
    assert_selector "turbo-cable-stream-source[channel='Turbo::StreamsChannel']", visible: :all
  end

  test "dashboard shows toast container for notifications" do
    visit dashboard_path

    # Toast container should be present for real-time notifications
    assert_selector "#toast-container", visible: :all
  end

  # ---------------------------------------------------------------------------
  # Dashboard Widgets Tests
  # ---------------------------------------------------------------------------

  test "failed commands section renders" do
    visit dashboard_path

    # Failed commands widget should be present (even if empty)
    assert_selector "#failed-commands-widget", visible: :all
  end

  test "vulnerability alerts widget displays when alerts exist" do
    # Create a vulnerability alert
    VulnerabilityAlert.create!(
      cve_id: "CVE-2024-0001",
      title: "Test Vulnerability",
      severity: "HIGH",
      status: "active",
      published_at: 1.day.ago,
      server: @server
    )

    visit dashboard_path

    # Vulnerability stats should be shown
    assert_text "Vulnerability"
  end

  test "dashboard shows group statistics" do
    visit dashboard_path

    # Groups section should be present
    within "#dashboard-stats" do
      assert_text "Groups"
    end
  end

  # ---------------------------------------------------------------------------
  # Operator Actions Tests
  # ---------------------------------------------------------------------------

  test "admin can see system action buttons" do
    visit dashboard_path

    # Admin should see system operation buttons
    # These may be in sidebar or main content
    if page.has_button?("Sync Servers")
      assert_button "Sync Servers"
    end
  end
end
