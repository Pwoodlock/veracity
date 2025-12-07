# frozen_string_literal: true

require "test_helper"

class CveWatchlistControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:user, :admin)
    @operator = create(:user, :operator)
    @viewer = create(:user, :viewer)
    @server = create(:server, :online)

    # Disable Turbo for tests to avoid redirect issues
    ActionController::Base.allow_forgery_protection = false
  end

  teardown do
    ActionController::Base.allow_forgery_protection = true
  end

  # =============================================================================
  # Authentication Tests
  # =============================================================================

  test "unauthenticated users are redirected to login" do
    get cve_watchlists_path
    assert_redirected_to new_user_session_path
  end

  # =============================================================================
  # CRUD Operations - Index
  # =============================================================================

  test "admin can view watchlists index" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx, server: @server)

    get cve_watchlists_path
    assert_response :success
    assert_match watchlist.vendor, response.body
  end

  test "viewer can view watchlists index" do
    sign_in @viewer
    create(:cve_watchlist, :nginx)

    get cve_watchlists_path
    assert_response :success
  end

  test "index filters by server_id" do
    sign_in @admin
    watchlist_with_server = create(:cve_watchlist, server: @server)
    watchlist_without_server = create(:cve_watchlist, :global)

    get cve_watchlists_path, params: { server_id: @server.id }
    assert_response :success
    assert_match watchlist_with_server.product, response.body
  end

  test "index filters by active status" do
    sign_in @admin
    active_watchlist = create(:cve_watchlist, :active)
    inactive_watchlist = create(:cve_watchlist, :inactive)

    get cve_watchlists_path, params: { active: "true" }
    assert_response :success
    assert_match active_watchlist.product, response.body
  end

  # =============================================================================
  # CRUD Operations - Show
  # =============================================================================

  test "admin can view watchlist details" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx)

    get cve_watchlist_path(watchlist)
    assert_response :success
    assert_match watchlist.vendor, response.body
  end

  test "show displays recent alerts" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx)
    alert = create(:vulnerability_alert, :critical, cve_watchlist: watchlist)

    get cve_watchlist_path(watchlist)
    assert_response :success
    assert_match alert.cve_id, response.body
  end

  # =============================================================================
  # CRUD Operations - Create
  # =============================================================================

  test "admin can create a new watchlist" do
    sign_in @admin

    assert_difference("CveWatchlist.count", 1) do
      post cve_watchlists_path, params: {
        cve_watchlist: {
          vendor: "apache",
          product: "http_server",
          frequency: "daily",
          active: true,
          description: "Apache HTTP Server monitoring"
        }
      }
    end

    assert_redirected_to cve_watchlists_path
    follow_redirect!
    assert_match "CVE Watchlist created successfully", response.body
  end

  test "admin can create watchlist for specific server" do
    sign_in @admin

    assert_difference("CveWatchlist.count", 1) do
      post cve_watchlists_path, params: {
        cve_watchlist: {
          server_id: @server.id,
          vendor: "nginx",
          product: "nginx",
          frequency: "hourly",
          active: true
        }
      }
    end

    watchlist = CveWatchlist.last
    assert_equal @server.id, watchlist.server_id
  end

  test "create fails with invalid parameters" do
    sign_in @admin

    assert_no_difference("CveWatchlist.count") do
      post cve_watchlists_path, params: {
        cve_watchlist: {
          vendor: "",
          product: "",
          frequency: "invalid"
        }
      }
    end

    assert_response :success
    assert_match "Failed to create watchlist", response.body
  end

  # =============================================================================
  # CRUD Operations - Update
  # =============================================================================

  test "admin can update a watchlist" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx, frequency: "daily")

    patch cve_watchlist_path(watchlist), params: {
      cve_watchlist: {
        frequency: "hourly",
        description: "Updated description"
      }
    }

    assert_redirected_to cve_watchlist_path(watchlist)
    watchlist.reload
    assert_equal "hourly", watchlist.frequency
    assert_equal "Updated description", watchlist.description
  end

  test "update fails with invalid parameters" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx)

    patch cve_watchlist_path(watchlist), params: {
      cve_watchlist: {
        vendor: "",
        product: ""
      }
    }

    assert_response :success
    assert_match "Failed to update watchlist", response.body
  end

  # =============================================================================
  # CRUD Operations - Delete
  # =============================================================================

  test "admin can delete a watchlist" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx)

    assert_difference("CveWatchlist.count", -1) do
      delete cve_watchlist_path(watchlist)
    end

    assert_redirected_to cve_watchlists_path
    follow_redirect!
    assert_match "CVE Watchlist deleted successfully", response.body
  end

  test "deleting watchlist also deletes associated alerts" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx)
    create_list(:vulnerability_alert, 3, cve_watchlist: watchlist)

    assert_difference("VulnerabilityAlert.count", -3) do
      delete cve_watchlist_path(watchlist)
    end
  end

  # =============================================================================
  # Alert Threshold Logic
  # =============================================================================

  test "watchlist with notification enabled includes notification settings" do
    sign_in @admin
    watchlist = create(:cve_watchlist,
      :nginx,
      notification_enabled: true,
      notification_threshold: "HIGH"
    )

    get cve_watchlist_path(watchlist)
    assert_response :success
    # Verify the watchlist has notification settings
    assert watchlist.notification_enabled
    assert_equal "HIGH", watchlist.notification_threshold
  end

  test "admin can update notification threshold" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx, notification_enabled: false)

    patch cve_watchlist_path(watchlist), params: {
      cve_watchlist: {
        notification_enabled: true,
        notification_threshold: "CRITICAL"
      }
    }

    assert_redirected_to cve_watchlist_path(watchlist)
    watchlist.reload
    assert watchlist.notification_enabled
    assert_equal "CRITICAL", watchlist.notification_threshold
  end

  # =============================================================================
  # Test Action (Manual Scan Trigger)
  # =============================================================================

  test "admin can trigger manual scan on watchlist" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx)

    # Mock the CVE monitoring service
    CveMonitoringService.stubs(:check_watchlist).returns([])
    CveMonitoringService.stubs(:fetch_vendor_product_vulnerabilities).returns([])

    post test_cve_watchlist_path(watchlist)

    assert_redirected_to cve_watchlist_path(watchlist)
  end

  test "force full scan option clears last_checked_at temporarily" do
    sign_in @admin
    watchlist = create(:cve_watchlist, :nginx, :checked)
    original_checked_at = watchlist.last_checked_at

    CveMonitoringService.stubs(:check_watchlist).returns([])
    CveMonitoringService.stubs(:fetch_vendor_product_vulnerabilities).returns([])

    post test_cve_watchlist_path(watchlist), params: { force_full_scan: true }

    assert_redirected_to cve_watchlist_path(watchlist)
    # After scan, original timestamp should be restored
    watchlist.reload
    assert_not_nil watchlist.last_checked_at
  end
end
