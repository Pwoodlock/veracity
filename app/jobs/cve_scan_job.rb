# frozen_string_literal: true

# Background job for scanning CVEs and checking watchlists
class CveScanJob < ApplicationJob
  queue_as :default

  # Retry configuration for transient API failures
  retry_on NetworkError, wait: :exponentially_longer, attempts: 3
  retry_on TimeoutError, wait: 30.seconds, attempts: 3
  retry_on RateLimitError, wait: 1.minute, attempts: 3
  retry_on ServiceUnavailableError, wait: :exponentially_longer, attempts: 4

  # Don't retry on permanent errors
  discard_on AuthenticationError
  discard_on AuthorizationError
  discard_on BadRequestError

  # Check all active watchlists for new vulnerabilities
  def perform(scope = 'all')
    Rails.logger.info "CveScanJob: Starting CVE scan (scope: #{scope})"

    case scope
    when 'all'
      scan_all_watchlists
    when 'server'
      # Called with a server_id
      server_id = arguments[1]
      scan_server(server_id)
    when 'watchlist'
      # Called with a watchlist_id
      watchlist_id = arguments[1]
      scan_watchlist(watchlist_id)
    else
      Rails.logger.error "CveScanJob: Unknown scope #{scope}"
    end
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    # Map to our custom TimeoutError for retry
    Rails.logger.error "CveScanJob: Timeout - #{e.message}"
    raise TimeoutError.new("CVE API timeout: #{e.message}", context: { scope: scope })
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
    # Map to our custom NetworkError for retry
    Rails.logger.error "CveScanJob: Network error - #{e.message}"
    raise NetworkError.new("CVE API connection failed: #{e.message}", context: { scope: scope })
  rescue SocketError => e
    # DNS errors
    Rails.logger.error "CveScanJob: DNS error - #{e.message}"
    raise NetworkError.new("DNS resolution failed: #{e.message}", context: { scope: scope })
  rescue StandardError => e
    Rails.logger.error "CveScanJob: Failed - #{e.class.name}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
    raise
  end

  private

  def scan_all_watchlists
    results = CveMonitoringService.check_all_watchlists

    # Log results
    Rails.logger.info "CveScanJob: Completed scanning all watchlists"
    Rails.logger.info "CveScanJob: Checked: #{results[:checked]}, New vulnerabilities: #{results[:new_vulnerabilities]}"

    if results[:errors].any?
      Rails.logger.error "CveScanJob: Errors encountered: #{results[:errors].to_json}"
    end

    # Send summary email if new critical vulnerabilities found
    send_summary_notification(results)

    results
  end

  def scan_server(server_id)
    server = Server.find(server_id)

    unless server.cve_scan_enabled?
      Rails.logger.info "CveScanJob: CVE scanning disabled for server #{server.hostname}"
      return
    end

    Rails.logger.info "CveScanJob: Scanning server #{server.hostname}"

    scan_history = CveMonitoringService.scan_server(server)

    Rails.logger.info "CveScanJob: Server scan completed - Found #{scan_history.new_vulnerabilities} new vulnerabilities"

    # Send notification if critical vulnerabilities found
    if server.critical_vulnerability_count > 0
      notify_critical_vulnerabilities(server)
    end

    scan_history
  end

  def scan_watchlist(watchlist_id)
    watchlist = CveWatchlist.find(watchlist_id)

    unless watchlist.active?
      Rails.logger.info "CveScanJob: Watchlist #{watchlist.display_name} is inactive"
      return
    end

    Rails.logger.info "CveScanJob: Scanning watchlist #{watchlist.display_name}"

    alerts = CveMonitoringService.check_watchlist(watchlist)

    Rails.logger.info "CveScanJob: Watchlist scan completed - Found #{alerts.size} new vulnerabilities"

    alerts
  end

  def send_summary_notification(results)
    return unless results[:new_vulnerabilities] > 0

    # Get all new alerts from last hour
    recent_alerts = VulnerabilityAlert.where(
      created_at: 1.hour.ago..Time.current
    ).includes(:server, :cve_watchlist)

    critical_count = recent_alerts.critical.count
    high_count = recent_alerts.high.count

    # Only send if there are critical or high severity alerts
    return unless critical_count > 0 || high_count > 0

    # Send to admins
    User.admin.find_each do |admin|
      CveAlertMailer.scan_summary(
        admin,
        results,
        recent_alerts
      ).deliver_later
    end
  end

  def notify_critical_vulnerabilities(server)
    critical_alerts = server.vulnerability_alerts.active.critical

    return unless critical_alerts.any?

    # Send notifications to admins and operators
    User.where(role: %w[admin operator]).find_each do |user|
      CveAlertMailer.server_critical_vulnerabilities(
        user,
        server,
        critical_alerts
      ).deliver_later
    end

    # Broadcast to dashboard
    ActionCable.server.broadcast(
      'dashboard_channel',
      {
        type: 'critical_vulnerabilities',
        server_id: server.id,
        server_name: server.hostname,
        count: critical_alerts.count,
        vulnerabilities: critical_alerts.limit(5).map do |alert|
          {
            cve_id: alert.cve_id,
            severity: alert.severity,
            cvss_score: alert.cvss_score,
            is_exploited: alert.is_exploited,
            description: alert.description&.truncate(150)
          }
        end
      }
    )
  end
end