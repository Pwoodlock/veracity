# frozen_string_literal: true

# Concern for broadcasting dashboard updates via Turbo Streams
# Include in background jobs that need to update dashboard
module DashboardBroadcaster
  extend ActiveSupport::Concern

  # Broadcast stats cards update
  def broadcast_stats_update
    Rails.logger.info "DashboardBroadcaster: Starting stats broadcast"
    stats_data = calculate_dashboard_stats
    Rails.logger.info "DashboardBroadcaster: Stats data: #{stats_data.inspect}"

    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "dashboard-stats",
      partial: "dashboard/stats",
      locals: stats_data
    )

    Rails.logger.info "DashboardBroadcaster: Stats broadcast completed successfully"
  rescue StandardError => e
    Rails.logger.error "DashboardBroadcaster: Failed to broadcast stats - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  # Broadcast failed commands
  def broadcast_failed_commands_update
    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "failed-commands-widget",
      partial: "dashboard/failed_commands",
      locals: { failed_updates: fetch_failed_commands }
    )
  rescue StandardError => e
    Rails.logger.error "DashboardBroadcaster: Failed to broadcast failed commands - #{e.message}"
  end

  private

  def calculate_dashboard_stats
    {
      total_servers: Server.count,
      online_servers: Server.where(status: 'online').count,
      offline_servers: Server.where(status: 'offline').count,
      total_groups: Group.count,
      ungrouped_servers: Server.where(group_id: nil).count,
      commands_today: Command.where('started_at > ?', 24.hours.ago).count,
      successful_commands: Command.where('started_at > ?', 24.hours.ago)
                                  .where(status: 'completed')
                                  .where('exit_code = 0 OR exit_code IS NULL')
                                  .count,
      failed_commands: Command.where('started_at > ?', 24.hours.ago)
                              .where(status: 'failed')
                              .count
    }
  end

  def fetch_failed_commands
    Command.includes(:server)
           .where('started_at > ?', 7.days.ago)
           .where(status: ['failed', 'timeout'])
           .order(started_at: :desc)
           .limit(10)
  end
end
