# frozen_string_literal: true

require 'shellwords'

# Service for Hetzner Cloud snapshot operations
# Handles creating, waiting, listing, and deleting snapshots
class HetznerSnapshotService
  # Path to Python script
  SCRIPT_PATH = Rails.root.join('lib', 'scripts', 'hetzner_cloud.py').to_s

  # Default snapshot retention (keep last N snapshots)
  DEFAULT_KEEP_LAST = 3

  # Maximum wait time for snapshot creation (15 minutes)
  SNAPSHOT_TIMEOUT = 900

  class << self
    # Create a snapshot of a server
    def create_snapshot(server, description: nil)
      validate_server!(server)

      # Generate description if not provided
      description ||= generate_snapshot_description(server)

      result = execute_command('create_snapshot', server, description)

      if result[:success]
        create_command_record(server, 'create_snapshot', result, description)
      end

      result
    end

    # Wait for snapshot to complete
    def wait_for_snapshot(server, snapshot_id, timeout: SNAPSHOT_TIMEOUT)
      validate_server!(server)

      api_token = server.hetzner_api_key.api_token

      cmd_parts = [
        'python3',
        Shellwords.escape(SCRIPT_PATH),
        'wait_snapshot',
        Shellwords.escape(api_token),
        Shellwords.escape(snapshot_id.to_s),
        Shellwords.escape(timeout.to_s)
      ]
      cmd = cmd_parts.join(' ')

      Rails.logger.info "Waiting for snapshot #{snapshot_id} (timeout: #{timeout}s)..."

      output = `#{cmd} 2>&1`
      exit_code = $?.exitstatus

      if exit_code == 0
        parse_json_response(output)
      else
        {
          success: false,
          error: "Failed to wait for snapshot: #{output}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "HetznerSnapshotService wait error: #{e.message}"

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    # Create snapshot and wait for completion
    def create_and_wait(server, description: nil, timeout: SNAPSHOT_TIMEOUT)
      # Create snapshot (or detect existing in-progress snapshot)
      create_result = create_snapshot(server, description: description)

      unless create_result[:success]
        return create_result
      end

      snapshot_id = create_result[:data][:snapshot_id]
      already_in_progress = create_result[:data][:already_in_progress]

      if already_in_progress
        Rails.logger.info "Snapshot already in progress: #{snapshot_id}. Waiting for it to complete..."
      else
        Rails.logger.info "Snapshot #{snapshot_id} created, waiting for completion..."
      end

      # Wait for completion (whether new or existing)
      wait_result = wait_for_snapshot(server, snapshot_id, timeout: timeout)

      if wait_result[:success]
        if already_in_progress
          Rails.logger.info "Existing snapshot #{snapshot_id} completed successfully"
        else
          Rails.logger.info "Snapshot #{snapshot_id} completed successfully"
          create_command_record(server, 'snapshot_completed', wait_result, description)
        end
      else
        Rails.logger.error "Snapshot #{snapshot_id} failed: #{wait_result[:error]}"
      end

      wait_result
    end

    # List all snapshots for a server
    # Filters snapshots by server ID and hostname for accurate matching
    def list_snapshots(server)
      validate_server!(server)

      api_token = server.hetzner_api_key.api_token
      # Pass both hostname and server_id for better filtering
      # Python script will try: 1) server_id match, 2) hostname prefix, 3) show all
      cmd_parts = [
        'python3',
        Shellwords.escape(SCRIPT_PATH),
        'list_snapshots',
        Shellwords.escape(api_token),
        Shellwords.escape(server.hostname),
        Shellwords.escape(server.hetzner_server_id.to_s)
      ]
      cmd = cmd_parts.join(' ')

      output = `#{cmd} 2>&1`
      exit_code = $?.exitstatus

      if exit_code == 0
        parse_json_response(output)
      else
        {
          success: false,
          error: "Failed to list snapshots: #{output}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "HetznerSnapshotService list error: #{e.message}"

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    # Delete a specific snapshot
    def delete_snapshot(server, snapshot_id)
      validate_server!(server)

      api_token = server.hetzner_api_key.api_token

      cmd_parts = [
        'python3',
        Shellwords.escape(SCRIPT_PATH),
        'delete_snapshot',
        Shellwords.escape(api_token),
        Shellwords.escape(snapshot_id.to_s)
      ]
      cmd = cmd_parts.join(' ')

      output = `#{cmd} 2>&1`
      exit_code = $?.exitstatus

      if exit_code == 0
        result = parse_json_response(output)
        create_command_record(server, 'delete_snapshot', result, snapshot_id.to_s) if result[:success]
        result
      else
        {
          success: false,
          error: "Failed to delete snapshot: #{output}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "HetznerSnapshotService delete error: #{e.message}"

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    # Cleanup old snapshots, keeping only the most recent N
    def cleanup_old_snapshots(server, keep_last: DEFAULT_KEEP_LAST)
      validate_server!(server)

      Rails.logger.info "Cleaning up old snapshots for #{server.hostname} (keeping last #{keep_last})..."

      # List all snapshots
      list_result = list_snapshots(server)

      unless list_result[:success]
        Rails.logger.error "Failed to list snapshots for cleanup: #{list_result[:error]}"
        return list_result
      end

      snapshots = list_result[:data][:snapshots]

      return { success: true, data: { message: 'No snapshots to cleanup' } } if snapshots.empty?

      # Sort by creation date (newest first)
      sorted_snapshots = snapshots.sort_by { |s| s[:created] || '' }.reverse

      # Keep only the specified number
      snapshots_to_delete = sorted_snapshots.drop(keep_last)

      if snapshots_to_delete.empty?
        Rails.logger.info "No old snapshots to delete (#{snapshots.count} snapshots, keeping last #{keep_last})"
        return {
          success: true,
          data: {
            message: "No snapshots to delete (#{snapshots.count} total, keeping #{keep_last})",
            kept_count: snapshots.count
          }
        }
      end

      # Delete old snapshots
      deleted_count = 0
      errors = []

      snapshots_to_delete.each do |snapshot|
        Rails.logger.info "Deleting old snapshot: #{snapshot[:snapshot_id]} (#{snapshot[:description]})"

        delete_result = delete_snapshot(server, snapshot[:snapshot_id])

        if delete_result[:success]
          deleted_count += 1
        else
          errors << "Failed to delete #{snapshot[:snapshot_id]}: #{delete_result[:error]}"
        end
      end

      result = {
        success: errors.empty?,
        data: {
          total_snapshots: snapshots.count,
          kept: keep_last,
          deleted: deleted_count,
          errors: errors.presence
        }
      }

      create_command_record(server, 'cleanup_snapshots', result, "Deleted #{deleted_count} old snapshots")

      result
    end

    private

    # Execute Python script command with retry logic for transient errors
    def execute_command(command, server, *args, max_retries: 3)
      api_token = server.hetzner_api_key.api_token
      server_id = server.hetzner_server_id

      # Build command with properly escaped arguments
      cmd_parts = [
        'python3',
        Shellwords.escape(SCRIPT_PATH),
        Shellwords.escape(command),
        Shellwords.escape(api_token),
        Shellwords.escape(server_id.to_s),
        *args.map { |arg| Shellwords.escape(arg.to_s) }
      ]
      cmd = cmd_parts.join(' ')

      # Mark API key as used
      server.hetzner_api_key.mark_as_used!

      attempt = 0
      last_error = nil

      max_retries.times do |retry_count|
        attempt = retry_count + 1

        begin
          # Execute command
          output = `#{cmd} 2>&1`
          exit_code = $?.exitstatus

          if exit_code == 0
            return parse_json_response(output)
          else
            # Parse the error to determine if it's transient
            error_result = {
              success: false,
              error: "Script execution failed with exit code #{exit_code}: #{output}",
              timestamp: Time.current.iso8601
            }

            # Check if the error is rate limiting (429)
            if output.include?('429') || output.downcase.include?('rate limit')
              last_error = :rate_limit
              if attempt < max_retries
                sleep_time = calculate_rate_limit_backoff(attempt)
                Rails.logger.warn "HetznerSnapshotService: Rate limited (attempt #{attempt}/#{max_retries}), waiting #{sleep_time}s..."
                sleep sleep_time
                next
              end
            # Check for other transient errors
            elsif output.include?('503') || output.downcase.include?('service unavailable')
              last_error = :service_unavailable
              if attempt < max_retries
                sleep_time = [2**attempt, 30].min
                Rails.logger.warn "HetznerSnapshotService: Service unavailable (attempt #{attempt}/#{max_retries}), waiting #{sleep_time}s..."
                sleep sleep_time
                next
              end
            elsif output.include?('timeout') || output.downcase.include?('timed out')
              last_error = :timeout
              if attempt < max_retries
                sleep_time = 10
                Rails.logger.warn "HetznerSnapshotService: Timeout (attempt #{attempt}/#{max_retries}), waiting #{sleep_time}s..."
                sleep sleep_time
                next
              end
            end

            # Non-retryable error or retries exhausted
            return error_result
          end
        rescue StandardError => e
          last_error = :exception
          Rails.logger.error "HetznerSnapshotService error on attempt #{attempt}: #{e.message}"

          if attempt < max_retries
            sleep 5
            next
          end

          Rails.logger.error e.backtrace.join("\n")
          return {
            success: false,
            error: e.message,
            timestamp: Time.current.iso8601
          }
        end
      end

      # All retries exhausted
      {
        success: false,
        error: "Failed after #{max_retries} attempts (last error: #{last_error})",
        timestamp: Time.current.iso8601
      }
    end

    # Calculate backoff time for rate limiting with jitter
    def calculate_rate_limit_backoff(attempt)
      # Base backoff: 30s, 60s, 120s
      base = [30 * (2**(attempt - 1)), 120].min
      # Add jitter (±20%)
      jitter = rand(-0.2..0.2)
      (base * (1 + jitter)).to_i
    end

    # Parse JSON response from Python script
    def parse_json_response(output)
      JSON.parse(output, symbolize_names: true)
    rescue JSON::ParserError => e
      {
        success: false,
        error: "Failed to parse response: #{e.message}",
        raw_output: output,
        timestamp: Time.current.iso8601
      }
    end

    # Validate server has required Hetzner configuration
    def validate_server!(server)
      unless server.hetzner_server?
        raise ArgumentError, "Server #{server.hostname} is not configured as a Hetzner Cloud server"
      end

      unless server.can_use_hetzner_features?
        raise ArgumentError, "Server #{server.hostname} cannot use Hetzner features (API key disabled or missing)"
      end
    end

    # Generate snapshot description
    def generate_snapshot_description(server)
      timestamp = Time.current.strftime('%Y%m%d-%H%M%S')
      "#{server.hostname}-pre-update-#{timestamp}"
    end

    # Create command record for audit trail
    def create_command_record(server, command_type, result, extra_info = nil)
      output_text = []
      output_text << "Command: #{command_type.humanize}"
      output_text << "Info: #{extra_info}" if extra_info
      output_text << "Result: #{JSON.pretty_generate(result[:data])}" if result[:data]

      Command.create!(
        server: server,
        command_type: command_type,
        command: "Hetzner Snapshot: #{command_type.humanize}",
        status: result[:success] ? 'completed' : 'failed',
        output: output_text.join("\n"),
        error_output: result[:error],
        started_at: Time.current,
        completed_at: Time.current,
        duration_seconds: result[:data]&.[](:duration_seconds) || 0
      )
    rescue StandardError => e
      Rails.logger.error "Failed to create command record: #{e.message}"
    end
  end
end
