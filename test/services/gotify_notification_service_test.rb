# frozen_string_literal: true

require "test_helper"

class GotifyNotificationServiceTest < ActiveSupport::TestCase
  setup do
    # Configure Gotify as enabled
    SystemSetting.stubs(:get).with("gotify_enabled", false).returns(true)
    SystemSetting.stubs(:get).with("gotify_url").returns("https://gotify.example.com")
    SystemSetting.stubs(:get).with("gotify_app_token").returns("test-app-token-12345")
    SystemSetting.stubs(:get).with("gotify_ssl_verify", true).returns(true)

    # Mock rate limiter to always allow
    RateLimiter.stubs(:check_limit!).returns({ allowed: true, remaining: 50 })

    # Clear any existing notification histories
    NotificationHistory.delete_all
  end

  # =============================================================================
  # Test 4.2.1: send_notification builds correct payload
  # =============================================================================
  test "send_notification builds correct payload and creates history" do
    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ "id" => 12345 })

    HTTParty.stubs(:post).returns(mock_response)

    result = GotifyNotificationService.send_notification(
      title: "Test Alert",
      message: "This is a test message",
      priority: 5,
      extras: { source: "unit_test" }
    )

    assert_instance_of NotificationHistory, result
    assert_equal "Test Alert", result.title
    assert_equal "This is a test message", result.message
    assert_equal 5, result.priority
    assert_equal "sent", result.status
  end

  test "send_notification includes extras metadata in payload" do
    captured_body = nil

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ "id" => 123 })

    HTTParty.stubs(:post).with do |url, options|
      captured_body = JSON.parse(options[:body])
      true
    end.returns(mock_response)

    GotifyNotificationService.send_notification(
      title: "Alert",
      message: "Message",
      extras: { server_id: 42, event: "offline" }
    )

    assert_not_nil captured_body
    assert_equal "Alert", captured_body["title"]
    assert_equal "Message", captured_body["message"]
  end

  test "send_notification returns nil when service is disabled" do
    GotifyNotificationService.stubs(:enabled?).returns(false)

    result = GotifyNotificationService.send_notification(
      title: "Test",
      message: "Should not send"
    )

    assert_nil result
  end

  # =============================================================================
  # Test 4.2.2: Priority levels are handled correctly
  # =============================================================================
  test "send_alert uses critical priority" do
    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ "id" => 456 })

    HTTParty.stubs(:post).returns(mock_response)

    result = GotifyNotificationService.send_alert(
      title: "Critical Issue",
      message: "Something is broken"
    )

    assert_instance_of NotificationHistory, result
    assert_equal NotificationHistory::PRIORITY_CRITICAL, result.priority
    assert_match(/ALERT:/, result.title)
  end

  test "notify_server_event uses appropriate priority for offline event" do
    server = build_stubbed(:server, :online, hostname: "web-01", ip_address: "192.168.1.10")

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ "id" => 789 })

    HTTParty.stubs(:post).returns(mock_response)

    result = GotifyNotificationService.notify_server_event(server, "offline", "Connection lost")

    assert_instance_of NotificationHistory, result
    assert_equal NotificationHistory::PRIORITY_HIGH, result.priority
    assert_equal "server_event", result.notification_type
  end

  test "notify_server_event uses normal priority for online event" do
    server = build_stubbed(:server, :online, hostname: "web-01")

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ "id" => 111 })

    HTTParty.stubs(:post).returns(mock_response)

    result = GotifyNotificationService.notify_server_event(server, "online", "Server recovered")

    assert_equal NotificationHistory::PRIORITY_NORMAL, result.priority
  end

  test "severity_to_priority maps CVE severities correctly" do
    # Access private method for testing
    service = GotifyNotificationService

    assert_equal NotificationHistory::PRIORITY_CRITICAL,
                 service.send(:severity_to_priority, "CRITICAL")
    assert_equal NotificationHistory::PRIORITY_HIGH,
                 service.send(:severity_to_priority, "HIGH")
    assert_equal NotificationHistory::PRIORITY_NORMAL,
                 service.send(:severity_to_priority, "MEDIUM")
    assert_equal NotificationHistory::PRIORITY_LOW,
                 service.send(:severity_to_priority, "LOW")
  end

  # =============================================================================
  # Test 4.2.3: Error handling for connection failures
  # =============================================================================
  test "send_notification handles connection timeout with retry" do
    # First two attempts fail, third succeeds
    call_count = 0
    HTTParty.stubs(:post).with do |_url, _options|
      call_count += 1
      true
    end.returns do
      if call_count < 3
        raise Net::ReadTimeout.new("Connection timed out")
      else
        mock_response = mock
        mock_response.stubs(:success?).returns(true)
        mock_response.stubs(:parsed_response).returns({ "id" => 999 })
        mock_response
      end
    end

    # Stub sleep to speed up tests
    GotifyNotificationService.stubs(:sleep)

    result = GotifyNotificationService.send_notification(
      title: "Retry Test",
      message: "Should retry on timeout"
    )

    assert_instance_of NotificationHistory, result
    assert_equal "sent", result.status
    assert_equal 3, call_count
  end

  test "send_notification marks history as failed after max retries" do
    HTTParty.stubs(:post).raises(Errno::ECONNREFUSED.new("Connection refused"))
    GotifyNotificationService.stubs(:sleep)

    assert_raises(Errno::ECONNREFUSED) do
      GotifyNotificationService.send_notification(
        title: "Connection Test",
        message: "Should fail after retries"
      )
    end

    # Check that a failed notification history was created
    history = NotificationHistory.last
    assert_equal "failed", history.status
    assert_match(/Connection/, history.error_message)
  end

  test "send_notification handles HTTP 500 errors as transient" do
    mock_response = mock
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(500)
    mock_response.stubs(:to_i).returns(500)
    mock_response.stubs(:message).returns("Internal Server Error")

    # Stub to always return 500
    HTTParty.stubs(:post).returns(mock_response)
    GotifyNotificationService.stubs(:sleep)

    # Service raises ServiceUnavailableError (from transient_error.rb) on 500 errors
    assert_raises(ServiceUnavailableError) do
      GotifyNotificationService.send_notification(
        title: "Server Error Test",
        message: "Should fail on 500"
      )
    end
  end

  # =============================================================================
  # Test 4.2.4: test_connection returns proper status
  # =============================================================================
  test "test_connection returns success when API responds correctly" do
    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({ "id" => 12345 })

    HTTParty.stubs(:post).returns(mock_response)

    result = GotifyNotificationService.test_connection

    assert result[:success]
    assert_equal "Connection successful", result[:message]
    assert_equal 12345, result[:response]["id"]
  end

  test "test_connection returns failure when API returns error" do
    mock_response = mock
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(401)
    mock_response.stubs(:message).returns("Unauthorized")

    HTTParty.stubs(:post).returns(mock_response)

    result = GotifyNotificationService.test_connection

    assert_not result[:success]
    assert_match(/401/, result[:message])
  end

  test "test_connection raises ConfigurationError when not enabled" do
    GotifyNotificationService.stubs(:enabled?).returns(false)

    assert_raises(GotifyNotificationService::ConfigurationError) do
      GotifyNotificationService.test_connection
    end
  end

  test "test_connection raises ConfigurationError when URL missing" do
    GotifyNotificationService.stubs(:enabled?).returns(true)
    GotifyNotificationService.stubs(:gotify_url).returns(nil)

    assert_raises(GotifyNotificationService::ConfigurationError) do
      GotifyNotificationService.test_connection
    end
  end

  test "test_connection raises ConfigurationError when token missing" do
    GotifyNotificationService.stubs(:enabled?).returns(true)
    GotifyNotificationService.stubs(:gotify_url).returns("https://gotify.example.com")
    GotifyNotificationService.stubs(:app_token).returns(nil)

    assert_raises(GotifyNotificationService::ConfigurationError) do
      GotifyNotificationService.test_connection
    end
  end

  test "test_connection handles network errors gracefully" do
    HTTParty.stubs(:post).raises(SocketError.new("DNS resolution failed"))

    result = GotifyNotificationService.test_connection

    assert_not result[:success]
    assert_match(/DNS resolution failed/, result[:message])
  end
end
