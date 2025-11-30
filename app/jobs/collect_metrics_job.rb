# frozen_string_literal: true

# Background job for collecting metrics from servers
# Can be called with a specific server_id or without arguments to collect from all online servers
class CollectMetricsJob < ApplicationJob
  include DashboardBroadcaster

  queue_as :metrics

  # Retry configuration for single server collection
  retry_on SaltService::ConnectionError, wait: :exponentially_longer, attempts: 3
  retry_on SaltService::AuthenticationError, wait: 1.minute, attempts: 2
  retry_on NetworkError, wait: :exponentially_longer, attempts: 3
  retry_on TimeoutError, wait: 30.seconds, attempts: 3

  # Don't retry on permanent errors
  discard_on ActiveRecord::RecordNotFound
  discard_on ConfigurationError

  def perform(server_id = nil, retry_count: 0)
    if server_id.present?
      # Collect metrics for specific server
      collect_for_server(server_id, retry_count)
    else
      # Collect metrics for all online servers
      collect_for_all_servers
    end
  end

  private

  def collect_for_server(server_id, retry_count = 0)
    server = Server.find_by(id: server_id)
    return unless server

    Rails.logger.info "CollectMetricsJob: Collecting metrics for server #{server.hostname} (attempt #{retry_count + 1})"

    # Collect metrics using the MetricsCollector service
    metrics = MetricsCollector.collect_for_server(server)

    if metrics.present?
      Rails.logger.info "CollectMetricsJob: Successfully collected metrics for #{server.hostname}"
    else
      Rails.logger.warn "CollectMetricsJob: Failed to collect metrics for #{server.hostname}"
    end
  rescue SaltService::ConnectionError, SaltService::AuthenticationError => e
    # Transient Salt API errors - let ActiveJob retry handle this
    Rails.logger.error "CollectMetricsJob: Salt API error for #{server.hostname}: #{e.message} (will retry)"
    raise
  rescue StandardError => e
    # Log and re-raise to trigger retry
    Rails.logger.error "CollectMetricsJob: Error for server #{server_id}: #{e.class.name} - #{e.message}"
    raise
  end

  def collect_for_all_servers
    Rails.logger.info "CollectMetricsJob: Collecting metrics for all online servers"
    start_time = Time.current

    # Create tracking command
    # Performance Fix: Use deterministic server selection instead of Server.first (non-deterministic)
    # This ensures consistent tracking server selection and prevents duplicate tracking records
    tracking_server = Server.order(:id).first
    return unless tracking_server

    cmd = Command.create!(
      server: tracking_server,
      command_type: 'system',
      command: 'collect_metrics',
      arguments: { job: 'CollectMetricsJob', scope: 'all_servers' },
      status: 'running',
      started_at: start_time
    )

    begin
      online_servers = Server.where(status: 'online')
      total_count = online_servers.count
      success_count = 0
      error_count = 0
      retry_count = 0
      output_lines = []

      online_servers.find_each do |server|
        begin
          # Attempt to collect with retry for transient errors
          collect_with_retry(server, output_lines)
          success_count += 1
        rescue TransientError => e
          # Transient error after retries - log and continue
          error_count += 1
          retry_count += 1
          output_lines << "✗ #{server.hostname}: #{e.class.name} - #{e.message} (retries exhausted)"
          Rails.logger.warn "CollectMetricsJob: Transient error for #{server.hostname} after retries: #{e.message}"
        rescue PermanentError => e
          # Permanent error - log and continue
          error_count += 1
          output_lines << "✗ #{server.hostname}: #{e.class.name} - #{e.message} (permanent failure)"
          Rails.logger.error "CollectMetricsJob: Permanent error for #{server.hostname}: #{e.message}"
        rescue StandardError => e
          # Unknown error - log and continue with next server
          error_count += 1
          output_lines << "✗ #{server.hostname}: #{e.class.name} - #{e.message}"
          Rails.logger.error "CollectMetricsJob: Error collecting for #{server.hostname}: #{e.class.name} - #{e.message}"
        end
      end

      summary = "Metrics collection: #{success_count}/#{total_count} servers successful"
      summary += ", #{retry_count} transient failures" if retry_count > 0
      Rails.logger.info "CollectMetricsJob: #{summary}"

      cmd.update!(
        status: 'completed',
        output: "#{summary}\n\n#{output_lines.join("\n")}",
        exit_code: error_count > 0 ? 1 : 0,
        completed_at: Time.current
      )

      # Broadcast dashboard updates
      broadcast_stats_update
    rescue StandardError => e
      cmd.update!(
        status: 'failed',
        error_output: "Metrics collection failed: #{e.message}\n#{e.backtrace.first(3).join("\n")}",
        exit_code: 99,
        completed_at: Time.current
      )
      raise
    end
  end

  # Collect metrics with per-server retry logic for transient failures
  def collect_with_retry(server, output_lines, max_attempts: 3)
    attempts = 0
    last_error = nil

    max_attempts.times do |attempt|
      attempts = attempt + 1
      begin
        Rails.logger.debug "CollectMetricsJob: Attempt #{attempts}/#{max_attempts} for #{server.hostname}"

        MetricsCollector.collect_for_server(server)
        output_lines << "✓ #{server.hostname}: Metrics collected" + (attempts > 1 ? " (attempt #{attempts})" : "")
        return true
      rescue SaltService::ConnectionError, SaltService::AuthenticationError => e
        last_error = map_to_transient_error(e)
        Rails.logger.warn "CollectMetricsJob: Transient error on attempt #{attempts} for #{server.hostname}: #{e.message}"

        # Wait before retry with exponential backoff
        if attempts < max_attempts
          sleep_time = [2**attempts, 30].min
          Rails.logger.debug "CollectMetricsJob: Waiting #{sleep_time}s before retry..."
          sleep sleep_time
        end
      rescue Timeout::Error => e
        last_error = TimeoutError.new("Metrics collection timed out for #{server.hostname}", context: { server_id: server.id })
        Rails.logger.warn "CollectMetricsJob: Timeout on attempt #{attempts} for #{server.hostname}"

        if attempts < max_attempts
          sleep 5
        end
      rescue StandardError => e
        # Unknown error - re-raise immediately (no retry)
        raise
      end
    end

    # All retries exhausted
    raise last_error if last_error
  end

  # Map Salt errors to our custom error hierarchy
  def map_to_transient_error(error)
    case error
    when SaltService::ConnectionError
      NetworkError.new("Salt API connection failed: #{error.message}", context: { original_error: error.class.name })
    when SaltService::AuthenticationError
      # Authentication could be transient (token expired) or permanent (bad credentials)
      # Treat as transient with limited retries
      TransientError.new("Salt API authentication failed: #{error.message}", context: { original_error: error.class.name })
    else
      TransientError.new(error.message, context: { original_error: error.class.name })
    end
  end
end