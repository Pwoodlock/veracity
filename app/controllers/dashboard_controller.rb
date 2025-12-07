class DashboardController < ApplicationController
  before_action :authenticate_user!

  # SECURITY: Authorization checks for system operations
  # Viewers: Can only view dashboard (index)
  # Operators & Admins: Can trigger system operations
  before_action :require_operator!, only: [:trigger_metrics_collection, :trigger_sync_minions, :trigger_check_updates, :trigger_security_updates, :trigger_full_updates, :execute_command, :clear_failed_commands]

  def index
    # Server statistics
    @total_servers = Server.count
    @online_servers = Server.where(status: 'online').count
    @offline_servers = Server.where(status: 'offline').count

    # N+1 Query Optimization: Preload server_metrics to avoid N+1 queries
    # in the server card partial which calls server.latest_metrics
    @servers = Server.with_latest_metrics.order(status: :asc, hostname: :asc).limit(50)

    # Group statistics
    @total_groups = Group.count
    @groups_with_servers = Group.with_servers.count
    @ungrouped_servers = Server.ungrouped.count
    @top_groups = Group.includes(:servers)
                       .ordered
                       .limit(5)

    # Command statistics
    @commands_today = Command.where('started_at > ?', 24.hours.ago).count
    @successful_commands = Command.where('started_at > ?', 24.hours.ago)
                                 .where(status: 'completed')
                                 .where('exit_code = 0 OR exit_code IS NULL')
                                 .count
    @failed_commands = Command.where('started_at > ?', 24.hours.ago)
                             .where(status: 'failed')
                             .count

    # Failed updates/commands with details (last 7 days)
    @failed_updates = Command
      .includes(:server)
      .where('started_at > ?', 7.days.ago)
      .where(status: ['failed', 'timeout'])
      .order(started_at: :desc)
      .limit(10)

    # Activity chart data (last 24 hours, grouped by hour with formatted labels)
    activity_raw = Command
      .where('started_at > ?', 24.hours.ago)
      .group_by_hour(:started_at, range: 24.hours.ago..Time.current)
      .count

    # Convert to simple labels (avoid time axis issues)
    @activity_chart_data = activity_raw.transform_keys { |time| time.strftime('%H:%M') }

    # Scheduled task info
    @next_daily_update = next_daily_run
    @next_weekly_update = next_weekly_run
    @last_metric_collection = ServerMetric.maximum(:collected_at)

    # Recent health checks (from commands with health check output)
    @recent_health_checks = Command
      .includes(:server)
      .where('started_at > ?', 24.hours.ago)
      .where(status: 'completed')
      .where("output LIKE '%=== Post-Reboot Health Check ===%'")
      .order(started_at: :desc)
      .limit(5)

    # Count servers by health status (from latest commands)
    # N+1 Query Optimization: Query health checks once instead of per-server iteration
    # Use a subquery to find latest health check per server, then filter for issues
    critical_server_ids = Command
      .select('DISTINCT ON (server_id) server_id, output')
      .where(server_id: @servers.map(&:id))
      .where("output LIKE '%Health Check%' OR output LIKE '%CRITICAL%'")
      .order('server_id, started_at DESC')
      .select { |cmd| cmd.output&.include?('CRITICAL') || cmd.output&.include?('❌') }
      .map(&:server_id)
    @servers_with_health_issues = critical_server_ids.count

    # Vulnerability alerts statistics
    active_alerts = VulnerabilityAlert.active
    @vulnerability_stats = {
      total: active_alerts.count,
      critical: active_alerts.where(severity: 'CRITICAL').count,
      high: active_alerts.where(severity: 'HIGH').count,
      medium: active_alerts.where(severity: 'MEDIUM').count,
      low: active_alerts.where(severity: %w[LOW INFO]).count,
      exploited: active_alerts.where(is_exploited: true).count
    }

    # Recent critical/high alerts for the dashboard card (limit 5)
    @recent_vulnerability_alerts = VulnerabilityAlert
      .includes(:server)
      .active
      .where(severity: %w[CRITICAL HIGH])
      .by_severity
      .order(published_at: :desc)
      .limit(5)

  end

  def execute_command
    server_id = params[:server_id]
    command = params[:command]
    command_type = params[:command_type] || 'shell'

    if server_id.blank? || command.blank?
      render json: { error: 'Server and command are required' }, status: :unprocessable_entity
      return
    end

    server = Server.find(server_id)

    # Parse command based on type
    salt_function, salt_args = if command_type == 'salt'
      # Salt module command (e.g., "disk.usage /", "grains.item os")
      parts = command.split(' ', 2)
      [parts[0], parts[1] ? [parts[1]] : []]
    else
      # Shell command
      ['cmd.run', [command]]
    end

    # Create command record with user tracking
    cmd_record = Command.create!(
      server: server,
      user: current_user,  # Track who executed the command
      command_type: command_type,
      command: salt_function,
      arguments: { args: salt_args },
      status: 'pending',
      started_at: Time.current
    )

    # Execute via Salt (using class method)
    result = SaltService.run_command(server.minion_id, salt_function, salt_args.presence)

    if result && result['return']
      output = result['return'].first[server.minion_id]

      if output.is_a?(Hash) && output['retcode']
        cmd_record.update!(
          status: output['retcode'] == 0 ? 'completed' : 'failed',
          output: output['stdout'] || output.to_json,
          error_output: output['stderr'],
          exit_code: output['retcode'],
          completed_at: Time.current
        )
      else
        cmd_record.update!(
          status: 'completed',
          output: output.to_s,
          exit_code: 0,
          completed_at: Time.current
        )
      end

      render json: {
        success: true,
        output: cmd_record.output,
        error: cmd_record.error_output,
        exit_code: cmd_record.exit_code,
        status: cmd_record.status
      }
    else
      cmd_record.update!(
        status: 'failed',
        error_output: 'No response from Salt',
        completed_at: Time.current
      )

      render json: { success: false, error: 'No response from Salt' }, status: :service_unavailable
    end
  rescue SaltService::ConnectionError => e
    # Timeout or connection errors
    cmd_record&.update(
      status: 'timeout',
      error_output: e.message,
      completed_at: Time.current
    )
    render json: {
      success: false,
      error: "Command timed out after 60 seconds. For long-running commands, consider using Salt's async job system.",
      details: e.message
    }, status: :gateway_timeout
  rescue StandardError => e
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # Manual trigger for scheduled tasks
  # NOTE: These use perform_now for immediate synchronous execution
  # This provides instant feedback and doesn't require Sidekiq to be running
  def trigger_metrics_collection
    begin
      # Execute metrics collection immediately (synchronous)
      CollectMetricsJob.perform_now  # Collects for all online servers
      online_count = Server.where(status: 'online').count

      flash[:success] = "✓ Metrics collected from #{online_count} online server(s)"
    rescue StandardError => e
      Rails.logger.error "Dashboard trigger_metrics_collection failed: #{e.message}"
      flash[:error] = "Failed to collect metrics: #{e.message}"
    end

    redirect_to dashboard_path
  end

  def trigger_sync_minions
    begin
      # Execute minion sync immediately (synchronous)
      SyncMinionsJob.perform_now

      flash[:success] = "✓ Server information synchronized successfully"
    rescue StandardError => e
      Rails.logger.error "Dashboard trigger_sync_minions failed: #{e.message}"
      flash[:error] = "Failed to sync servers: #{e.message}"
    end

    redirect_to dashboard_path
  end

  def trigger_check_updates
    begin
      # Check for available updates immediately (synchronous)
      SystemUpdateJob.perform_now(apply_updates: false, security_only: false)

      flash[:success] = "✓ Update check completed for all online servers"
    rescue StandardError => e
      Rails.logger.error "Dashboard trigger_check_updates failed: #{e.message}"
      flash[:error] = "Failed to check updates: #{e.message}"
    end

    redirect_to dashboard_path
  end

  def trigger_security_updates
    begin
      # Apply security updates immediately (synchronous)
      SystemUpdateJob.perform_now(apply_updates: true, security_only: true)

      flash[:success] = "✓ Security updates completed for all online servers"
    rescue StandardError => e
      Rails.logger.error "Dashboard trigger_security_updates failed: #{e.message}"
      flash[:error] = "Failed to apply security updates: #{e.message}"
    end

    redirect_to dashboard_path
  end

  def trigger_full_updates
    begin
      # Apply all available updates immediately (synchronous)
      SystemUpdateJob.perform_now(apply_updates: true, security_only: false)

      flash[:success] = "✓ Full system updates completed for all online servers"
    rescue StandardError => e
      Rails.logger.error "Dashboard trigger_full_updates failed: #{e.message}"
      flash[:error] = "Failed to apply system updates: #{e.message}"
    end

    redirect_to dashboard_path
  end

  def clear_failed_commands
    begin
      # Delete failed commands from last 7 days
      deleted_count = Command.where('started_at > ?', 7.days.ago)
                             .where(status: %w[failed timeout])
                             .delete_all

      flash[:success] = "✓ Cleared #{deleted_count} failed command#{deleted_count == 1 ? '' : 's'} from the last 7 days"
    rescue StandardError => e
      Rails.logger.error "Dashboard clear_failed_commands failed: #{e.message}"
      flash[:error] = "Failed to clear commands: #{e.message}"
    end

    redirect_to dashboard_path
  end

  private

  def next_daily_run
    now = Time.current
    next_run = now.change(hour: 2, min: 0)
    next_run += 1.day if now.hour >= 2
    next_run
  end

  def next_weekly_run
    now = Time.current
    days_until_sunday = (7 - now.wday) % 7
    days_until_sunday = 7 if days_until_sunday == 0 && now.hour >= 3
    (now + days_until_sunday.days).change(hour: 3, min: 0)
  end
end
