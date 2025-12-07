# frozen_string_literal: true

class CveAlertMailer < ApplicationMailer
  # Send alert for critical vulnerabilities
  def critical_vulnerabilities(alerts)
    @alerts = alerts
    @grouped_alerts = alerts.group_by(&:server)

    subject = "[CRITICAL] #{alerts.size} new critical vulnerabilities detected"

    # Send to all admins and operators
    recipients = User.where(role: %w[admin operator]).pluck(:email)

    mail(
      to: recipients,
      subject: subject,
      priority: 'high',
      importance: 'high'
    )
  end

  # Send summary of CVE scan results
  def scan_summary(user, results, recent_alerts)
    @user = user
    @results = results
    @recent_alerts = recent_alerts
    @critical_count = recent_alerts.critical.count
    @high_count = recent_alerts.high.count
    @exploited_count = recent_alerts.exploited.count

    subject = "CVE Scan Summary: #{@results[:new_vulnerabilities]} new vulnerabilities found"

    mail(
      to: user.email,
      subject: subject
    )
  end

  # Send alert for server-specific critical vulnerabilities
  def server_critical_vulnerabilities(user, server, critical_alerts)
    @user = user
    @server = server
    @alerts = critical_alerts

    subject = "[CRITICAL] #{server.hostname}: #{critical_alerts.size} critical vulnerabilities"

    mail(
      to: user.email,
      subject: subject,
      priority: 'high',
      importance: 'high'
    )
  end

  # Daily digest of CVE alerts
  def daily_digest(user)
    @user = user
    @date = Date.current

    # Get alerts from last 24 hours
    @new_alerts = VulnerabilityAlert.where(created_at: 24.hours.ago..Time.current)
                                    .includes(:server, :cve_watchlist)

    # Group by severity
    @alerts_by_severity = @new_alerts.group_by(&:severity)

    # Get overdue alerts
    @overdue_alerts = VulnerabilityAlert.active.select(&:overdue?)

    # Get servers with most vulnerabilities
    @vulnerable_servers = Server.joins(:vulnerability_alerts)
                                .where(vulnerability_alerts: { status: %w[new acknowledged] })
                                .group('servers.id')
                                .order('COUNT(vulnerability_alerts.id) DESC')
                                .limit(5)
                                .select('servers.*, COUNT(vulnerability_alerts.id) as vuln_count')

    subject = "CVE Daily Digest - #{@date.strftime('%B %d, %Y')}"

    mail(
      to: user.email,
      subject: subject
    )
  end

  # Alert for newly exploited vulnerability (added to CISA KEV)
  def exploited_vulnerability_alert(alert)
    @alert = alert
    @server = alert.server

    subject = "[URGENT] Actively exploited vulnerability detected: #{alert.cve_id}"

    # Send to all admins immediately
    recipients = User.admin.pluck(:email)

    mail(
      to: recipients,
      subject: subject,
      priority: 'high',
      importance: 'high'
    )
  end

  # Weekly report
  def weekly_report(user)
    @user = user
    @week_start = 1.week.ago.beginning_of_day
    @week_end = Time.current

    # Stats for the week
    @new_alerts_count = VulnerabilityAlert.where(created_at: @week_start..@week_end).count
    @resolved_alerts_count = VulnerabilityAlert.where(
      resolved_at: @week_start..@week_end,
      status: 'patched'
    ).count

    # Current status
    @active_critical = VulnerabilityAlert.active.critical.count
    @active_high = VulnerabilityAlert.active.high.count
    @total_active = VulnerabilityAlert.active.count

    # Trending vulnerabilities
    @top_cves = VulnerabilityAlert.where(created_at: @week_start..@week_end)
                                  .group(:cve_id)
                                  .order('COUNT(*) DESC')
                                  .limit(10)
                                  .pluck(:cve_id, Arel.sql('COUNT(*) as count'))

    subject = "CVE Weekly Report - #{@week_start.strftime('%B %d')} to #{@week_end.strftime('%B %d, %Y')}"

    mail(
      to: user.email,
      subject: subject
    )
  end
end