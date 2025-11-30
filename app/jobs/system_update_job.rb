# frozen_string_literal: true

# Background job for checking and applying system updates
# Delegates to SystemUpdateWorkflowJob for detailed step tracking
class SystemUpdateJob < ApplicationJob
  queue_as :default

  # Retry configuration for Salt API issues
  retry_on SaltService::ConnectionError, wait: 30.seconds, attempts: 2
  retry_on SaltService::AuthenticationError, wait: 1.minute, attempts: 2

  # @param apply_updates [Boolean] If true, applies updates. If false, only checks for available updates
  # @param security_only [Boolean] If true, only applies security updates
  # @param is_weekly_update [Boolean] If true, this is a weekly update (triggers Hetzner snapshots if enabled)
  def perform(apply_updates: false, security_only: false, is_weekly_update: false)
    start_time = Time.current
    action = apply_updates ? (security_only ? 'Security Updates' : 'Full System Updates') : 'Update Check'
    command_name = apply_updates ? (security_only ? 'security_updates' : 'full_updates') : 'check_updates'

    Rails.logger.info "SystemUpdateJob: Starting #{action} (weekly: #{is_weekly_update})"

    online_servers = Server.where(status: 'online')
    total_count = online_servers.count

    if total_count == 0
      Rails.logger.info "SystemUpdateJob: No online servers to update"
      return
    end

    success_count = 0
    error_count = 0

    # Process each server using SystemUpdateWorkflowJob for detailed tracking
    online_servers.find_each do |server|
      begin
        # Use the workflow job for detailed step tracking
        SystemUpdateWorkflowJob.perform_now(
          server_id: server.id,
          apply_updates: apply_updates,
          security_only: security_only,
          is_weekly_update: is_weekly_update
        )

        success_count += 1
        Rails.logger.info "SystemUpdateJob: ✓ #{server.hostname}"

      rescue StandardError => e
        error_count += 1
        error_msg = "#{action} failed: #{e.message}"
        Rails.logger.error "SystemUpdateJob: ✗ #{server.hostname}: #{error_msg}"

        # Create a failed command record for tracking
        Command.create!(
          server: server,
          command_type: 'system',
          command: command_name,
          arguments: {
            job: 'SystemUpdateJob',
            apply: apply_updates,
            security_only: security_only,
            is_weekly: is_weekly_update
          },
          status: 'failed',
          error_output: error_msg,
          exit_code: 1,
          started_at: start_time,
          completed_at: Time.current
        )
      end
    end

    summary = "#{action}: #{success_count}/#{total_count} servers successful"
    summary += ", #{error_count} errors" if error_count > 0
    Rails.logger.info "SystemUpdateJob: #{summary}"
  end
end
