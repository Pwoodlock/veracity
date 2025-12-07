# frozen_string_literal: true

# Background job for syncing all accepted Salt minions
# Runs periodically to discover minions, check their status, and update database
class SyncMinionsJob < ApplicationJob
  include DashboardBroadcaster

  queue_as :default

  # Retry configuration - be resilient to temporary Salt API issues
  retry_on SaltService::ConnectionError, wait: 30.seconds, attempts: 3
  retry_on SaltService::AuthenticationError, wait: 1.minute, attempts: 2

  def perform
    Rails.logger.info 'SyncMinionsJob: Starting minion sync'
    start_time = Time.current

    # Create a command record for tracking (use first server or create system entry)
    tracking_server = Server.first || Server.create!(
      hostname: 'system',
      minion_id: 'system',
      ip_address: '127.0.0.1',
      status: 'online'
    )

    cmd = Command.create!(
      server: tracking_server,
      command_type: 'system',
      command: 'sync_minions',
      arguments: { job: 'SyncMinionsJob', manual: true },
      status: 'running',
      started_at: start_time
    )

    begin
      # Discover all accepted minions from Salt Master
      minions_data = SaltService.discover_all_minions

      if minions_data.empty?
        Rails.logger.info 'SyncMinionsJob: No accepted minions found'
        cmd.update!(
          status: 'completed',
          output: 'No accepted minions found',
          exit_code: 0,
          completed_at: Time.current
        )
        return
      end

      Rails.logger.info "SyncMinionsJob: Discovered #{minions_data.count} minion(s)"

      # Process each minion
      created_count = 0
      updated_count = 0
      error_count = 0
      output_lines = []

      minions_data.each do |minion_data|
        begin
          result = process_minion(minion_data)
          if result[:created]
            created_count += 1
            output_lines << "✓ Created: #{result[:server].hostname} (#{result[:server].minion_id})"
            Rails.logger.info "SyncMinionsJob: Created server #{result[:server].hostname}"
          else
            updated_count += 1
            output_lines << "✓ Updated: #{result[:server].hostname} (#{result[:server].status})"
            Rails.logger.debug "SyncMinionsJob: Updated server #{result[:server].hostname}"
          end
        rescue StandardError => e
          error_count += 1
          output_lines << "✗ Error: #{minion_data[:minion_id]} - #{e.message}"
          Rails.logger.error "SyncMinionsJob: Error processing #{minion_data[:minion_id]}: #{e.message}"
        end
      end

      # Log summary
      summary = "Sync completed: #{created_count} created, #{updated_count} updated, #{error_count} errors"
      Rails.logger.info "SyncMinionsJob: #{summary}"

      cmd.update!(
        status: error_count > 0 ? 'completed' : 'completed',
        output: "#{summary}\n\n#{output_lines.join("\n")}",
        exit_code: error_count > 0 ? 1 : 0,
        completed_at: Time.current
      )

      # Broadcast dashboard updates
      broadcast_stats_update

    rescue SaltService::ConnectionError => e
      Rails.logger.error "SyncMinionsJob: Salt API connection error: #{e.message}"
      cmd.update!(
        status: 'failed',
        error_output: "Salt API connection error: #{e.message}",
        exit_code: 1,
        completed_at: Time.current
      )
      raise # Will trigger retry
    rescue SaltService::AuthenticationError => e
      Rails.logger.error "SyncMinionsJob: Salt API authentication error: #{e.message}"
      cmd.update!(
        status: 'failed',
        error_output: "Salt API authentication error: #{e.message}",
        exit_code: 2,
        completed_at: Time.current
      )
      raise # Will trigger retry
    rescue StandardError => e
      Rails.logger.error "SyncMinionsJob: Unexpected error: #{e.message}"
      Rails.logger.error e.backtrace.first(5)
      cmd.update!(
        status: 'failed',
        error_output: "Unexpected error: #{e.message}\n#{e.backtrace.first(5).join("\n")}",
        exit_code: 99,
        completed_at: Time.current
      )
      # Don't raise - we don't want to retry on unexpected errors
    end
  end

  private

  def process_minion(minion_data)
    minion_id = minion_data[:minion_id]
    online = minion_data[:online]
    grains = minion_data[:grains]
    ping_error = minion_data[:ping_error]

    # Find or create server
    server = Server.find_or_initialize_by(minion_id: minion_id)
    is_new = server.new_record?

    # Update basic info
    server.hostname = extract_hostname(grains, minion_id)
    server.ip_address = extract_ip_address(grains)
    server.status = determine_status(server, online)

    # Update OS info if grains available
    if grains.present?
      server.os_family = grains['os_family']
      server.os_name = grains['os']
      server.os_version = grains['osrelease'] || grains['osmajorrelease']&.to_s
      server.cpu_cores = grains['num_cpus']
      server.memory_gb = extract_memory_gb(grains)
      server.grains = grains

      # Extract optional info
      server.environment ||= grains['environment'] || 'production'
      server.location ||= grains['location'] || grains['datacenter']
      server.provider ||= detect_provider(grains)
    end

    # Track ping diagnostics - ALWAYS record attempt
    server.last_ping_attempt = Time.current

    if online
      # Ping succeeded
      server.last_ping_success = Time.current
      server.last_seen = Time.current
      server.last_heartbeat = Time.current
      server.ping_failure_count = 0
      server.last_ping_error = nil

      # Log success for previously failing servers
      if server.ping_failure_count_was.to_i > 0
        Rails.logger.info "SyncMinionsJob: Server #{minion_id} is back online after #{server.ping_failure_count_was} failures"
      end
    else
      # Ping failed - increment failure count and log error
      server.ping_failure_count = (server.ping_failure_count || 0) + 1
      server.last_ping_error = ping_error || "Salt minion not responding to ping"

      # Log diagnostic information
      Rails.logger.warn "SyncMinionsJob: Server #{minion_id} ping failed (failure ##{server.ping_failure_count})"
      Rails.logger.warn "  Error: #{server.last_ping_error}"
      Rails.logger.warn "  Last successful ping: #{server.last_ping_success || 'never'}"
      Rails.logger.warn "  Proxmox: #{server.proxmox_server? ? "VM #{server.proxmox_vmid} on #{server.proxmox_node}" : 'N/A'}"
      Rails.logger.warn "  Status: #{server.status}"

      # Alert on repeated failures (threshold: 3)
      if server.ping_failure_count == 3
        Rails.logger.error "ALERT: Server #{minion_id} has failed ping 3 times consecutively"
      elsif server.ping_failure_count >= 10
        Rails.logger.error "CRITICAL: Server #{minion_id} has failed ping #{server.ping_failure_count} times"
      end
    end

    # Save
    server.save!

    { server: server, created: is_new }
  end

  def extract_hostname(grains, fallback)
    return fallback if grains.blank?

    grains['id'] || grains['nodename'] || grains['fqdn'] || grains['host'] || fallback
  end

  def extract_ip_address(grains)
    return nil if grains.blank?

    # Try various grain keys for IP address
    grains['fqdn_ip4']&.first ||
      grains['ipv4']&.first ||
      grains['ip4_interfaces']&.dig('eth0', 0) ||
      grains['ip_interfaces']&.dig('eth0', 0) ||
      grains['ip4_interfaces']&.values&.flatten&.first
  end

  def extract_memory_gb(grains)
    return nil if grains.blank?

    mem_total = grains['mem_total'] || grains['memory_total']
    return nil unless mem_total

    # mem_total is in MB, convert to GB
    (mem_total.to_f / 1024.0).round(2)
  end

  def determine_status(server, online)
    # If new server, just use the ping result
    return online ? 'online' : 'offline' if server.new_record?

    # For existing servers, use grace period to prevent false offline detection
    if online
      'online'
    elsif server.status == 'maintenance'
      # Don't change maintenance status automatically
      'maintenance'
    elsif server.last_seen && server.last_seen > 15.minutes.ago
      # GRACE PERIOD: Keep as online if seen recently (within 15 minutes)
      # This prevents false offline detection from temporary network issues,
      # high load, or minions being busy with other tasks
      time_since_seen = ((Time.current - server.last_seen) / 60).round(1)
      Rails.logger.info "SyncMinionsJob: Server #{server.hostname} (#{server.minion_id}) didn't respond to ping, but was seen #{time_since_seen} min ago - keeping online (grace period)"
      'online'
    else
      # Truly offline - hasn't responded for 15+ minutes
      if server.status != 'offline'
        time_since_seen = server.last_seen ? ((Time.current - server.last_seen) / 60).round(1) : 'unknown'
        Rails.logger.warn "SyncMinionsJob: Marking server #{server.hostname} (#{server.minion_id}) as OFFLINE (last seen: #{time_since_seen} min ago)"
      end
      'offline'
    end
  end

  def detect_provider(grains)
    return nil if grains.blank?

    # Detect cloud provider from grains
    return 'aws' if grains['ec2']
    return 'azure' if grains['azure']
    return 'gcp' if grains['gce']
    return 'digitalocean' if grains['digitalocean']
    return 'linode' if grains['linode']
    return 'vultr' if grains['vultr']
    return 'vmware' if grains['virtual'] == 'VMware'
    return 'docker' if grains['virtual'] == 'container'
    return 'virtualbox' if grains['virtual'] == 'VirtualBox'
    return 'proxmox' if grains['virtual'] == 'kvm' && grains['manufacturer']&.downcase&.include?('proxmox')

    # Check for bare metal indicators
    return 'bare_metal' if grains['virtual'] == 'physical'

    # Default based on virtualization
    grains['virtual'] || 'unknown'
  end
end
