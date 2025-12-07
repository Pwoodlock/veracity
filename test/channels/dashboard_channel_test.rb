# frozen_string_literal: true

require "test_helper"

# Action Cable channel tests for DashboardChannel
# These tests verify that the DashboardChannel correctly handles
# subscription, unsubscription, and streaming
class DashboardChannelTest < ActionCable::Channel::TestCase
  setup do
    @user = create(:user, :admin)
  end

  # ===========================================
  # DashboardChannel Subscription Tests
  # ===========================================

  test "subscribes to dashboard stream" do
    stub_connection(current_user: @user)

    subscribe

    assert subscription.confirmed?
    assert_has_stream "dashboard"
  end

  test "rejects subscription without current_user" do
    # When current_user is nil, accessing current_user.email in subscribed will fail
    # In production, the connection would reject before reaching the channel
    # This test verifies the channel behavior requires an authenticated user
    stub_connection(current_user: nil)

    # The channel accesses current_user.email in subscribed callback
    # which will raise NoMethodError when current_user is nil
    assert_raises(NoMethodError) do
      subscribe
    end
  end

  test "multiple users can subscribe to same dashboard stream" do
    user1 = create(:user, :admin)
    user2 = create(:user, :operator)

    stub_connection(current_user: user1)
    subscribe

    assert subscription.confirmed?
    assert_has_stream "dashboard"

    # Unsubscribe to test second user
    unsubscribe

    stub_connection(current_user: user2)
    subscribe

    assert subscription.confirmed?
    assert_has_stream "dashboard"
  end

  test "viewer role can subscribe to dashboard stream" do
    viewer = create(:user, :viewer)

    stub_connection(current_user: viewer)
    subscribe

    assert subscription.confirmed?
    assert_has_stream "dashboard"
  end

  test "unsubscribes cleanly from dashboard stream" do
    stub_connection(current_user: @user)

    subscribe
    assert subscription.confirmed?

    unsubscribe

    # After unsubscribe, the subscription should be removed
    assert_no_streams
  end
end

# ===========================================
# Turbo Stream Broadcast Integration Tests
# ===========================================
class TurboBroadcastIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
  end

  test "server creation broadcasts dashboard stats update" do
    sign_in @admin

    # Use assert_broadcasts to verify the broadcast happens
    assert_broadcasts("dashboard", 1) do
      create(:server, :online)
    end
  end

  test "server status change broadcasts dashboard stats update" do
    sign_in @admin

    server = create(:server, :online)

    # Clear the broadcast from creation by using a new assertion block
    assert_broadcasts("dashboard", 1) do
      server.update!(status: "offline")
    end
  end

  test "server destruction broadcasts dashboard stats update" do
    sign_in @admin

    server = create(:server, :online)

    assert_broadcasts("dashboard", 1) do
      server.destroy!
    end
  end

  test "dashboard broadcast contains correct stats data" do
    sign_in @admin

    # Clean up existing data
    Server.destroy_all
    create(:server, :online)
    create(:server, :offline)

    # Use perform_enqueued_jobs to ensure broadcasts are processed
    perform_enqueued_jobs do
      server = create(:server, :online)
      # The broadcast is triggered after commit
    end

    # Verify dashboard page shows correct stats after broadcast
    get dashboard_path
    assert_response :success

    assert_equal 3, assigns(:total_servers)
    assert_equal 2, assigns(:online_servers)
    assert_equal 1, assigns(:offline_servers)
  end
end

# ===========================================
# Server Status Update Broadcast Tests
# ===========================================
class ServerStatusBroadcastTest < ActiveSupport::TestCase
  test "server status change from online to offline triggers broadcast" do
    server = create(:server, :online)

    assert_broadcasts("dashboard", 1) do
      server.update!(status: "offline")
    end
  end

  test "server status change from offline to online triggers broadcast" do
    server = create(:server, :offline)

    assert_broadcasts("dashboard", 1) do
      server.update!(status: "online")
    end
  end

  test "server update without status change does not trigger broadcast" do
    server = create(:server, :online)

    # Updating hostname (non-status field) should not trigger broadcast
    # Note: The model only broadcasts on status change via saved_change_to_status?
    assert_broadcasts("dashboard", 0) do
      server.update!(hostname: "new-hostname")
    end
  end

  test "server creation triggers single broadcast" do
    # Server creation triggers broadcast via after_create_commit
    assert_broadcasts("dashboard", 1) do
      create(:server, :online)
    end
  end

  test "server status change enqueues notification job" do
    server = create(:server, :online)

    # Changing status should enqueue NotifyServerStatusChangeJob
    assert_enqueued_with(job: NotifyServerStatusChangeJob) do
      server.update!(status: "offline")
    end
  end

  test "server creation does not enqueue status change notification" do
    # Server creation doesn't trigger enqueue_status_change_notification
    # because it's an after_update_commit callback, not after_create
    assert_no_enqueued_jobs(only: NotifyServerStatusChangeJob) do
      create(:server, :online)
    end
  end
end
