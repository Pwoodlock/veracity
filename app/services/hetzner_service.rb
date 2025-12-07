# frozen_string_literal: true

# Service for Hetzner Cloud server control operations
# Handles starting, stopping, rebooting, and status checks via hcloud Python library
class HetznerService
  # Path to Python script
  SCRIPT_PATH = Rails.root.join('lib', 'scripts', 'hetzner_cloud.py').to_s

  class << self
    # Start a Hetzner Cloud server
    def start_server(server)
      validate_server!(server)

      result = execute_command('start', server)

      if result[:success]
        server.update(
          hetzner_power_state: 'running',
          status: 'online',
          last_seen: Time.current
        )
        create_command_record(server, 'start_server', result)
      end

      result
    end

    # Stop a Hetzner Cloud server
    def stop_server(server)
      validate_server!(server)

      result = execute_command('stop', server)

      if result[:success]
        server.update(
          hetzner_power_state: 'off',
          status: 'offline'
        )
        create_command_record(server, 'stop_server', result)
      end

      result
    end

    # Reboot a Hetzner Cloud server
    def reboot_server(server)
      validate_server!(server)

      result = execute_command('reboot', server)

      if result[:success]
        server.update(
          hetzner_power_state: 'rebooting'
        )
        create_command_record(server, 'reboot_server', result)
      end

      result
    end

    # Get current server status
    def get_server_status(server)
      validate_server!(server)

      result = execute_command('status', server)

      if result[:success] && result[:data]
        # Update server record with latest status
        server.update(
          hetzner_power_state: result[:data]['status'],
          status: power_state_to_server_status(result[:data]['status']),
          last_seen: Time.current
        )
      end

      result
    end

    # Refresh server info from Hetzner API
    def refresh_server_info(server)
      result = get_server_status(server)

      if result[:success] && result[:data]
        create_command_record(server, 'refresh_hetzner_info', result)
      end

      result
    end

    # List all servers in a Hetzner Cloud project
    # Takes a HetznerApiKey object and returns list of servers
    def list_servers(api_key)
      unless api_key.is_a?(HetznerApiKey)
        raise ArgumentError, "Expected HetznerApiKey, got #{api_key.class}"
      end

      unless api_key.enabled?
        return {
          success: false,
          error: "API key '#{api_key.name}' is disabled",
          timestamp: Time.current.iso8601
        }
      end

      cmd = "python3 #{SCRIPT_PATH} list_servers #{api_key.api_token}"

      # Mark API key as used
      api_key.mark_as_used!

      # Execute command
      output = `#{cmd} 2>&1`
      exit_code = $?.exitstatus

      if exit_code == 0
        parse_json_response(output)
      else
        {
          success: false,
          error: "Failed to list servers: #{output}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "HetznerService list_servers error: #{e.message}"

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    private

    # Execute Python script command
    def execute_command(command, server)
      api_token = server.hetzner_api_key.api_token
      server_id = server.hetzner_server_id

      cmd = "python3 #{SCRIPT_PATH} #{command} #{api_token} #{server_id}"

      # Mark API key as used
      server.hetzner_api_key.mark_as_used!

      # Execute command
      output = `#{cmd} 2>&1`
      exit_code = $?.exitstatus

      if exit_code == 0
        parse_json_response(output)
      else
        {
          success: false,
          error: "Script execution failed with exit code #{exit_code}: #{output}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "HetznerService error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
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

    # Convert Hetzner power state to server status
    def power_state_to_server_status(power_state)
      case power_state
      when 'running'
        'online'
      when 'off', 'stopped'
        'offline'
      when 'starting', 'stopping', 'rebooting'
        'maintenance'
      else
        'unreachable'
      end
    end

    # Create command record for audit trail
    def create_command_record(server, command_type, result)
      Command.create!(
        server: server,
        command_type: command_type,
        command: "Hetzner Cloud: #{command_type.humanize}",
        status: result[:success] ? 'completed' : 'failed',
        output: result[:data] ? JSON.pretty_generate(result[:data]) : nil,
        error_output: result[:error],
        started_at: Time.current,
        completed_at: Time.current,
        duration_seconds: 0
      )
    rescue StandardError => e
      Rails.logger.error "Failed to create command record: #{e.message}"
    end
  end
end
