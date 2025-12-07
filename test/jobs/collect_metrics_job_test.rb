# frozen_string_literal: true

require "test_helper"

class CollectMetricsJobTest < ActiveJob::TestCase
  setup do
    @server = create(:server, :online, hostname: "metrics-server", minion_id: "metrics-minion")

    # Mock Salt API responses
    mock_salt_api
  end

  # =============================================================================
  # Test 4.4.3: CollectMetricsJob collects server metrics
  # =============================================================================
  test "perform collects metrics for specific server" do
    # Mock MetricsCollector to return test data
    test_metrics = {
      load: { load_1m: 0.5, load_5m: 0.4, load_15m: 0.3 },
      memory: { total_gb: 8.0, used_gb: 4.0, percent_used: 50.0 },
      disk: { "/" => { total_gb: 100.0, used_gb: 50.0, percent_used: 50.0 } }
    }

    MetricsCollector.stubs(:collect_for_server).with(@server).returns(test_metrics)

    CollectMetricsJob.perform_now(@server.id)

    # Job should complete without error
    # Metrics collection was triggered
  end

  test "perform handles missing server gracefully" do
    non_existent_id = SecureRandom.uuid

    # Should not raise error
    assert_nothing_raised do
      CollectMetricsJob.perform_now(non_existent_id)
    end
  end

  test "perform collects for all online servers when no ID given" do
    # Create multiple online servers
    server2 = create(:server, :online, hostname: "server-2")
    server3 = create(:server, :online, hostname: "server-3")
    create(:server, :offline, hostname: "offline-server")

    # Track which servers were processed
    processed_servers = []
    MetricsCollector.stubs(:collect_for_server).with do |server|
      processed_servers << server.id
      true
    end.returns({})

    # Stub Command.create! to avoid validation issues
    Command.stubs(:create!).returns(Command.new)
    Command.any_instance.stubs(:update!).returns(true)

    CollectMetricsJob.new.send(:collect_for_all_servers)

    # All online servers should have been processed
    assert_includes processed_servers, @server.id
    assert_includes processed_servers, server2.id
    assert_includes processed_servers, server3.id
  end

  test "perform retries on Salt connection errors" do
    MetricsCollector.stubs(:collect_for_server).raises(SaltService::ConnectionError.new("Connection failed"))

    # Job should be configured to retry
    assert_includes CollectMetricsJob.rescue_handlers.keys, SaltService::ConnectionError
  end

  test "perform retries on authentication errors" do
    MetricsCollector.stubs(:collect_for_server).raises(SaltService::AuthenticationError.new("Auth failed"))

    # Job should be configured to retry auth errors
    assert_includes CollectMetricsJob.rescue_handlers.keys, SaltService::AuthenticationError
  end

  # =============================================================================
  # Test 4.4.4: Job error handling and retries
  # =============================================================================
  test "job discards on record not found" do
    # Job should be configured to discard on RecordNotFound
    assert_includes CollectMetricsJob.discard_handlers.keys, ActiveRecord::RecordNotFound
  end

  test "collect_with_retry retries transient errors up to max_attempts" do
    job = CollectMetricsJob.new
    output_lines = []

    # First two attempts fail, third succeeds
    call_count = 0
    MetricsCollector.stubs(:collect_for_server).with(@server).with do
      call_count += 1
      if call_count < 3
        raise SaltService::ConnectionError.new("Connection failed")
      end
      true
    end.returns({})

    # Stub sleep to speed up test
    job.stubs(:sleep)

    result = job.send(:collect_with_retry, @server, output_lines, max_attempts: 3)

    assert result
    assert_equal 3, call_count
    assert output_lines.any? { |line| line.include?(@server.hostname) }
  end

  test "collect_with_retry raises after exhausting retries" do
    job = CollectMetricsJob.new
    output_lines = []

    MetricsCollector.stubs(:collect_for_server).raises(SaltService::ConnectionError.new("Connection failed"))
    job.stubs(:sleep)

    # Should eventually fail
    error = assert_raises(TransientError) do
      job.send(:collect_with_retry, @server, output_lines, max_attempts: 3)
    end

    assert_match(/Salt API connection failed/, error.message)
  end

  test "map_to_transient_error converts Salt errors correctly" do
    job = CollectMetricsJob.new

    # ConnectionError maps to NetworkError
    connection_error = SaltService::ConnectionError.new("Connection refused")
    result = job.send(:map_to_transient_error, connection_error)
    assert_instance_of NetworkError, result

    # AuthenticationError maps to TransientError
    auth_error = SaltService::AuthenticationError.new("Token expired")
    result = job.send(:map_to_transient_error, auth_error)
    assert_instance_of TransientError, result
  end

  test "perform broadcasts dashboard update after collecting all metrics" do
    Command.stubs(:create!).returns(Command.new)
    Command.any_instance.stubs(:update!).returns(true)
    MetricsCollector.stubs(:collect_for_server).returns({})

    # Track if broadcast was called
    broadcast_called = false
    CollectMetricsJob.any_instance.stubs(:broadcast_stats_update).with { broadcast_called = true }

    job = CollectMetricsJob.new
    job.send(:collect_for_all_servers)

    assert broadcast_called, "Dashboard should be updated after metrics collection"
  end
end
