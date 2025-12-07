# frozen_string_literal: true

# Workflow job for system updates with multi-level execution
# Handles conditional logic like Hetzner snapshots before updates
class SystemUpdateWorkflowJob < ApplicationJob
  queue_as :default

  # Retry configuration
  retry_on StandardError, wait: 1.minute, attempts: 2

  # @param server_id [String] UUID of the server to update
  # @param apply_updates [Boolean] If true, applies updates. If false, only checks
  # @param security_only [Boolean] If true, only applies security updates
  # @param is_weekly_update [Boolean] If true, triggers Hetzner snapshots if enabled
  def perform(server_id:, apply_updates: false, security_only: false, is_weekly_update: false)
    @server = Server.find(server_id)
    @apply_updates = apply_updates
    @security_only = security_only
    @is_weekly_update = is_weekly_update
    @start_time = Time.current

    Rails.logger.info "SystemUpdateWorkflow: Starting for #{@server.hostname} (weekly: #{is_weekly_update})"

    # Step 1: Pre-update actions (snapshots, backups, etc.)
    execute_pre_update_steps

    # Step 2: Execute the update command
    execute_update_command

    # Step 3: Post-update actions (cleanup, verification, etc.)
    execute_post_update_steps

    Rails.logger.info "SystemUpdateWorkflow: Completed for #{@server.hostname}"

  rescue StandardError => e
    Rails.logger.error "SystemUpdateWorkflow: Failed for #{@server.hostname}: #{e.message}"
    create_error_command(e)
    raise # Re-raise to trigger retry logic
  end

  private

  def execute_pre_update_steps
    # Check if server needs Hetzner snapshot before update
    if should_create_hetzner_snapshot?
      Rails.logger.info "SystemUpdateWorkflow: Creating Hetzner snapshot for #{@server.hostname}"
      create_hetzner_snapshot
    end

    # Check if server needs Proxmox snapshot before update
    if should_create_proxmox_snapshot?
      Rails.logger.info "SystemUpdateWorkflow: Creating Proxmox snapshot for #{@server.hostname}"
      create_proxmox_snapshot
    end
  end

  def execute_update_command
    return unless @apply_updates # Only execute if we're actually applying updates

    command = build_update_command
    Rails.logger.info "SystemUpdateWorkflow: Executing update command for #{@server.hostname}: #{command}"

    # Execute via Salt
    result = execute_salt_command(command)

    # Create command record for audit trail
    create_command_record(command, result)

    unless result[:success]
      raise "Update command failed: #{result[:error]}"
    end
  end

  def execute_post_update_steps
    # Cleanup old Hetzner snapshots if we created one
    if should_create_hetzner_snapshot? && @hetzner_snapshot_created
      cleanup_old_hetzner_snapshots
    end

    # Cleanup old Proxmox snapshots if we created one
    if should_create_proxmox_snapshot? && @proxmox_snapshot_created
      cleanup_old_proxmox_snapshots
    end
  end

  # Conditional logic: should we create a Hetzner snapshot?
  def should_create_hetzner_snapshot?
    return false unless @apply_updates # Only for actual updates, not checks
    return false unless @is_weekly_update # Only for weekly updates

    @server.snapshot_before_update? # Uses existing Server model method
  end

  # Conditional logic: should we create a Proxmox snapshot?
  def should_create_proxmox_snapshot?
    return false unless @apply_updates
    return false unless @is_weekly_update

    # Add Proxmox snapshot logic if needed
    # For now, return false (can be extended later)
    false
  end

  def create_hetzner_snapshot
    hetzner_service = HetznerSnapshotService.new(@server)

    # Create snapshot and wait for completion
    result = hetzner_service.create_and_wait(
      description: "Pre-update snapshot (#{Date.current})",
      timeout: 900 # 15 minutes
    )

    if result[:success]
      @hetzner_snapshot_created = true
      @hetzner_snapshot_id = result[:snapshot_id]
      Rails.logger.info "SystemUpdateWorkflow: Hetzner snapshot created: #{@hetzner_snapshot_id}"
    else
      # Snapshot failed - abort the update
      raise "Hetzner snapshot failed: #{result[:error]}"
    end
  end

  def create_proxmox_snapshot
    # Placeholder for Proxmox snapshot logic
    # Will be implemented when Proxmox snapshot service is built
    Rails.logger.info "SystemUpdateWorkflow: Proxmox snapshot would be created here"
    @proxmox_snapshot_created = false
  end

  def cleanup_old_hetzner_snapshots
    return unless @hetzner_snapshot_created

    Rails.logger.info "SystemUpdateWorkflow: Cleaning up old Hetzner snapshots for #{@server.hostname}"

    hetzner_service = HetznerSnapshotService.new(@server)
    result = hetzner_service.cleanup_old_snapshots(keep_last: 3)

    if result[:success]
      deleted = result[:deleted_count] || 0
      Rails.logger.info "SystemUpdateWorkflow: Cleaned up #{deleted} old snapshot(s)"
    else
      # Log but don't fail the job if cleanup fails
      Rails.logger.warn "SystemUpdateWorkflow: Snapshot cleanup failed: #{result[:error]}"
    end
  end

  def cleanup_old_proxmox_snapshots
    # Placeholder for Proxmox cleanup
    Rails.logger.info "SystemUpdateWorkflow: Proxmox snapshot cleanup would happen here"
  end

  def build_update_command
    if @security_only
      # Security updates only
      'pkg.upgrade dist_upgrade=False refresh=True only_upgrade=True'
    else
      # Full system update
      'pkg.upgrade dist_upgrade=True refresh=True'
    end
  end

  def execute_salt_command(command)
    require 'open3'

    # Build Salt command targeting this specific server
    salt_cmd = "sudo salt '#{@server.minion_id}' #{command} --output=json"

    Rails.logger.debug "SystemUpdateWorkflow: Executing: #{salt_cmd}"

    stdout, stderr, status = Open3.capture3(salt_cmd)

    if status.success?
      {
        success: true,
        output: stdout,
        parsed: parse_salt_output(stdout)
      }
    else
      {
        success: false,
        error: stderr.presence || stdout,
        output: stdout
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: "Execution error: #{e.message}",
      output: nil
    }
  end

  def parse_salt_output(output)
    JSON.parse(output)
  rescue JSON::ParserError
    output
  end

  def create_command_record(command, result)
    Command.create!(
      server: @server,
      command_type: 'system',
      command: @security_only ? 'security_updates' : 'full_updates',
      arguments: {
        job: 'SystemUpdateWorkflowJob',
        apply: @apply_updates,
        security_only: @security_only,
        is_weekly: @is_weekly_update,
        salt_command: command,
        snapshot_created: @hetzner_snapshot_created || @proxmox_snapshot_created || false,
        snapshot_id: @hetzner_snapshot_id
      },
      status: result[:success] ? 'completed' : 'failed',
      output: result[:parsed].to_s,
      error_output: result[:error],
      exit_code: result[:success] ? 0 : 1,
      started_at: @start_time,
      completed_at: Time.current
    )
  end

  def create_error_command(exception)
    Command.create!(
      server: @server,
      command_type: 'system',
      command: @security_only ? 'security_updates' : 'full_updates',
      arguments: {
        job: 'SystemUpdateWorkflowJob',
        apply: @apply_updates,
        security_only: @security_only,
        is_weekly: @is_weekly_update,
        error: exception.class.name
      },
      status: 'failed',
      error_output: "#{exception.message}\n#{exception.backtrace.first(5).join("\n")}",
      exit_code: 1,
      started_at: @start_time,
      completed_at: Time.current
    )
  end
end
