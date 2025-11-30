# frozen_string_literal: true

# Service for comprehensive Salt minion health diagnostics
# Helps identify why specific servers are showing as offline
class SaltHealthCheckService
  class << self
    # Perform comprehensive health check on a server
    # @param server [Server] The server to diagnose
    # @return [Hash] Diagnostic results with detailed information
    def diagnose(server)
      Rails.logger.info "Running health check for server: #{server.hostname} (#{server.minion_id})"

      results = {
        server_id: server.id,
        minion_id: server.minion_id,
        hostname: server.hostname,
        timestamp: Time.current,
        checks: {},
        overall_status: 'unknown',
        recommendations: []
      }

      # Check 1: Basic server database status
      results[:checks][:database_status] = check_database_status(server)

      # Check 2: Salt minion key status
      results[:checks][:key_status] = check_key_status(server.minion_id)

      # Check 3: Ping test
      results[:checks][:ping_test] = check_ping(server.minion_id)

      # Check 4: Grains retrieval (deeper connectivity test)
      results[:checks][:grains_test] = check_grains(server.minion_id)

      # Check 5: Proxmox status (if applicable)
      if server.proxmox_server?
        results[:checks][:proxmox_status] = check_proxmox_status(server)
      end

      # Check 6: Recent activity
      results[:checks][:activity_status] = check_activity_status(server)

      # Determine overall status and generate recommendations
      results[:overall_status] = determine_overall_status(results[:checks])
      results[:recommendations] = generate_recommendations(server, results[:checks])

      results
    rescue StandardError => e
      Rails.logger.error "Error during health check for #{server.minion_id}: #{e.message}"
      {
        server_id: server.id,
        minion_id: server.minion_id,
        hostname: server.hostname,
        timestamp: Time.current,
        checks: {},
        overall_status: 'error',
        error: e.message,
        recommendations: ["Health check failed: #{e.message}"]
      }
    end

    private

    # Check database status
    def check_database_status(server)
      {
        status: 'pass',
        current_status: server.status,
        last_ping_attempt: server.last_ping_attempt,
        last_ping_success: server.last_ping_success,
        ping_failure_count: server.ping_failure_count || 0,
        last_ping_error: server.last_ping_error,
        last_seen: server.last_seen,
        message: "Server record status: #{server.status}"
      }
    end

    # Check if minion key is accepted
    def check_key_status(minion_id)
      Rails.logger.debug "Checking key status for #{minion_id}"

      keys_response = SaltService.list_keys
      if keys_response && keys_response['return']
        data = keys_response['return'].first['data']
        all_keys = data['return']

        accepted_keys = all_keys['minions'] || []
        pending_keys = all_keys['minions_pre'] || []
        rejected_keys = all_keys['minions_rejected'] || []
        denied_keys = all_keys['minions_denied'] || []

        if accepted_keys.include?(minion_id)
          {
            status: 'pass',
            key_state: 'accepted',
            message: "Minion key is accepted on Salt master"
          }
        elsif pending_keys.include?(minion_id)
          {
            status: 'fail',
            key_state: 'pending',
            message: "Minion key is pending acceptance"
          }
        elsif rejected_keys.include?(minion_id)
          {
            status: 'fail',
            key_state: 'rejected',
            message: "Minion key has been rejected"
          }
        elsif denied_keys.include?(minion_id)
          {
            status: 'fail',
            key_state: 'denied',
            message: "Minion key has been denied"
          }
        else
          {
            status: 'fail',
            key_state: 'not_found',
            message: "Minion key not found on Salt master"
          }
        end
      else
        {
          status: 'error',
          key_state: 'unknown',
          message: "Could not retrieve key list from Salt master"
        }
      end
    rescue StandardError => e
      Rails.logger.error "Error checking key status: #{e.message}"
      {
        status: 'error',
        key_state: 'unknown',
        message: "Error checking key: #{e.message}"
      }
    end

    # Test ping connectivity
    def check_ping(minion_id)
      Rails.logger.debug "Testing ping for #{minion_id}"

      start_time = Time.current
      ping_result = SaltService.ping_minion(minion_id)
      duration = ((Time.current - start_time) * 1000).round(2) # ms

      if ping_result && ping_result['return'] && ping_result['return'].first
        response = ping_result['return'].first[minion_id]

        if response == true
          {
            status: 'pass',
            response_time_ms: duration,
            message: "Minion responded to ping in #{duration}ms"
          }
        elsif response == false
          {
            status: 'fail',
            response_time_ms: duration,
            message: "Minion returned false (service may be unhealthy)"
          }
        elsif response.nil?
          {
            status: 'fail',
            response_time_ms: duration,
            message: "No response from minion (timeout or unreachable)"
          }
        else
          {
            status: 'warn',
            response_time_ms: duration,
            message: "Unexpected ping response: #{response.inspect}"
          }
        end
      else
        {
          status: 'fail',
          response_time_ms: duration,
          message: "No valid response from Salt API"
        }
      end
    rescue StandardError => e
      Rails.logger.error "Error during ping test: #{e.message}"
      {
        status: 'error',
        message: "Ping test error: #{e.message}"
      }
    end

    # Test grains retrieval (deeper connectivity)
    def check_grains(minion_id)
      Rails.logger.debug "Testing grains retrieval for #{minion_id}"

      start_time = Time.current
      grains_result = SaltService.get_grains(minion_id)
      duration = ((Time.current - start_time) * 1000).round(2) # ms

      if grains_result && grains_result['return'] && grains_result['return'].first
        grains = grains_result['return'].first[minion_id]

        if grains.is_a?(Hash) && grains.any?
          {
            status: 'pass',
            response_time_ms: duration,
            grains_count: grains.keys.count,
            message: "Successfully retrieved #{grains.keys.count} grains in #{duration}ms"
          }
        elsif grains.nil?
          {
            status: 'fail',
            response_time_ms: duration,
            message: "No grains data returned (minion unreachable)"
          }
        else
          {
            status: 'warn',
            response_time_ms: duration,
            message: "Unexpected grains response: #{grains.class}"
          }
        end
      else
        {
          status: 'fail',
          response_time_ms: duration,
          message: "Failed to retrieve grains"
        }
      end
    rescue StandardError => e
      Rails.logger.error "Error during grains test: #{e.message}"
      {
        status: 'error',
        message: "Grains test error: #{e.message}"
      }
    end

    # Check Proxmox VM status
    def check_proxmox_status(server)
      return nil unless server.proxmox_server?

      Rails.logger.debug "Checking Proxmox status for #{server.hostname}"

      begin
        proxmox_service = ProxmoxService.new(server.proxmox_api_key)
        status_data = proxmox_service.get_vm_status(server.proxmox_node, server.proxmox_vmid, server.proxmox_type)

        if status_data[:success]
          power_state = status_data[:status]
          {
            status: power_state == 'running' ? 'pass' : 'warn',
            power_state: power_state,
            node: server.proxmox_node,
            vmid: server.proxmox_vmid,
            type: server.proxmox_type,
            message: "Proxmox VM is #{power_state}"
          }
        else
          {
            status: 'error',
            message: "Failed to get Proxmox status: #{status_data[:error]}"
          }
        end
      rescue StandardError => e
        Rails.logger.error "Error checking Proxmox status: #{e.message}"
        {
          status: 'error',
          message: "Proxmox check error: #{e.message}"
        }
      end
    end

    # Check recent activity timestamps
    def check_activity_status(server)
      last_ping_success = server.last_ping_success
      last_ping_attempt = server.last_ping_attempt
      last_seen = server.last_seen

      status = if last_ping_success && last_ping_success > 10.minutes.ago
                 'pass'
               elsif last_ping_success && last_ping_success > 1.hour.ago
                 'warn'
               else
                 'fail'
               end

      time_since_success = if last_ping_success
                             distance_of_time(Time.current - last_ping_success)
                           else
                             'never'
                           end

      time_since_attempt = if last_ping_attempt
                             distance_of_time(Time.current - last_ping_attempt)
                           else
                             'never'
                           end

      {
        status: status,
        last_ping_success: last_ping_success,
        last_ping_attempt: last_ping_attempt,
        last_seen: last_seen,
        time_since_success: time_since_success,
        time_since_attempt: time_since_attempt,
        message: "Last successful ping: #{time_since_success} ago"
      }
    end

    # Determine overall health status from check results
    def determine_overall_status(checks)
      statuses = checks.values.compact.map { |check| check[:status] }

      return 'error' if statuses.include?('error')
      return 'fail' if statuses.include?('fail')
      return 'degraded' if statuses.include?('warn')
      return 'healthy' if statuses.all? { |s| s == 'pass' }

      'unknown'
    end

    # Generate actionable recommendations based on check results
    def generate_recommendations(server, checks)
      recommendations = []

      # Key issues
      if checks[:key_status][:status] == 'fail'
        case checks[:key_status][:key_state]
        when 'pending'
          recommendations << "Accept the minion key on the Salt master"
        when 'rejected', 'denied'
          recommendations << "Delete and re-accept the minion key"
        when 'not_found'
          recommendations << "The minion key is missing. Restart salt-minion service on the server to regenerate the key"
        end
      end

      # Ping issues
      if checks[:ping_test][:status] == 'fail'
        if checks[:key_status][:status] == 'pass'
          recommendations << "Salt minion service may not be running. SSH to server and check: systemctl status salt-minion"
          recommendations << "Check firewall rules allow Salt traffic (ports 4505, 4506)"
          recommendations << "Verify /etc/salt/minion configuration points to correct master"
        end
      end

      # Proxmox mismatch
      if checks[:proxmox_status] && checks[:proxmox_status][:power_state] == 'running' && checks[:ping_test][:status] == 'fail'
        recommendations << "Proxmox shows VM is running but Salt minion is not responding"
        recommendations << "The VM may have booted but salt-minion service failed to start"
        recommendations << "SSH to the VM and manually start: systemctl start salt-minion"
        recommendations << "Check salt-minion logs: journalctl -u salt-minion -n 50"
      end

      # Grains but no ping (unusual)
      if checks[:ping_test][:status] == 'fail' && checks[:grains_test][:status] == 'pass'
        recommendations << "Unusual state: grains work but ping fails. This may indicate a Salt master issue"
      end

      # High failure count
      if checks[:database_status][:ping_failure_count] >= 5
        recommendations << "Server has failed #{checks[:database_status][:ping_failure_count]} consecutive pings"
        recommendations << "This server may need manual intervention or salt-minion reinstallation"
      end

      # No recent success
      if checks[:activity_status][:status] == 'fail'
        recommendations << "No successful ping in over 1 hour. Server may be persistently offline"
      end

      # Default recommendation if nothing specific
      if recommendations.empty? && determine_overall_status(checks) != 'healthy'
        recommendations << "Run diagnostics to identify the root cause"
        recommendations << "Check Salt master logs: tail -f /var/log/salt/master"
      end

      recommendations
    end

    # Human-readable time distance
    def distance_of_time(seconds)
      return 'never' if seconds.nil?

      minutes = (seconds / 60).round
      hours = (seconds / 3600).round
      days = (seconds / 86400).round

      if seconds < 60
        "#{seconds.round}s"
      elsif minutes < 60
        "#{minutes}m"
      elsif hours < 24
        "#{hours}h"
      else
        "#{days}d"
      end
    end
  end
end
