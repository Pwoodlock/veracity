# frozen_string_literal: true

# Service for Proxmox VM/LXC control operations
# Handles power management, snapshots, and status checks via proxmoxer Python library
#
# SECURITY: This service supports two execution modes:
# 1. Legacy mode (insecure): Passes API token as command-line argument
# 2. Pillar mode (secure): Passes credentials via Salt pillar, never in command line
#
# The secure mode is used by default when USE_SECURE_PROXMOX_API env var is set,
# or can be explicitly called via execute_proxmox_command_secure method.
class ProxmoxService
  # Path to Python script on Proxmox host
  SCRIPT_PATH = '/usr/local/bin/proxmox_api.py'

  # Use secure pillar-based execution by default
  USE_SECURE_MODE = ENV.fetch('USE_SECURE_PROXMOX_API', 'true').downcase == 'true'

  class << self
    # ===== Power Management Methods =====

    # Start a Proxmox VM or LXC container
    def start_vm(server)
      validate_server!(server)

      result = execute_proxmox_command(server, 'start_vm')

      if result[:success]
        server.update(
          proxmox_power_state: 'running',
          status: 'online',
          last_seen: Time.current
        )
        create_command_record(server, 'start_vm', result)
      end

      result
    end

    # Stop (force) a Proxmox VM or LXC container
    def stop_vm(server)
      validate_server!(server)

      result = execute_proxmox_command(server, 'stop_vm')

      if result[:success]
        server.update(
          proxmox_power_state: 'stopped',
          status: 'offline'
        )
        create_command_record(server, 'stop_vm', result)
      end

      result
    end

    # Shutdown (graceful) a Proxmox VM or LXC container
    def shutdown_vm(server)
      validate_server!(server)

      result = execute_proxmox_command(server, 'shutdown_vm')

      if result[:success]
        server.update(
          proxmox_power_state: 'stopped',
          status: 'offline'
        )
        create_command_record(server, 'shutdown_vm', result)
      end

      result
    end

    # Reboot a Proxmox VM or LXC container
    def reboot_vm(server)
      validate_server!(server)

      result = execute_proxmox_command(server, 'reboot_vm')

      if result[:success]
        server.update(
          proxmox_power_state: 'running'
        )
        create_command_record(server, 'reboot_vm', result)
      end

      result
    end

    # ===== Status Methods =====

    # Get current VM/LXC status
    def get_vm_status(server)
      validate_server!(server)

      result = execute_proxmox_command(server, 'get_vm_status')

      if result[:success] && result[:data]
        # Update server record with latest status
        update_server_from_status(server, result[:data])
      end

      result
    end

    # Refresh VM/LXC info from Proxmox API
    def refresh_vm_info(server)
      result = get_vm_status(server)

      if result[:success] && result[:data]
        create_command_record(server, 'refresh_proxmox_info', result)
      end

      result
    end

    # ===== Snapshot Methods =====

    # List all snapshots for a VM or LXC container
    def list_snapshots(server)
      validate_server!(server)

      result = execute_proxmox_command(server, 'list_snapshots')

      if result[:success]
        create_command_record(server, 'list_snapshots', result)
      end

      result
    end

    # Create a new snapshot
    def create_snapshot(server, snap_name, description = '')
      validate_server!(server)

      result = execute_proxmox_command(server, 'create_snapshot', {
        snap_name: snap_name,
        description: description
      })

      if result[:success]
        create_command_record(server, 'create_snapshot', result.merge(
          snapshot_name: snap_name
        ))
      end

      result
    end

    # Rollback VM/LXC to a snapshot
    def rollback_snapshot(server, snap_name)
      validate_server!(server)

      result = execute_proxmox_command(server, 'rollback_snapshot', {
        snap_name: snap_name
      })

      if result[:success]
        create_command_record(server, 'rollback_snapshot', result.merge(
          snapshot_name: snap_name
        ))
      end

      result
    end

    # Delete a snapshot
    def delete_snapshot(server, snap_name)
      validate_server!(server)

      result = execute_proxmox_command(server, 'delete_snapshot', {
        snap_name: snap_name
      })

      if result[:success]
        create_command_record(server, 'delete_snapshot', result.merge(
          snapshot_name: snap_name
        ))
      end

      result
    end

    # ===== Discovery Methods =====

    # List all VMs and containers on a Proxmox node
    # Takes a ProxmoxApiKey object and node name
    def list_vms(api_key, node_name)
      unless api_key.is_a?(ProxmoxApiKey)
        raise ArgumentError, "Expected ProxmoxApiKey, got #{api_key.class}"
      end

      unless api_key.enabled?
        return {
          success: false,
          error: "API key '#{api_key.name}' is disabled",
          timestamp: Time.current.iso8601
        }
      end

      if USE_SECURE_MODE
        return list_vms_secure(api_key, node_name)
      end

      list_vms_legacy(api_key, node_name)
    end

    # SECURE: List VMs using pillar-based credentials
    # Uses cmd.run with environment variables - credentials never appear in command line
    def list_vms_secure(api_key, node_name)
      minion_id = api_key.minion_id
      proxmox_node = node_name.split('.').first

      Rails.logger.info "Listing VMs on #{node_name} using secure env var mode"

      # Build the command with --env flag (reads from environment)
      command = "python3 #{SCRIPT_PATH} list_vms --env"

      # Environment variables containing the secrets
      env_vars = {
        'PROXMOX_API_URL' => api_key.proxmox_url,
        'PROXMOX_USERNAME' => "#{api_key.username}@#{api_key.realm}",
        'PROXMOX_TOKEN' => "#{api_key.token_name}=#{api_key.api_token}",
        'PROXMOX_VERIFY_SSL' => api_key.verify_ssl ? 'true' : 'false',
        'PROXMOX_NODE' => proxmox_node
      }

      # Execute via Salt with environment variables
      # The env vars are passed securely via Salt's encrypted channel
      salt_result = execute_with_env(minion_id, command, env_vars, timeout: 30)

      api_key.mark_as_used!

      if salt_result[:success]
        parse_json_response(salt_result[:output])
      else
        {
          success: false,
          error: "Command failed: #{salt_result[:output]}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "ProxmoxService list_vms_secure error: #{e.message}"
      { success: false, error: e.message, timestamp: Time.current.iso8601 }
    end

    # LEGACY: List VMs with credentials in command line (INSECURE)
    def list_vms_legacy(api_key, node_name)
      # Extract short hostname for Proxmox API (e.g., pve-1 from pve-1.fritz.box)
      # Proxmox node names are typically just the short hostname
      proxmox_node = node_name.split('.').first

      # Build command for Python script via Salt
      # Python script expects: username=user@realm, token=tokenname=secret
      command = build_python_command('list_vms', {
        api_url: api_key.proxmox_url,
        username: "#{api_key.username}@#{api_key.realm}",
        token: "#{api_key.token_name}=#{api_key.api_token}",
        node: proxmox_node,
        verify_ssl: api_key.verify_ssl
      })

      # Mark API key as used
      api_key.mark_as_used!

      # Execute via Salt on Proxmox host using the configured minion_id
      minion_id = api_key.minion_id
      salt_result = SaltService.run_command(minion_id, 'cmd.run', [command], timeout: 30)

      if salt_result[:success]
        parse_json_response(salt_result[:output])
      else
        {
          success: false,
          error: "Salt command failed: #{salt_result[:output]}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "ProxmoxService list_vms error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    # Test connection to Proxmox API
    def test_connection(api_key)
      unless api_key.is_a?(ProxmoxApiKey)
        raise ArgumentError, "Expected ProxmoxApiKey, got #{api_key.class}"
      end

      unless api_key.enabled?
        return {
          success: false,
          error: "API key '#{api_key.name}' is disabled",
          timestamp: Time.current.iso8601
        }
      end

      if USE_SECURE_MODE
        return test_connection_secure(api_key)
      end

      test_connection_legacy(api_key)
    end

    # SECURE: Test connection using environment variables
    # Uses cmd.run with environment variables - credentials never appear in command line
    def test_connection_secure(api_key)
      minion_id = api_key.minion_id

      Rails.logger.info "Testing Proxmox connection using secure env var mode"

      # Build the command with --env flag
      command = "python3 #{SCRIPT_PATH} test_connection --env"

      # Environment variables containing the secrets
      env_vars = {
        'PROXMOX_API_URL' => api_key.proxmox_url,
        'PROXMOX_USERNAME' => "#{api_key.username}@#{api_key.realm}",
        'PROXMOX_TOKEN' => "#{api_key.token_name}=#{api_key.api_token}",
        'PROXMOX_VERIFY_SSL' => api_key.verify_ssl ? 'true' : 'false'
      }

      # Execute via Salt with environment variables
      salt_result = execute_with_env(minion_id, command, env_vars, timeout: 15)

      api_key.mark_as_used!

      if salt_result[:success]
        parse_json_response(salt_result[:output])
      else
        {
          success: false,
          error: "Command failed: #{salt_result[:output]}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "ProxmoxService test_connection_secure error: #{e.message}"
      { success: false, error: e.message, timestamp: Time.current.iso8601 }
    end

    # LEGACY: Test connection with credentials in command line (INSECURE)
    def test_connection_legacy(api_key)
      # Build command for Python script via Salt
      # Python script expects: username=user@realm, token=tokenname=secret
      command = build_python_command('test_connection', {
        api_url: api_key.proxmox_url,
        username: "#{api_key.username}@#{api_key.realm}",
        token: "#{api_key.token_name}=#{api_key.api_token}",
        verify_ssl: api_key.verify_ssl
      })

      # Mark API key as used
      api_key.mark_as_used!

      # Use the configured minion_id for Salt command execution
      minion_id = api_key.minion_id

      # Execute via Salt
      salt_result = SaltService.run_command(minion_id, 'cmd.run', [command], timeout: 15)

      if salt_result[:success]
        parse_json_response(salt_result[:output])
      else
        {
          success: false,
          error: "Salt command failed: #{salt_result[:output]}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "ProxmoxService test_connection error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    private

    # Execute Proxmox Python script command via Salt
    # Automatically uses secure pillar mode if USE_SECURE_MODE is true
    def execute_proxmox_command(server, command, extra_params = {})
      if USE_SECURE_MODE
        return execute_proxmox_command_secure(server, command, extra_params)
      end

      execute_proxmox_command_legacy(server, command, extra_params)
    end

    # SECURE: Execute Proxmox command using environment variables
    # The API token is passed via env vars, never appearing in:
    # - Command-line arguments (ps aux won't show it)
    # - Salt job cache
    # - Shell history
    #
    # @param server [Server] Server with Proxmox configuration
    # @param command [String] Proxmox command to execute
    # @param extra_params [Hash] Additional parameters (snap_name, description, etc.)
    # @return [Hash] Result with :success, :data, :error keys
    def execute_proxmox_command_secure(server, command, extra_params = {})
      api_key = server.proxmox_api_key
      minion_id = server.proxmox_node

      # Extract short hostname for Proxmox API
      proxmox_node = server.proxmox_node.split('.').first

      Rails.logger.info "Executing Proxmox command '#{command}' on #{minion_id} using secure env var mode"

      # Build the command with --env flag
      cmd = "python3 #{SCRIPT_PATH} #{command} --env"

      # Environment variables containing the secrets
      env_vars = {
        'PROXMOX_API_URL' => api_key.proxmox_url,
        'PROXMOX_USERNAME' => "#{api_key.username}@#{api_key.realm}",
        'PROXMOX_TOKEN' => "#{api_key.token_name}=#{api_key.api_token}",
        'PROXMOX_VERIFY_SSL' => api_key.verify_ssl ? 'true' : 'false',
        'PROXMOX_NODE' => proxmox_node,
        'PROXMOX_VMID' => server.proxmox_vmid.to_s,
        'PROXMOX_VM_TYPE' => server.proxmox_type
      }

      # Add extra params (for snapshots)
      env_vars['PROXMOX_SNAP_NAME'] = extra_params[:snap_name] if extra_params[:snap_name]
      env_vars['PROXMOX_SNAP_DESC'] = extra_params[:description] if extra_params[:description]

      # Execute via Salt with environment variables
      salt_result = execute_with_env(minion_id, cmd, env_vars, timeout: 60)

      # Mark API key as used
      api_key.mark_as_used!

      if salt_result[:success]
        parse_json_response(salt_result[:output])
      else
        {
          success: false,
          error: "Command failed: #{salt_result[:output]}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "ProxmoxService secure execution error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    # LEGACY: Execute Proxmox Python script command via Salt (INSECURE)
    # WARNING: API token appears in command-line arguments
    def execute_proxmox_command_legacy(server, command, extra_params = {})
      api_key = server.proxmox_api_key

      # Extract short hostname for Proxmox API (e.g., pve-1 from pve-1.fritz.box)
      # Proxmox node names are typically just the short hostname
      proxmox_node = server.proxmox_node.split('.').first

      # Build command parameters
      # Python script expects: username=user@realm, token=tokenname=secret
      params = {
        api_url: api_key.proxmox_url,
        username: "#{api_key.username}@#{api_key.realm}",
        token: "#{api_key.token_name}=#{api_key.api_token}",
        node: proxmox_node,
        vmid: server.proxmox_vmid,
        vm_type: server.proxmox_type,
        verify_ssl: api_key.verify_ssl
      }.merge(extra_params)

      # Build Python command
      python_cmd = build_python_command(command, params)

      # Mark API key as used
      api_key.mark_as_used!

      # Execute via Salt on Proxmox host (use full hostname as minion ID)
      minion_id = server.proxmox_node
      salt_result = SaltService.run_command(minion_id, 'cmd.run', [python_cmd], timeout: 60)

      if salt_result[:success]
        parse_json_response(salt_result[:output])
      else
        {
          success: false,
          error: "Salt command failed: #{salt_result[:output]}",
          timestamp: Time.current.iso8601
        }
      end
    rescue StandardError => e
      Rails.logger.error "ProxmoxService error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      {
        success: false,
        error: e.message,
        timestamp: Time.current.iso8601
      }
    end

    # Execute a command via Salt with environment variables
    # This is the SECURE method - credentials are passed via env vars, not command line
    # Salt encrypts the env vars in transit, and they never appear in ps aux
    #
    # @param minion_id [String] Target minion ID
    # @param command [String] Shell command to execute
    # @param env_vars [Hash] Environment variables to set (will contain secrets)
    # @param timeout [Integer] Timeout in seconds
    # @return [Hash] Result with :success and :output keys
    def execute_with_env(minion_id, command, env_vars, timeout: 60)
      Rails.logger.debug "Executing command on #{minion_id} with #{env_vars.keys.size} env vars"

      # Salt's cmd.run accepts env as a kwarg
      # Format: salt 'minion' cmd.run 'command' env='{"KEY": "value"}'
      # We pass it as a Python dict string
      env_json = env_vars.to_json

      # Use Salt API to run the command with environment variables
      # The env parameter is passed as a kwarg to cmd.run
      body = {
        client: 'local',
        tgt: minion_id,
        fun: 'cmd.run',
        arg: [command],
        kwarg: { env: env_vars }
      }

      options = { body: body.to_json, timeout: timeout }

      begin
        result = SaltService.api_call(:post, '/', options)

        if result && result['return'] && result['return'].first
          output = result['return'].first[minion_id]

          if output.nil?
            {
              success: false,
              output: "No response from minion '#{minion_id}'"
            }
          else
            {
              success: true,
              output: output.is_a?(String) ? output : output.to_json
            }
          end
        else
          {
            success: false,
            output: "No response from Salt API"
          }
        end
      rescue StandardError => e
        Rails.logger.error "Salt command with env failed for #{minion_id}: #{e.message}"
        {
          success: false,
          output: "Error: #{e.message}"
        }
      end
    end

    # Build Python command with proper argument escaping
    def build_python_command(command, params)
      cmd_parts = [
        'python3',
        SCRIPT_PATH,
        command
      ]

      # Add parameters based on command type
      case command
      when 'test_connection'
        cmd_parts += [
          escape_shell_arg(params[:api_url]),
          escape_shell_arg(params[:username]),
          escape_shell_arg(params[:token]),
          params[:verify_ssl] ? 'true' : 'false'
        ]
      when 'list_vms'
        cmd_parts += [
          escape_shell_arg(params[:api_url]),
          escape_shell_arg(params[:username]),
          escape_shell_arg(params[:token]),
          escape_shell_arg(params[:node]),
          params[:verify_ssl] ? 'true' : 'false'
        ]
      when 'get_vm_status', 'start_vm', 'stop_vm', 'shutdown_vm', 'reboot_vm', 'list_snapshots'
        cmd_parts += [
          escape_shell_arg(params[:api_url]),
          escape_shell_arg(params[:username]),
          escape_shell_arg(params[:token]),
          escape_shell_arg(params[:node]),
          params[:vmid].to_s,
          escape_shell_arg(params[:vm_type]),
          params[:verify_ssl] ? 'true' : 'false'
        ]
      when 'create_snapshot'
        cmd_parts += [
          escape_shell_arg(params[:api_url]),
          escape_shell_arg(params[:username]),
          escape_shell_arg(params[:token]),
          escape_shell_arg(params[:node]),
          params[:vmid].to_s,
          escape_shell_arg(params[:vm_type]),
          escape_shell_arg(params[:snap_name]),
          escape_shell_arg(params[:description] || ''),
          params[:verify_ssl] ? 'true' : 'false'
        ]
      when 'rollback_snapshot', 'delete_snapshot'
        cmd_parts += [
          escape_shell_arg(params[:api_url]),
          escape_shell_arg(params[:username]),
          escape_shell_arg(params[:token]),
          escape_shell_arg(params[:node]),
          params[:vmid].to_s,
          escape_shell_arg(params[:vm_type]),
          escape_shell_arg(params[:snap_name]),
          params[:verify_ssl] ? 'true' : 'false'
        ]
      end

      cmd_parts.join(' ')
    end

    # Escape shell argument for safe command execution
    def escape_shell_arg(arg)
      return '""' if arg.nil? || arg.to_s.empty?
      # Use single quotes to prevent shell interpolation
      "'#{arg.to_s.gsub("'", "'\\''")}'"
    end

    # Parse JSON response from Python script
    def parse_json_response(output)
      # Extract JSON from output (in case there's any extra logging)
      json_match = output.match(/\{.*\}/m)
      json_str = json_match ? json_match[0] : output

      JSON.parse(json_str, symbolize_names: true)
    rescue JSON::ParserError => e
      {
        success: false,
        error: "Failed to parse response: #{e.message}",
        raw_output: output,
        timestamp: Time.current.iso8601
      }
    end

    # Validate server has required Proxmox configuration
    def validate_server!(server)
      unless server.proxmox_server?
        raise ArgumentError, "Server #{server.hostname} is not configured as a Proxmox VM/LXC"
      end

      unless server.can_use_proxmox_features?
        raise ArgumentError, "Server #{server.hostname} cannot use Proxmox features (API key disabled or missing)"
      end
    end

    # Update server attributes from Proxmox status data
    def update_server_from_status(server, status_data)
      # status_data format: {vmid:, node:, type:, status:, uptime:, cpus:, memory:, maxmem:, name:}
      updates = {
        proxmox_power_state: status_data[:status],
        last_seen: Time.current
      }

      # Map Proxmox status to server status
      updates[:status] = case status_data[:status]
                        when 'running'
                          'online'
                        when 'stopped', 'paused'
                          'offline'
                        else
                          'unreachable'
                        end

      server.update(updates)
    end

    # Create command record for audit trail
    def create_command_record(server, command_type, result)
      command_description = case command_type
                          when 'start_vm' then 'Proxmox: Start VM/LXC'
                          when 'stop_vm' then 'Proxmox: Stop VM/LXC (Force)'
                          when 'shutdown_vm' then 'Proxmox: Shutdown VM/LXC (Graceful)'
                          when 'reboot_vm' then 'Proxmox: Reboot VM/LXC'
                          when 'refresh_proxmox_info' then 'Proxmox: Refresh VM Info'
                          when 'list_snapshots' then 'Proxmox: List Snapshots'
                          when 'create_snapshot' then "Proxmox: Create Snapshot '#{result[:snapshot_name]}'"
                          when 'rollback_snapshot' then "Proxmox: Rollback to Snapshot '#{result[:snapshot_name]}'"
                          when 'delete_snapshot' then "Proxmox: Delete Snapshot '#{result[:snapshot_name]}'"
                          else
                            "Proxmox: #{command_type.humanize}"
                          end

      Command.create!(
        server: server,
        command_type: command_type,
        command: command_description,
        status: result[:success] ? 'completed' : 'failed',
        output: result[:data] ? JSON.pretty_generate(result[:data]) : result[:message],
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
