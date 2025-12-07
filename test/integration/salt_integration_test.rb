# frozen_string_literal: true

require "test_helper"

# Base class for Salt Stack integration tests
# These tests run against a real Salt API and require the staging environment
#
# IMPORTANT: These tests use the `n8n` minion for any operations that modify state.
# This minion is designated as the test minion on staging server (46.224.101.253).
#
# Tests will be skipped if:
# - Salt API is unavailable (connection refused, timeout, etc.)
# - SALT_API_PASSWORD environment variable is not set
class SaltIntegrationTest < ActionDispatch::IntegrationTest
  # Test minion ID designated for integration tests
  # This minion is safe for destructive operations
  TEST_MINION_ID = "n8n"

  # Connection timeout for Salt API availability check
  AVAILABILITY_TIMEOUT = 5

  def setup
    skip_unless_salt_api_available
  end

  def teardown
    cleanup_test_artifacts
  end

  protected

  # Check if Salt API is available for integration testing
  # Returns true if we can successfully authenticate with the Salt API
  def salt_api_available?
    return @salt_api_available if defined?(@salt_api_available)

    # Check if required environment variables are set
    unless ENV["SALT_API_PASSWORD"].present?
      Rails.logger.warn "Salt integration test skipped: SALT_API_PASSWORD not set"
      return @salt_api_available = false
    end

    # Try to connect and authenticate with Salt API
    begin
      SaltService.clear_token!
      result = SaltService.test_connection
      @salt_api_available = result[:status] == "connected"
    rescue SaltService::ConnectionError, SaltService::AuthenticationError => e
      Rails.logger.warn "Salt integration test skipped: #{e.message}"
      @salt_api_available = false
    rescue StandardError => e
      Rails.logger.warn "Salt integration test skipped: Unexpected error - #{e.message}"
      @salt_api_available = false
    end
  end

  # Skip test if Salt API is not available
  def skip_unless_salt_api_available
    skip "Salt API unavailable" unless salt_api_available?
  end

  # Check if the test minion is online and responsive
  # Returns true if the n8n minion responds to ping
  def test_minion_available?
    return @test_minion_available if defined?(@test_minion_available)

    begin
      result = SaltService.ping_minion(TEST_MINION_ID, timeout: AVAILABILITY_TIMEOUT)
      @test_minion_available = result&.dig("return", 0, TEST_MINION_ID) == true
    rescue StandardError => e
      Rails.logger.warn "Test minion unavailable: #{e.message}"
      @test_minion_available = false
    end
  end

  # Skip test if the test minion is not available
  def skip_unless_test_minion_available
    skip "Test minion '#{TEST_MINION_ID}' unavailable" unless test_minion_available?
  end

  # Get or create a server record for the test minion
  # This ensures we have a database record to test sync operations
  def test_minion_server
    @test_minion_server ||= Server.find_or_create_by!(minion_id: TEST_MINION_ID) do |server|
      server.hostname = TEST_MINION_ID
      server.ip_address = "10.0.0.1"
      server.status = "online"
    end
  end

  # Clean up any test artifacts created during tests
  def cleanup_test_artifacts
    cleanup_test_pillars
  end

  # Clean up test pillar files created during tests
  def cleanup_test_pillars
    test_pillar_dir = "/srv/pillar/minions/#{TEST_MINION_ID}"
    test_pillar_file = "#{test_pillar_dir}/integration_test.sls"

    if File.exist?(test_pillar_file)
      FileUtils.rm_f(test_pillar_file)
      Rails.logger.info "Cleaned up test pillar: #{test_pillar_file}"
    end
  end

  # Assert that a Salt API response indicates success
  def assert_salt_success(result, message = nil)
    assert result.is_a?(Hash), "Expected Hash result, got #{result.class}"

    if result.key?(:success)
      assert result[:success], message || "Expected success=true, got: #{result.inspect}"
    elsif result.key?("return")
      assert result["return"].present?, message || "Expected non-empty return, got: #{result.inspect}"
    else
      flunk message || "Unable to determine success from result: #{result.inspect}"
    end
  end

  # Assert that a Salt command returned a valid response for the test minion
  def assert_minion_responded(result, minion_id = TEST_MINION_ID)
    assert result.is_a?(Hash), "Expected Hash result"
    assert result["return"].present?, "Expected 'return' key in result"
    assert result["return"].first.is_a?(Hash), "Expected first return element to be Hash"

    minion_response = result["return"].first[minion_id]
    assert_not_nil minion_response, "Expected response from minion '#{minion_id}'"

    minion_response
  end
end
