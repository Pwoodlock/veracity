# frozen_string_literal: true

require 'json'

# Service for processing Salt events from the event stream
# This can be used with WebSocket or polling mechanisms
class SaltEventProcessor
  class << self
    # Process a Salt event
    def process_event(event_data)
      return unless event_data.present?

      event = parse_event(event_data)
      return unless event

      Rails.logger.debug "Processing Salt event: #{event[:tag]}"

      case event[:tag]
      when /^salt\/minion\/(.+)\/start$/
        handle_minion_start(Regexp.last_match(1), event)
      when /^salt\/job\/(.+)\/ret\/(.+)$/
        handle_job_return(Regexp.last_match(1), Regexp.last_match(2), event)
      when /^salt\/auth$/
        handle_auth_event(event)
      when /^salt\/key$/
        handle_key_event(event)
      when /^salt\/presence\/present$/
        handle_presence_event(event, true)
      when /^salt\/presence\/lost$/
        handle_presence_event(event, false)
      when /^salt\/beacon\/(.+)\/(.+)$/
        handle_beacon_event(Regexp.last_match(1), Regexp.last_match(2), event)
      else
        Rails.logger.debug "Unhandled event tag: #{event[:tag]}"
      end
    rescue StandardError => e
      Rails.logger.error "Error processing Salt event: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    private

    # Parse event data from various formats
    def parse_event(event_data)
      case event_data
      when Hash
        {
          tag: event_data['tag'] || event_data[:tag],
          data: event_data['data'] || event_data[:data],
          timestamp: Time.current
        }
      when String
        # Try to parse as JSON
        JSON.parse(event_data, symbolize_names: true)
      else
        Rails.logger.warn "Unknown event data format: #{event_data.class}"
        nil
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse event data: #{e.message}"
      nil
    end

    # Handle minion start events
    def handle_minion_start(minion_id, event)
      Rails.logger.info "Minion started: #{minion_id}"

      # Find or create server record
      server = Server.find_by(minion_id: minion_id)

      if server
        server.update!(
          status: 'online',
          last_seen: Time.current,
          last_heartbeat: Time.current
        )
      else
        # New minion - create server record
        create_server_from_minion(minion_id)
      end

      # Broadcast update
      broadcast_server_update(minion_id, 'online')
    end

    # Handle job return events
    def handle_job_return(job_id, minion_id, event)
      Rails.logger.info "Job #{job_id} completed on #{minion_id}"

      return_data = event[:data]
      return unless return_data

      # Find command record if it exists
      command = Command.find_by(salt_job_id: job_id, server: { minion_id: minion_id })

      if command
        command.update!(
          status: return_data['success'] ? 'completed' : 'failed',
          output: format_output(return_data['return']),
          error_output: return_data['retcode'] != 0 ? return_data['return'] : nil,
          exit_code: return_data['retcode'] || 0,
          completed_at: Time.current,
          duration_seconds: calculate_duration(command.started_at)
        )

        # Broadcast command update
        broadcast_command_update(command)
      end
    end

    # Handle authentication events
    def handle_auth_event(event)
      auth_data = event[:data]
      Rails.logger.info "Authentication event: #{auth_data['act']} for #{auth_data['id']}"
    end

    # Handle key events
    def handle_key_event(event)
      key_data = event[:data]
      action = key_data['act']
      minion_id = key_data['id']

      Rails.logger.info "Key event: #{action} for #{minion_id}"

      case action
      when 'accept'
        # Key accepted - create or update server
        create_server_from_minion(minion_id)
      when 'delete', 'reject'
        # Key deleted/rejected - mark server offline
        server = Server.find_by(minion_id: minion_id)
        server&.update!(status: 'offline', last_seen: Time.current)
      end
    end

    # Handle presence events
    def handle_presence_event(event, present)
      minions = event[:data]['present'] || event[:data]['lost'] || []

      minions.each do |minion_id|
        server = Server.find_by(minion_id: minion_id)
        next unless server

        new_status = present ? 'online' : 'offline'
        server.update!(
          status: new_status,
          last_seen: Time.current
        )

        broadcast_server_update(minion_id, new_status)
      end
    end

    # Handle beacon events (monitoring alerts)
    def handle_beacon_event(minion_id, beacon_name, event)
      Rails.logger.info "Beacon event from #{minion_id}: #{beacon_name}"

      beacon_data = event[:data]
      server = Server.find_by(minion_id: minion_id)
      return unless server

      # Process based on beacon type
      case beacon_name
      when 'load'
        handle_load_beacon(server, beacon_data)
      when 'disk'
        handle_disk_beacon(server, beacon_data)
      when 'service'
        handle_service_beacon(server, beacon_data)
      when 'network_info'
        handle_network_beacon(server, beacon_data)
      end
    end

    # Create server from new minion
    def create_server_from_minion(minion_id)
      Rails.logger.info "Creating server record for new minion: #{minion_id}"

      # Get grains data from minion
      RefreshGrainsJob.perform_later(minion_id)

      # Create basic server record
      Server.create!(
        minion_id: minion_id,
        hostname: minion_id, # Will be updated from grains
        status: 'online',
        last_seen: Time.current,
        last_heartbeat: Time.current
      )
    end

    # Format command output
    def format_output(output)
      case output
      when String
        output
      when Hash, Array
        JSON.pretty_generate(output)
      else
        output.to_s
      end
    end

    # Calculate command duration
    def calculate_duration(started_at)
      return 0 unless started_at

      (Time.current - started_at).round(2)
    end

    # Broadcast server status update
    def broadcast_server_update(minion_id, status)
      ActionCable.server.broadcast(
        "server_#{minion_id}",
        {
          type: 'status_update',
          minion_id: minion_id,
          status: status,
          timestamp: Time.current
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to broadcast server update: #{e.message}"
    end

    # Broadcast command update
    def broadcast_command_update(command)
      ActionCable.server.broadcast(
        "command_#{command.id}",
        {
          type: 'command_update',
          command_id: command.id,
          status: command.status,
          output: command.output,
          timestamp: Time.current
        }
      )
    rescue StandardError => e
      Rails.logger.error "Failed to broadcast command update: #{e.message}"
    end

    # Handle load beacon alerts
    def handle_load_beacon(server, data)
      load_1m = data['1m']
      load_5m = data['5m']
      load_15m = data['15m']

      # Check thresholds
      if load_1m > 10.0
        create_alert(server, 'high_load', "High load average: #{load_1m}", data)
      end
    end

    # Handle disk beacon alerts
    def handle_disk_beacon(server, data)
      data.each do |mount, usage|
        next unless usage.is_a?(Hash) && usage['percent']

        if usage['percent'] > 90
          create_alert(server, 'disk_space', "Disk #{mount} at #{usage['percent']}%", usage)
        end
      end
    end

    # Handle service beacon alerts
    def handle_service_beacon(server, data)
      service_name = data['name']
      status = data['status']

      if status != 'running'
        create_alert(server, 'service_down', "Service #{service_name} is #{status}", data)
      end
    end

    # Handle network beacon data
    def handle_network_beacon(server, data)
      # Store network info in latest_metrics
      server.update!(
        latest_metrics: server.latest_metrics.merge('network' => data)
      )
    end

    # Create alert record
    def create_alert(server, alert_type, message, data)
      Rails.logger.warn "Alert for #{server.hostname}: #{message}"

      # Here you would create an Alert record if you have that model
      # Alert.create!(
      #   server: server,
      #   alert_type: alert_type,
      #   message: message,
      #   data: data,
      #   status: 'active'
      # )
    end
  end
end