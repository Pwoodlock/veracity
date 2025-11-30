# frozen_string_literal: true

# Service for performing comprehensive health checks on servers
# Used primarily after reboots to verify system health
class HealthCheckService
  # Health check result statuses
  STATUS_HEALTHY = 'healthy'
  STATUS_WARNING = 'warning'
  STATUS_CRITICAL = 'critical'
  STATUS_UNKNOWN = 'unknown'

  # Thresholds for health checks
  DISK_WARNING_PERCENT = 80
  DISK_CRITICAL_PERCENT = 90
  MEMORY_WARNING_PERCENT = 85
  MEMORY_CRITICAL_PERCENT = 95
  LOAD_WARNING_MULTIPLIER = 2.0  # Load > (cores * 2) is warning
  LOAD_CRITICAL_MULTIPLIER = 4.0 # Load > (cores * 4) is critical
  UPTIME_RECENT_MINUTES = 15     # If uptime < 15 min, consider it a recent reboot

  class << self
    # Perform full health check on a server
    # @param server [Server] The server to check
    # @param post_reboot [Boolean] Whether this is a post-reboot check
    # @return [Hash] Health check results with status and details
    def check(server, post_reboot: false)
      Rails.logger.info("Starting health check for #{server.hostname} (post_reboot: #{post_reboot})")

      results = {
        server_id: server.id,
        hostname: server.hostname,
        checked_at: Time.current,
        post_reboot: post_reboot,
        overall_status: STATUS_UNKNOWN,
        checks: {},
        summary: '',
        issues: [],
        metadata: {}
      }

      # Run individual health checks
      results[:checks][:connectivity] = check_connectivity(server)
      results[:checks][:uptime] = check_uptime(server, post_reboot)
      results[:checks][:disk] = check_disk_space(server)
      results[:checks][:memory] = check_memory(server)
      results[:checks][:load] = check_load_average(server)
      results[:checks][:minion_service] = check_minion_service(server)

      # Determine overall status
      results[:overall_status] = calculate_overall_status(results[:checks])
      results[:issues] = collect_issues(results[:checks])
      results[:summary] = generate_summary(results)

      # Store metadata
      results[:metadata][:checks_performed] = results[:checks].size
      results[:metadata][:failed_checks] = results[:checks].count { |_k, v| v[:status] == STATUS_CRITICAL }
      results[:metadata][:warning_checks] = results[:checks].count { |_k, v| v[:status] == STATUS_WARNING }

      Rails.logger.info("Health check completed for #{server.hostname}: #{results[:overall_status]}")

      results
    rescue StandardError => e
      Rails.logger.error("Health check failed for #{server.hostname}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      {
        server_id: server.id,
        hostname: server.hostname,
        checked_at: Time.current,
        overall_status: STATUS_UNKNOWN,
        checks: {},
        summary: "Health check failed: #{e.message}",
        issues: ["Error performing health check: #{e.message}"],
        metadata: { error: e.message }
      }
    end

    # Format health check results as human-readable text
    # @param results [Hash] Results from check() method
    # @return [String] Formatted health report
    def format_report(results)
      lines = []
      lines << "=" * 70
      lines << "HEALTH CHECK REPORT: #{results[:hostname]}"
      lines << "=" * 70
      lines << "Checked at: #{results[:checked_at].strftime('%Y-%m-%d %H:%M:%S')}"
      lines << "Overall Status: #{status_icon(results[:overall_status])} #{results[:overall_status].upcase}"
      lines << ""

      # Individual check results
      lines << "DETAILED RESULTS:"
      lines << "-" * 70

      results[:checks].each do |check_name, check_result|
        icon = status_icon(check_result[:status])
        lines << "\n#{icon} #{check_name.to_s.titleize}"
        lines << "   Status: #{check_result[:status]}"
        lines << "   #{check_result[:message]}" if check_result[:message].present?

        if check_result[:details].present?
          check_result[:details].each do |key, value|
            lines << "   #{key}: #{value}"
          end
        end
      end

      # Issues summary
      if results[:issues].any?
        lines << ""
        lines << "ISSUES FOUND:"
        lines << "-" * 70
        results[:issues].each do |issue|
          lines << "  ⚠️  #{issue}"
        end
      end

      # Summary
      lines << ""
      lines << "SUMMARY:"
      lines << "-" * 70
      lines << results[:summary]
      lines << "=" * 70

      lines.join("\n")
    end

    private

    # Check if server is reachable via Salt
    def check_connectivity(server)
      result = SaltService.ping_minion(server.minion_id)

      if result[:success] && result[:data] == true
        {
          status: STATUS_HEALTHY,
          message: "Minion responding",
          details: { response_time: result[:response_time] }
        }
      else
        {
          status: STATUS_CRITICAL,
          message: "Minion not responding",
          details: { error: result[:error] }
        }
      end
    rescue StandardError => e
      {
        status: STATUS_CRITICAL,
        message: "Connectivity check failed: #{e.message}",
        details: {}
      }
    end

    # Check system uptime
    def check_uptime(server, post_reboot)
      result = SaltService.run_command(server.minion_id, 'status.uptime', [])

      if result[:success]
        uptime_seconds = result[:data].to_i
        uptime_minutes = uptime_seconds / 60

        status = if post_reboot && uptime_minutes > UPTIME_RECENT_MINUTES
                   STATUS_WARNING # Expected recent reboot but uptime is old
                 else
                   STATUS_HEALTHY
                 end

        {
          status: status,
          message: format_uptime(uptime_seconds),
          details: {
            uptime_seconds: uptime_seconds,
            uptime_human: format_uptime(uptime_seconds),
            recent_reboot: uptime_minutes < UPTIME_RECENT_MINUTES
          }
        }
      else
        {
          status: STATUS_WARNING,
          message: "Could not determine uptime",
          details: { error: result[:error] }
        }
      end
    rescue StandardError => e
      {
        status: STATUS_WARNING,
        message: "Uptime check failed: #{e.message}",
        details: {}
      }
    end

    # Check disk space
    def check_disk_space(server)
      result = SaltService.run_command(server.minion_id, 'disk.usage', [])

      if result[:success] && result[:data].is_a?(Hash)
        disk_data = result[:data]
        issues = []
        max_usage = 0

        disk_data.each do |mount_point, usage|
          next unless usage.is_a?(Hash) && usage['capacity'].present?

          capacity_str = usage['capacity'].to_s.gsub('%', '')
          capacity = capacity_str.to_f
          max_usage = capacity if capacity > max_usage

          if capacity >= DISK_CRITICAL_PERCENT
            issues << "#{mount_point}: #{capacity}% (CRITICAL)"
          elsif capacity >= DISK_WARNING_PERCENT
            issues << "#{mount_point}: #{capacity}% (WARNING)"
          end
        end

        status = if issues.any? { |i| i.include?('CRITICAL') }
                   STATUS_CRITICAL
                 elsif issues.any? { |i| i.include?('WARNING') }
                   STATUS_WARNING
                 else
                   STATUS_HEALTHY
                 end

        {
          status: status,
          message: issues.any? ? issues.join('; ') : "All disks healthy (max: #{max_usage.round(1)}%)",
          details: { max_usage_percent: max_usage, disk_data: disk_data }
        }
      else
        {
          status: STATUS_WARNING,
          message: "Could not check disk space",
          details: { error: result[:error] }
        }
      end
    rescue StandardError => e
      {
        status: STATUS_WARNING,
        message: "Disk check failed: #{e.message}",
        details: {}
      }
    end

    # Check memory usage
    def check_memory(server)
      result = SaltService.run_command(server.minion_id, 'status.meminfo', [])

      if result[:success] && result[:data].is_a?(Hash)
        mem_data = result[:data]
        total = mem_data['MemTotal'].to_i
        available = mem_data['MemAvailable']&.to_i || mem_data['MemFree'].to_i
        used = total - available
        usage_percent = (used.to_f / total * 100).round(1)

        status = if usage_percent >= MEMORY_CRITICAL_PERCENT
                   STATUS_CRITICAL
                 elsif usage_percent >= MEMORY_WARNING_PERCENT
                   STATUS_WARNING
                 else
                   STATUS_HEALTHY
                 end

        {
          status: status,
          message: "Memory usage: #{usage_percent}%",
          details: {
            total_mb: (total / 1024).round(1),
            used_mb: (used / 1024).round(1),
            available_mb: (available / 1024).round(1),
            usage_percent: usage_percent
          }
        }
      else
        {
          status: STATUS_WARNING,
          message: "Could not check memory",
          details: { error: result[:error] }
        }
      end
    rescue StandardError => e
      {
        status: STATUS_WARNING,
        message: "Memory check failed: #{e.message}",
        details: {}
      }
    end

    # Check load average
    def check_load_average(server)
      result = SaltService.run_command(server.minion_id, 'status.loadavg', [])

      if result[:success] && result[:data].is_a?(Hash)
        load_1 = result[:data]['1-min'].to_f
        load_5 = result[:data]['5-min'].to_f
        load_15 = result[:data]['15-min'].to_f

        # Get CPU count
        cpu_count = server.cpu_cores || 1
        warning_threshold = cpu_count * LOAD_WARNING_MULTIPLIER
        critical_threshold = cpu_count * LOAD_CRITICAL_MULTIPLIER

        status = if load_1 >= critical_threshold
                   STATUS_CRITICAL
                 elsif load_1 >= warning_threshold
                   STATUS_WARNING
                 else
                   STATUS_HEALTHY
                 end

        {
          status: status,
          message: "Load: #{load_1}, #{load_5}, #{load_15} (#{cpu_count} cores)",
          details: {
            load_1min: load_1,
            load_5min: load_5,
            load_15min: load_15,
            cpu_cores: cpu_count,
            load_per_core: (load_1 / cpu_count).round(2)
          }
        }
      else
        {
          status: STATUS_WARNING,
          message: "Could not check load average",
          details: { error: result[:error] }
        }
      end
    rescue StandardError => e
      {
        status: STATUS_WARNING,
        message: "Load check failed: #{e.message}",
        details: {}
      }
    end

    # Check Salt minion service status
    def check_minion_service(server)
      result = SaltService.run_command(server.minion_id, 'service.status', ['salt-minion'])

      if result[:success]
        service_running = result[:data] == true || result[:data].to_s.downcase.include?('running')

        if service_running
          {
            status: STATUS_HEALTHY,
            message: "Salt minion service is running",
            details: { running: true }
          }
        else
          {
            status: STATUS_CRITICAL,
            message: "Salt minion service is not running",
            details: { running: false }
          }
        end
      else
        {
          status: STATUS_WARNING,
          message: "Could not check minion service status",
          details: { error: result[:error] }
        }
      end
    rescue StandardError => e
      {
        status: STATUS_WARNING,
        message: "Service check failed: #{e.message}",
        details: {}
      }
    end

    # Calculate overall status from individual checks
    def calculate_overall_status(checks)
      statuses = checks.values.map { |check| check[:status] }

      if statuses.include?(STATUS_CRITICAL)
        STATUS_CRITICAL
      elsif statuses.include?(STATUS_WARNING)
        STATUS_WARNING
      elsif statuses.all? { |s| s == STATUS_HEALTHY }
        STATUS_HEALTHY
      else
        STATUS_UNKNOWN
      end
    end

    # Collect all issues from checks
    def collect_issues(checks)
      issues = []

      checks.each do |check_name, check_result|
        next if check_result[:status] == STATUS_HEALTHY

        severity = check_result[:status] == STATUS_CRITICAL ? 'CRITICAL' : 'WARNING'
        issues << "[#{severity}] #{check_name.to_s.titleize}: #{check_result[:message]}"
      end

      issues
    end

    # Generate summary message
    def generate_summary(results)
      status_counts = results[:checks].values.group_by { |check| check[:status] }
                                      .transform_values(&:count)

      healthy = status_counts[STATUS_HEALTHY] || 0
      warnings = status_counts[STATUS_WARNING] || 0
      critical = status_counts[STATUS_CRITICAL] || 0
      total = results[:checks].size

      summary_parts = []
      summary_parts << "#{healthy}/#{total} checks passed"
      summary_parts << "#{warnings} warnings" if warnings > 0
      summary_parts << "#{critical} critical issues" if critical > 0

      if results[:post_reboot]
        uptime_check = results[:checks][:uptime]
        if uptime_check && uptime_check[:details][:recent_reboot]
          summary_parts << "(recent reboot confirmed)"
        end
      end

      summary_parts.join(', ')
    end

    # Get icon for status
    def status_icon(status)
      case status
      when STATUS_HEALTHY then '✅'
      when STATUS_WARNING then '⚠️'
      when STATUS_CRITICAL then '❌'
      else '❓'
      end
    end

    # Format uptime seconds to human-readable
    def format_uptime(seconds)
      days = seconds / 86400
      hours = (seconds % 86400) / 3600
      minutes = (seconds % 3600) / 60

      parts = []
      parts << "#{days}d" if days > 0
      parts << "#{hours}h" if hours > 0 || days > 0
      parts << "#{minutes}m" if minutes > 0 || (hours == 0 && days == 0)

      parts.join(' ')
    end
  end
end
