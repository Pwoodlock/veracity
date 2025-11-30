# frozen_string_literal: true

require 'httparty'

class GotifyNotificationService
  include HTTParty

  class GotifyError < StandardError; end
  class ConfigurationError < GotifyError; end
  class ConnectionError < GotifyError; end
  class RateLimitError < GotifyError; end

  # Maximum retry attempts
  MAX_RETRIES = 3
  # Timeout for API calls (5 seconds)
  TIMEOUT = 5
  # Rate limiting: max notifications per minute
  RATE_LIMIT = 60

  class << self
    # Send a generic notification
    # @param title [String] Notification title
    # @param message [String] Notification message (supports Markdown)
    # @param priority [Integer] Priority level (0-10, default: 5)
    # @param extras [Hash] Additional metadata
    # @return [NotificationHistory] The created notification history record
    def send_notification(title:, message:, priority: NotificationHistory::PRIORITY_NORMAL, extras: {})
      return unless enabled?

      # Check global rate limit using Redis-based rate limiter
      check_rate_limit_redis!

      history = NotificationHistory.create!(
        notification_type: 'system_event',
        title: title,
        message: message,
        priority: priority,
        metadata: extras,
        status: 'pending'
      )

      send_with_retry(history)
      history
    rescue ConfigurationError => e
      # Permanent configuration errors - log and re-raise
      Rails.logger.error "GotifyNotificationService: Configuration error: #{e.message}"
      history&.mark_failed!(e.message)
      raise
    rescue RateLimitError, GotifyError => e
      # Transient errors - log but don't fail the caller
      # These will be retried automatically by the retry logic
      Rails.logger.warn "GotifyNotificationService: Transient error: #{e.message}"
      history&.mark_failed!(e.message)
      # Re-raise to allow retry mechanism to work
      raise
    rescue StandardError => e
      # Unknown errors - log with full context
      Rails.logger.error "GotifyNotificationService: Unexpected error: #{e.class.name} - #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
      history&.mark_failed!(e.message)
      # Re-raise in all environments for proper error tracking
      raise
    end

    # Send a high-priority alert
    # @param title [String] Alert title
    # @param message [String] Alert message
    # @param extras [Hash] Additional metadata
    # @return [NotificationHistory]
    def send_alert(title:, message:, extras: {})
      send_notification(
        title: "ALERT: #{title}",
        message: message,
        priority: NotificationHistory::PRIORITY_CRITICAL,
        extras: extras
      )
    end

    # Notify about server status changes
    # @param server [Server] The server instance
    # @param event [String] Event type (offline, online, error)
    # @param details [String] Additional details
    def notify_server_event(server, event, details = nil)
      return unless enabled?

      # Check rate limits: global + per-server
      check_rate_limit_redis!
      RateLimiter.check_limit!(:server, identifier: server.id)

      priority = case event.to_s
                when 'offline', 'error' then NotificationHistory::PRIORITY_HIGH
                when 'online' then NotificationHistory::PRIORITY_NORMAL
                else NotificationHistory::PRIORITY_LOW
                end

      title = "Server #{event.to_s.upcase}: #{server.hostname}"
      message = build_server_message(server, event, details)

      history = NotificationHistory.create!(
        notification_type: 'server_event',
        title: title,
        message: message,
        priority: priority,
        metadata: {
          server_id: server.id,
          server_hostname: server.hostname,
          event: event,
          ip_address: server.ip_address,
          environment: server.environment
        },
        status: 'pending'
      )

      send_with_retry(history)
      history
    rescue StandardError => e
      Rails.logger.error "GotifyNotificationService: Failed to send server event notification: #{e.message}"
      history&.mark_failed!(e.message)
      nil
    end

    # Notify about CVE alerts
    # @param alert [VulnerabilityAlert] The vulnerability alert
    def notify_cve_alert(alert)
      return unless enabled?

      # Check rate limits: global + cve_alert specific
      check_rate_limit_redis!
      RateLimiter.check_limit!(:cve_alert)

      priority = severity_to_priority(alert.severity)

      title = "CVE Alert: #{alert.cve_id}"
      message = build_cve_message(alert)

      history = NotificationHistory.create!(
        notification_type: 'cve_alert',
        title: title,
        message: message,
        priority: priority,
        metadata: {
          alert_id: alert.id,
          cve_id: alert.cve_id,
          severity: alert.severity,
          server_id: alert.server_id,
          server_hostname: alert.server&.hostname
        },
        status: 'pending'
      )

      send_with_retry(history)
      history
    rescue StandardError => e
      Rails.logger.error "GotifyNotificationService: Failed to send CVE alert: #{e.message}"
      history&.mark_failed!(e.message)
      nil
    end

    # Notify about task execution results
    # @param task_execution [TaskExecution] The task execution record
    def notify_task_execution(task_execution)
      return unless enabled?

      # Check rate limits: global + task_execution specific
      check_rate_limit_redis!
      RateLimiter.check_limit!(:task_execution)

      status = task_execution.status
      priority = case status
                when 'failed' then NotificationHistory::PRIORITY_HIGH
                when 'completed' then NotificationHistory::PRIORITY_NORMAL
                else NotificationHistory::PRIORITY_LOW
                end

      title = "Task #{status.upcase}: #{task_execution.scheduled_task.name}"
      message = build_task_message(task_execution)

      history = NotificationHistory.create!(
        notification_type: 'task_execution',
        title: title,
        message: message,
        priority: priority,
        metadata: {
          task_execution_id: task_execution.id,
          task_id: task_execution.scheduled_task_id,
          task_name: task_execution.scheduled_task.name,
          status: status,
          duration: task_execution.duration_seconds
        },
        status: 'pending'
      )

      send_with_retry(history)
      history
    rescue StandardError => e
      Rails.logger.error "GotifyNotificationService: Failed to send task execution notification: #{e.message}"
      history&.mark_failed!(e.message)
      nil
    end

    # Notify about backup status
    # @param backup_history [BackupHistory] The backup history record
    def notify_backup_status(backup_history)
      return unless enabled?

      # Check rate limits: global + backup specific
      check_rate_limit_redis!
      RateLimiter.check_limit!(:backup)

      status = backup_history.status
      priority = case status
                when 'failed' then NotificationHistory::PRIORITY_CRITICAL
                when 'completed' then NotificationHistory::PRIORITY_NORMAL
                else NotificationHistory::PRIORITY_LOW
                end

      title = "Backup #{status.upcase}: #{backup_history.backup_name}"
      message = build_backup_message(backup_history)

      history = NotificationHistory.create!(
        notification_type: 'backup',
        title: title,
        message: message,
        priority: priority,
        metadata: {
          backup_history_id: backup_history.id,
          backup_name: backup_history.backup_name,
          status: status,
          duration: backup_history.duration_seconds,
          size: backup_history.deduplicated_size
        },
        status: 'pending'
      )

      send_with_retry(history)
      history
    rescue StandardError => e
      Rails.logger.error "GotifyNotificationService: Failed to send backup notification: #{e.message}"
      history&.mark_failed!(e.message)
      nil
    end

    # Notify about user management events
    # @param user [User] The user instance
    # @param event [String] Event type (created, updated, deleted, 2fa_enabled, etc.)
    # @param details [String] Additional details
    def notify_user_event(user, event, details = nil)
      return unless enabled?

      # Check rate limits: global + per-user
      check_rate_limit_redis!
      RateLimiter.check_limit!(:user, identifier: user.id)

      priority = case event.to_s
                when 'deleted', 'locked' then NotificationHistory::PRIORITY_HIGH
                when '2fa_enabled', 'role_changed' then NotificationHistory::PRIORITY_NORMAL
                else NotificationHistory::PRIORITY_LOW
                end

      title = "User #{event.to_s.humanize}: #{user.email}"
      message = build_user_message(user, event, details)

      history = NotificationHistory.create!(
        notification_type: 'user_event',
        title: title,
        message: message,
        priority: priority,
        metadata: {
          user_id: user.id,
          user_email: user.email,
          event: event,
          role: user.role
        },
        status: 'pending'
      )

      send_with_retry(history)
      history
    rescue StandardError => e
      Rails.logger.error "GotifyNotificationService: Failed to send user event notification: #{e.message}"
      history&.mark_failed!(e.message)
      nil
    end

    # Test connection to Gotify server
    # @return [Hash] Connection test result
    def test_connection
      raise ConfigurationError, 'Gotify is not enabled' unless enabled?
      raise ConfigurationError, 'Gotify URL not configured' if gotify_url.blank?
      raise ConfigurationError, 'Gotify app token not configured' if app_token.blank?

      # Configure SSL verification
      ssl_opts = {}
      unless ssl_verify_enabled?
        ssl_opts[:verify] = false
      end

      # Send a test notification
      response = HTTParty.post(
        "#{gotify_url}/message",
        headers: headers,
        body: {
          title: 'Test Notification',
          message: 'Server Manager - Gotify integration is working correctly!',
          priority: NotificationHistory::PRIORITY_NORMAL
        }.to_json,
        timeout: TIMEOUT,
        **ssl_opts
      )

      if response.success?
        { success: true, message: 'Connection successful', response: response.parsed_response }
      else
        { success: false, message: "Connection failed: #{response.code} - #{response.message}" }
      end
    rescue StandardError => e
      { success: false, message: "Connection error: #{e.message}" }
    end

    # Check if Gotify is enabled and configured
    # @return [Boolean]
    def enabled?
      # ENV takes precedence over database
      env_enabled = ENV['GOTIFY_ENABLED']
      return env_enabled == 'true' if env_enabled.present?

      SystemSetting.get('gotify_enabled', false) == true
    end

    # Get Gotify URL from settings
    # @return [String]
    def gotify_url
      ENV['GOTIFY_URL'] || SystemSetting.get('gotify_url')
    end

    # Get Gotify app token from settings
    # @return [String]
    def app_token
      ENV['GOTIFY_APP_TOKEN'] || SystemSetting.get('gotify_app_token')
    end

    # Check if SSL verification is enabled
    # @return [Boolean]
    def ssl_verify_enabled?
      env_verify = ENV['GOTIFY_SSL_VERIFY']
      return env_verify == 'true' if env_verify.present?

      SystemSetting.get('gotify_ssl_verify', true)
    end

    private

    # Send notification with retry logic
    def send_with_retry(history, attempt = 1)
      raise ConfigurationError, 'Gotify is not configured' if gotify_url.blank? || app_token.blank?

      # Configure SSL verification
      ssl_opts = {}
      unless ssl_verify_enabled?
        ssl_opts[:verify] = false
        Rails.logger.warn "[Gotify] SSL verification disabled" if attempt == 1
      end

      response = HTTParty.post(
        "#{gotify_url}/message",
        headers: headers,
        body: {
          title: history.title,
          message: history.message,
          priority: history.priority,
          extras: history.metadata
        }.to_json,
        timeout: TIMEOUT,
        **ssl_opts
      )

      if response.success?
        message_id = response.parsed_response['id']
        history.mark_sent!(message_id)
        Rails.logger.info "GotifyNotificationService: Notification sent successfully (ID: #{message_id})"
      else
        # Classify HTTP errors as transient or permanent
        handle_http_error(response, history, attempt)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      # Timeout errors - transient, should retry
      handle_transient_error(e, 'Request timeout', history, attempt)
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      # Connection errors - transient, should retry
      handle_transient_error(e, 'Connection failed', history, attempt)
    rescue SocketError => e
      # DNS errors - transient, should retry
      handle_transient_error(e, 'DNS resolution failed', history, attempt)
    rescue ConfigurationError
      # Configuration errors - permanent, don't retry
      history.mark_failed!("Configuration error")
      raise
    rescue StandardError => e
      # Unknown errors - log and retry
      handle_transient_error(e, 'Unknown error', history, attempt)
    end

    # Handle HTTP response errors
    def handle_http_error(response, history, attempt)
      status_code = response.code.to_i

      case status_code
      when 401, 403
        # Authentication/Authorization errors - permanent
        error_msg = "Authentication failed: HTTP #{status_code}"
        history.mark_failed!(error_msg)
        raise AuthenticationError.new(error_msg, status_code: status_code)
      when 400, 404, 422
        # Bad request errors - permanent
        error_msg = "Bad request: HTTP #{status_code} - #{response.message}"
        history.mark_failed!(error_msg)
        raise BadRequestError.new(error_msg, status_code: status_code)
      when 429
        # Rate limiting - transient but needs special handling
        error = RateLimitError.new("Rate limited: HTTP 429", status_code: 429)
        handle_transient_error(error, 'Rate limited', history, attempt)
      when 500..599
        # Server errors - transient
        error = ServiceUnavailableError.new("Server error: HTTP #{status_code}", status_code: status_code)
        handle_transient_error(error, "Server error (#{status_code})", history, attempt)
      else
        # Unknown status code - treat as transient
        error = ConnectionError.new("HTTP #{status_code}: #{response.message}")
        handle_transient_error(error, "HTTP error (#{status_code})", history, attempt)
      end
    end

    # Handle transient errors with retry logic
    def handle_transient_error(error, error_type, history, attempt)
      if attempt < MAX_RETRIES
        sleep_time = backoff_time(attempt)
        Rails.logger.warn "GotifyNotificationService: #{error_type} - Retry #{attempt}/#{MAX_RETRIES} after #{sleep_time}s: #{error.message}"
        sleep sleep_time
        send_with_retry(history, attempt + 1)
      else
        error_msg = "#{error_type} after #{MAX_RETRIES} attempts: #{error.message}"
        history.mark_failed!(error_msg)
        Rails.logger.error "GotifyNotificationService: #{error_msg}"
        raise error
      end
    end

    # Calculate exponential backoff time
    def backoff_time(attempt)
      [2**attempt, 30].min
    end

    # HTTP headers for Gotify API
    def headers
      {
        'Content-Type' => 'application/json',
        'X-Gotify-Key' => app_token
      }
    end

    # Convert CVE severity to Gotify priority
    def severity_to_priority(severity)
      case severity.to_s.upcase
      when 'CRITICAL'
        NotificationHistory::PRIORITY_CRITICAL
      when 'HIGH'
        NotificationHistory::PRIORITY_HIGH
      when 'MEDIUM'
        NotificationHistory::PRIORITY_NORMAL
      when 'LOW'
        NotificationHistory::PRIORITY_LOW
      else
        NotificationHistory::PRIORITY_NORMAL
      end
    end

    # Build server event message with Markdown formatting
    def build_server_message(server, event, details)
      message = []
      message << "**Server:** #{server.hostname}"
      message << "**IP Address:** #{server.ip_address}" if server.ip_address.present?
      message << "**Environment:** #{server.environment}" if server.environment.present?
      message << "**Status:** #{event.to_s.upcase}"
      message << "\n#{details}" if details.present?

      message.join("\n")
    end

    # Build CVE alert message with enhanced formatting
    def build_cve_message(alert)
      message = []

      # Header with severity level
      message << "**[#{alert.severity}] #{alert.cve_id}**"

      # CISA KEV Badge
      if alert.is_exploited
        message << "**[CISA KEV] KNOWN EXPLOITED VULNERABILITY**"
      end

      # Separator
      message << "---"

      # Server/Product Information
      if alert.server.present?
        message << "**Server:** #{alert.server.hostname}"
      end

      if alert.cve_watchlist.present?
        watchlist = alert.cve_watchlist
        message << "**Product:** #{watchlist.vendor}/#{watchlist.product}" + (watchlist.version.present? ? " #{watchlist.version}" : "")
      end

      # CVSS Score with visual indicator
      if alert.cvss_score.present?
        cvss_bar = cvss_visual_indicator(alert.cvss_score)
        cvss_rating = cvss_severity_rating(alert.cvss_score)
        message << "**CVSS Score:** #{alert.cvss_score}/10.0 (#{cvss_rating}) #{cvss_bar}"
        message << "**CVSS Vector:** `#{alert.cvss_vector}`" if alert.cvss_vector.present?
      end

      # EPSS Score (Exploit Prediction Scoring System)
      if alert.epss_score.present?
        epss_percentage = (alert.epss_score.to_f * 100).round(2)
        epss_risk = epss_risk_level(alert.epss_score.to_f)
        message << "**EPSS Score:** #{epss_percentage}% (#{epss_risk})"
        message << "_Exploit prediction: likelihood of exploitation in next 30 days_"
      end

      # Description
      message << "\n**Description:**"
      message << alert.description.to_s.truncate(400)

      # Solution if available
      if alert.solution.present?
        message << "\n**Remediation:**"
        message << alert.solution.to_s.truncate(200)
      end

      # Published date
      if alert.published_at.present?
        message << "\n**Published:** #{alert.published_at.strftime('%Y-%m-%d')}"
      end

      # Links
      message << "\n**References:**"
      message << "- [NVD Details](https://nvd.nist.gov/vuln/detail/#{alert.cve_id})"

      if alert.cve_id.present?
        cve_year = alert.cve_id.match(/CVE-(\d{4})/)[1] rescue nil
        if cve_year
          message << "- [MITRE CVE](https://cve.mitre.org/cgi-bin/cvename.cgi?name=#{alert.cve_id})"
        end
      end

      message.join("\n")
    end

    # Create visual indicator for CVSS score
    def cvss_visual_indicator(score)
      normalized = (score.to_f / 10.0 * 10).round
      filled = '█' * normalized
      empty = '░' * (10 - normalized)
      "[#{filled}#{empty}]"
    end

    # Get CVSS severity rating
    def cvss_severity_rating(score)
      case score.to_f
      when 0.0...4.0
        "Low"
      when 4.0...7.0
        "Medium"
      when 7.0...9.0
        "High"
      else
        "Critical"
      end
    end

    # Get EPSS risk level
    def epss_risk_level(epss_score)
      case epss_score
      when 0.0...0.1
        "Low Risk"
      when 0.1...0.3
        "Medium Risk"
      when 0.3...0.6
        "High Risk"
      else
        "Very High Risk"
      end
    end

    # Build task execution message
    def build_task_message(task_execution)
      task = task_execution.scheduled_task
      message = []
      message << "**Task:** #{task.name}"
      message << "**Status:** #{task_execution.status.upcase}"
      message << "**Duration:** #{task_execution.duration_seconds}s" if task_execution.duration_seconds
      message << "**Success Count:** #{task_execution.success_count}"
      message << "**Failure Count:** #{task_execution.failure_count}" if task_execution.failure_count > 0

      if task_execution.summary.present?
        message << "\n#{task_execution.summary}"
      end

      message.join("\n")
    end

    # Build backup status message
    def build_backup_message(backup_history)
      message = []
      message << "**Backup:** #{backup_history.backup_name}"
      message << "**Status:** #{backup_history.status.upcase}"

      if backup_history.status == 'completed'
        message << "**Duration:** #{backup_history.duration_seconds}s"

        if backup_history.deduplicated_size
          size_mb = (backup_history.deduplicated_size.to_f / 1024 / 1024).round(2)
          message << "**Size:** #{size_mb} MB"
        end

        if backup_history.files_count
          message << "**Files:** #{backup_history.files_count}"
        end
      elsif backup_history.status == 'failed'
        message << "\n**Error:** #{backup_history.error_message}"
      end

      message.join("\n")
    end

    # Build user event message
    def build_user_message(user, event, details)
      message = []
      message << "**User:** #{user.email}"
      message << "**Name:** #{user.name}" if user.name.present?
      message << "**Role:** #{user.role}"
      message << "**Event:** #{event.to_s.humanize}"
      message << "\n#{details}" if details.present?

      message.join("\n")
    end

    # Check rate limit using Redis-based rate limiter
    # Falls back to database-based check if Redis is unavailable
    def check_rate_limit_redis!
      # Use Redis-based rate limiter for global rate limiting
      result = RateLimiter.check_limit!(:global)

      # Log rate limit status for monitoring
      if result[:remaining] < 10
        Rails.logger.warn "GotifyNotificationService: Rate limit warning - #{result[:remaining]} requests remaining"
      end
    rescue RateLimiter::RateLimitError => e
      # Rate limit exceeded - convert to our error type and raise
      Rails.logger.error "GotifyNotificationService: #{e.message}"
      raise RateLimitError, e.message
    rescue StandardError => e
      # If Redis fails, fall back to database check
      Rails.logger.warn "GotifyNotificationService: Rate limiter error, falling back to database: #{e.message}"
      check_rate_limit_database!
    end

    # Database-based rate limit check (fallback only)
    # This is the original implementation, kept as a fallback
    def check_rate_limit_database!
      recent_count = NotificationHistory.where('created_at >= ?', 1.minute.ago).count

      if recent_count >= RATE_LIMIT
        raise RateLimitError, "Rate limit exceeded: #{recent_count} notifications in the last minute (database fallback)"
      end
    end
  end
end
