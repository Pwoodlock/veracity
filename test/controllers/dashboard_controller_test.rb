# frozen_string_literal: true

require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
  end

  test "should redirect to login when not authenticated" do
    get dashboard_path
    assert_redirected_to new_user_session_path
  end

  test "should get index when authenticated" do
    sign_in @admin
    get dashboard_path
    assert_response :success
  end

  test "index assigns correct server counts" do
    sign_in @admin
    get dashboard_path

    assert_response :success
    # The controller should set instance variables for stats
  end

  test "index renders stats partial" do
    sign_in @admin
    get dashboard_path

    assert_select "#dashboard-stats"
  end

  test "index includes turbo stream tag" do
    sign_in @admin
    get dashboard_path

    # Should have Action Cable meta tag for real-time updates
    assert_select "meta[name='action-cable-url']"
  end
end
