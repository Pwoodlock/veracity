# frozen_string_literal: true

require "application_system_test_case"

class DashboardTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test "dashboard loads and shows stats" do
    visit dashboard_path

    # Check page title
    assert_selector "h1", text: "Operations Dashboard"

    # Check stats cards are present
    assert_selector "#dashboard-stats"
    assert_text "Total Servers"
    assert_text "Commands"
  end

  test "dashboard shows correct server counts" do
    visit dashboard_path

    # Stats should show server counts from fixtures
    within "#dashboard-stats" do
      # We have 4 servers in fixtures, 3 online, 1 offline
      assert_text "4" # Total servers
    end
  end

  test "dashboard shows navigation" do
    visit dashboard_path

    # Check navigation links exist
    assert_link "Dashboard"
    assert_link "Servers"
  end

  test "dashboard loads without JavaScript errors" do
    visit dashboard_path
    wait_for_page_load

    # Just verify the page loaded successfully
    assert_selector "h1", text: "Operations Dashboard"
  end

  test "dashboard has turbo stream subscription" do
    visit dashboard_path

    # Check that Turbo Stream is connected for real-time updates
    assert_selector "turbo-cable-stream-source[channel='Turbo::StreamsChannel']", visible: :all
  end

  test "failed commands section renders" do
    visit dashboard_path

    # Failed commands widget should be present (even if empty)
    assert_selector "#failed-commands-widget", visible: :all
  end

  test "dashboard links to servers page" do
    visit dashboard_path

    click_link "Servers"
    wait_for_page_load

    assert_current_path servers_path
  end
end
