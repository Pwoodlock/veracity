# frozen_string_literal: true

require "test_helper"

# Integration tests for Dashboard data aggregation and stats calculation
# These tests verify that the dashboard controller correctly calculates
# server statistics, command history, and activity data
class DashboardIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  # ===========================================
  # Dashboard Stats Calculation Tests
  # ===========================================

  test "dashboard stats correctly count servers by status" do
    # Clean up existing servers from fixtures
    Server.destroy_all

    # Create servers with different statuses
    create(:server, :online)
    create(:server, :online)
    create(:server, :online)
    create(:server, :offline)
    create(:server, :offline)
    create(:server, status: "maintenance")

    get dashboard_path

    assert_response :success

    # Verify the controller assigns correct counts
    assert_equal 6, assigns(:total_servers)
    assert_equal 3, assigns(:online_servers)
    assert_equal 2, assigns(:offline_servers)
  end

  test "dashboard stats correctly count groups and ungrouped servers" do
    # Clean up existing data
    Server.destroy_all
    Group.destroy_all

    # Create groups with servers
    group1 = create(:group, name: "Production", slug: "production")
    group2 = create(:group, name: "Staging", slug: "staging")

    create(:server, :online, group: group1)
    create(:server, :online, group: group1)
    create(:server, :online, group: group2)
    create(:server, :online, group: nil) # ungrouped
    create(:server, :online, group: nil) # ungrouped

    get dashboard_path

    assert_response :success

    assert_equal 2, assigns(:total_groups)
    assert_equal 2, assigns(:groups_with_servers)
    assert_equal 2, assigns(:ungrouped_servers)
  end

  # ===========================================
  # Command History Aggregation Tests
  # ===========================================

  test "dashboard correctly aggregates command statistics for last 24 hours" do
    # Clean up existing data
    Command.destroy_all
    Server.destroy_all

    server = create(:server, :online)

    # Create commands within the last 24 hours
    create(:command, :completed, server: server, started_at: 2.hours.ago)
    create(:command, :completed, server: server, started_at: 4.hours.ago)
    create(:command, :completed, server: server, started_at: 6.hours.ago)
    create(:command, :failed, server: server, started_at: 3.hours.ago)
    create(:command, :timeout, server: server, started_at: 5.hours.ago)

    # Create command outside the 24 hour window (should not be counted)
    create(:command, :completed, server: server, started_at: 2.days.ago)

    get dashboard_path

    assert_response :success

    # 5 commands within 24 hours
    assert_equal 5, assigns(:commands_today)
    # 3 completed with exit_code 0 or nil
    assert_equal 3, assigns(:successful_commands)
    # 1 failed (timeout is not "failed" status)
    assert_equal 1, assigns(:failed_commands)
  end

  test "dashboard correctly fetches failed updates from last 7 days" do
    # Clean up existing data
    Command.destroy_all
    Server.destroy_all

    server = create(:server, :online)

    # Create failed commands within the last 7 days
    failed1 = create(:command, :failed, server: server, started_at: 1.day.ago)
    failed2 = create(:command, :timeout, server: server, started_at: 3.days.ago)
    failed3 = create(:command, :failed, server: server, started_at: 5.days.ago)

    # Create completed command (should not appear in failed_updates)
    create(:command, :completed, server: server, started_at: 2.days.ago)

    # Create old failed command (outside 7 day window)
    create(:command, :failed, server: server, started_at: 10.days.ago)

    get dashboard_path

    assert_response :success

    failed_updates = assigns(:failed_updates)
    assert_equal 3, failed_updates.count

    # Most recent first
    failed_ids = failed_updates.map(&:id)
    assert_includes failed_ids, failed1.id
    assert_includes failed_ids, failed2.id
    assert_includes failed_ids, failed3.id
  end

  # ===========================================
  # Server Status Chart Data Tests
  # ===========================================

  test "dashboard generates activity chart data for last 24 hours" do
    # Clean up existing data
    Command.destroy_all
    Server.destroy_all

    server = create(:server, :online)

    # Create commands at different hours
    create(:command, :completed, server: server, started_at: 1.hour.ago)
    create(:command, :completed, server: server, started_at: 1.hour.ago)
    create(:command, :completed, server: server, started_at: 3.hours.ago)
    create(:command, :completed, server: server, started_at: 5.hours.ago)

    get dashboard_path

    assert_response :success

    activity_data = assigns(:activity_chart_data)
    assert_kind_of Hash, activity_data

    # The data should have keys in HH:MM format
    activity_data.keys.each do |key|
      assert_match(/\d{2}:\d{2}/, key, "Activity chart key should be in HH:MM format")
    end

    # The total count across all hours should equal our commands
    total_count = activity_data.values.sum
    assert_equal 4, total_count
  end

  # ===========================================
  # Vulnerability Alerts Integration Tests
  # ===========================================

  test "dashboard correctly aggregates vulnerability alert statistics" do
    # Clean up existing data
    VulnerabilityAlert.destroy_all

    # Create alerts with different severities and statuses
    create(:vulnerability_alert, :critical, :new)
    create(:vulnerability_alert, :critical, :new, is_exploited: true)
    create(:vulnerability_alert, :high, :new)
    create(:vulnerability_alert, :high, :acknowledged)
    create(:vulnerability_alert, :medium, :new)
    create(:vulnerability_alert, :low, :new)
    create(:vulnerability_alert, :info, :new)

    # Create resolved alert (should not be counted in active)
    create(:vulnerability_alert, :critical, :patched)

    get dashboard_path

    assert_response :success

    stats = assigns(:vulnerability_stats)
    assert_kind_of Hash, stats

    # 7 active (not patched/ignored)
    assert_equal 7, stats[:total]
    assert_equal 2, stats[:critical]
    assert_equal 2, stats[:high]
    assert_equal 1, stats[:medium]
    assert_equal 2, stats[:low] # LOW and INFO are combined
    assert_equal 1, stats[:exploited]
  end

  test "dashboard fetches recent critical and high vulnerability alerts" do
    # Clean up existing data
    VulnerabilityAlert.destroy_all

    # Create alerts with different severities
    critical_alert = create(:vulnerability_alert, :critical, :new, published_at: 1.day.ago)
    high_alert = create(:vulnerability_alert, :high, :new, published_at: 2.days.ago)
    medium_alert = create(:vulnerability_alert, :medium, :new, published_at: 3.days.ago)

    # Create resolved critical alert (should not appear)
    create(:vulnerability_alert, :critical, :patched, published_at: 1.hour.ago)

    get dashboard_path

    assert_response :success

    recent_alerts = assigns(:recent_vulnerability_alerts)

    # Only critical and high, active alerts should be included
    assert_equal 2, recent_alerts.count
    alert_ids = recent_alerts.map(&:id)
    assert_includes alert_ids, critical_alert.id
    assert_includes alert_ids, high_alert.id
    refute_includes alert_ids, medium_alert.id
  end

  # ===========================================
  # Dashboard View Rendering Tests
  # ===========================================

  test "dashboard renders all required partials" do
    get dashboard_path

    assert_response :success

    # Verify stats section is rendered
    assert_select "#dashboard-stats"

    # Verify Action Cable meta tag is present for real-time updates
    assert_select "meta[name='action-cable-url']"
  end

  test "dashboard renders Turbo Stream subscription tag" do
    get dashboard_path

    assert_response :success

    # Verify turbo_stream_from "dashboard" is rendered
    assert_select "turbo-cable-stream-source[channel='Turbo::StreamsChannel']"
  end
end
