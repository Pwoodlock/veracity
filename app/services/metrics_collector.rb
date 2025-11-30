# frozen_string_literal: true

# Service for collecting system metrics from Salt minions
class MetricsCollector
  class << self
    # Collect metrics for a specific server
    def collect_for_server(server)
      return unless server.minion_id.present? && server.status == 'online'

      Rails.logger.info "Collecting metrics for #{server.hostname}"

      begin
        # Collect various metrics from the minion
        metrics_data = gather_metrics(server.minion_id)

        # Process and store metrics
        if metrics_data.present?
          store_metrics(server, metrics_data)
          update_server_status(server, metrics_data)
        end

        metrics_data
      rescue StandardError => e
        Rails.logger.error "Failed to collect metrics for #{server.hostname}: #{e.message}"
        nil
      end
    end

    # Collect metrics for all online servers
    def collect_for_all_servers
      Server.where(status: 'online').find_each do |server|
        CollectMetricsJob.perform_later(server.id)
      end
    end

    private

    # Gather all metrics from a minion
    def gather_metrics(minion_id)
      Rails.logger.debug "Gathering metrics for minion: #{minion_id}"

      metrics = {}

      # Load average metrics (replaces status.cpuload which isn't available)
      load_result = SaltService.run_command_raw(minion_id, 'status.loadavg')
      if load_result && load_result['return']
        load_data = load_result['return'].first[minion_id]
        metrics[:load] = parse_load_average(load_data) if load_data
      end

      # Memory metrics (using free command since status.meminfo isn't available)
      mem_result = SaltService.run_command_raw(minion_id, 'cmd.run', ['free -m'])
      if mem_result && mem_result['return']
        mem_output = mem_result['return'].first[minion_id]
        metrics[:memory] = parse_free_output(mem_output) if mem_output
      end

      # Disk metrics
      disk_result = SaltService.run_command_raw(minion_id, 'disk.usage')
      if disk_result && disk_result['return']
        disk_data = disk_result['return'].first[minion_id]
        metrics[:disk] = parse_disk_metrics(disk_data) if disk_data
      end

      # Network metrics - DISABLED (interface name varies, unreliable)
      # Can be re-enabled if needed with dynamic interface detection
      # net_result = SaltService.run_command_raw(minion_id, 'network.interface_ip', ['eth0'])
      # if net_result && net_result['return']
      #   net_data = net_result['return'].first[minion_id]
      #   metrics[:network] = { primary_ip: net_data } if net_data
      # end

      # CPU count from grains (replaces ps.num_cpus which isn't available)
      proc_result = SaltService.run_command_raw(minion_id, 'grains.item', ['num_cpus'])
      if proc_result && proc_result['return']
        proc_data = proc_result['return'].first[minion_id]
        metrics[:processes] = { cpu_count: proc_data['num_cpus'] } if proc_data && proc_data['num_cpus']
      end

      # Uptime
      uptime_result = SaltService.run_command_raw(minion_id, 'status.uptime')
      if uptime_result && uptime_result['return']
        uptime_data = uptime_result['return'].first[minion_id]
        metrics[:uptime] = parse_uptime(uptime_data) if uptime_data
      end

      # Note: Load average already collected above (line 45-49), no need to duplicate

      metrics
    rescue StandardError => e
      Rails.logger.error "Error gathering metrics: #{e.message}"
      {}
    end

    # Parse CPU metrics
    def parse_cpu_metrics(cpu_data)
      case cpu_data
      when Hash
        {
          load_1m: cpu_data['1-min']&.to_f || 0.0,
          load_5m: cpu_data['5-min']&.to_f || 0.0,
          load_15m: cpu_data['15-min']&.to_f || 0.0
        }
      when Array
        # Some systems return as array [1m, 5m, 15m]
        {
          load_1m: cpu_data[0]&.to_f || 0.0,
          load_5m: cpu_data[1]&.to_f || 0.0,
          load_15m: cpu_data[2]&.to_f || 0.0
        }
      else
        { load_1m: 0.0, load_5m: 0.0, load_15m: 0.0 }
      end
    end

    # Parse memory metrics
    def parse_memory_metrics(mem_data)
      return {} unless mem_data.is_a?(Hash)

      total = extract_memory_value(mem_data, 'MemTotal')
      free = extract_memory_value(mem_data, 'MemFree')
      available = extract_memory_value(mem_data, 'MemAvailable') || free
      buffers = extract_memory_value(mem_data, 'Buffers')
      cached = extract_memory_value(mem_data, 'Cached')
      swap_total = extract_memory_value(mem_data, 'SwapTotal')
      swap_free = extract_memory_value(mem_data, 'SwapFree')

      used = total - available
      percent_used = total > 0 ? (used.to_f / total * 100).round(2) : 0
      swap_percent = swap_total > 0 ? ((swap_total - swap_free).to_f / swap_total * 100).round(2) : 0

      {
        total_gb: (total / 1024.0 / 1024.0).round(2),
        used_gb: (used / 1024.0 / 1024.0).round(2),
        free_gb: (free / 1024.0 / 1024.0).round(2),
        available_gb: (available / 1024.0 / 1024.0).round(2),
        percent_used: percent_used,
        buffers_gb: (buffers / 1024.0 / 1024.0).round(2),
        cached_gb: (cached / 1024.0 / 1024.0).round(2),
        swap_total_gb: (swap_total / 1024.0 / 1024.0).round(2),
        swap_free_gb: (swap_free / 1024.0 / 1024.0).round(2),
        swap_percent: swap_percent
      }
    end

    # Extract memory value from various formats
    def extract_memory_value(mem_data, key)
      value = mem_data[key]
      return 0 unless value

      case value
      when Hash
        value['value']&.to_i || 0
      when String
        # Parse "1234 kB" format
        value.scan(/\d+/).first&.to_i || 0
      when Numeric
        value.to_i
      else
        0
      end
    end

    # Parse free command output (free -m)
    # @param output [String] Output from 'free -m' command
    # @return [Hash] Parsed memory metrics in GB
    def parse_free_output(output)
      return {} unless output.is_a?(String)

      lines = output.split("\n")
      mem_line = lines.find { |l| l.start_with?('Mem:') }
      swap_line = lines.find { |l| l.start_with?('Swap:') }

      return {} unless mem_line

      # Parse memory line: Mem:  total  used  free  shared  buff/cache  available
      mem_parts = mem_line.split
      total = mem_parts[1].to_i
      used = mem_parts[2].to_i
      free = mem_parts[3].to_i
      available = mem_parts[6]&.to_i || free

      # Parse swap line if present
      swap_total = 0
      swap_used = 0
      if swap_line
        swap_parts = swap_line.split
        swap_total = swap_parts[1].to_i
        swap_used = swap_parts[2].to_i
      end

      # Calculate percentages
      percent_used = total > 0 ? (used.to_f / total * 100).round(2) : 0.0
      swap_percent = swap_total > 0 ? (swap_used.to_f / swap_total * 100).round(2) : 0.0

      # Return in GB (free -m gives MB, so divide by 1024)
      {
        total_gb: (total / 1024.0).round(2),
        used_gb: (used / 1024.0).round(2),
        free_gb: (free / 1024.0).round(2),
        available_gb: (available / 1024.0).round(2),
        percent_used: percent_used,
        buffers_gb: 0.0, # Not available from free output
        cached_gb: 0.0,  # Not available from free output
        swap_total_gb: (swap_total / 1024.0).round(2),
        swap_free_gb: ((swap_total - swap_used) / 1024.0).round(2),
        swap_percent: swap_percent
      }
    end

    # Parse disk metrics
    def parse_disk_metrics(disk_data)
      return {} unless disk_data.is_a?(Hash)

      disks = {}
      disk_data.each do |mount_point, usage|
        next unless usage.is_a?(Hash)

        # Convert to GB and percentages
        total = usage['total']&.to_i || usage['1K-blocks']&.to_i || 0
        used = usage['used']&.to_i || 0
        available = usage['available']&.to_i || 0
        percent = usage['percent']&.to_f || usage['capacity']&.to_f || 0

        disks[mount_point] = {
          total_gb: (total / 1024.0 / 1024.0).round(2),
          used_gb: (used / 1024.0 / 1024.0).round(2),
          available_gb: (available / 1024.0 / 1024.0).round(2),
          percent_used: percent,
          filesystem: usage['filesystem']
        }
      end

      disks
    end

    # Parse uptime data
    def parse_uptime(uptime_data)
      case uptime_data
      when Hash
        {
          days: uptime_data['days']&.to_i || 0,
          hours: uptime_data['hours']&.to_i || 0,
          minutes: uptime_data['minutes']&.to_i || 0,
          seconds: uptime_data['seconds']&.to_i || 0,
          since: uptime_data['since']
        }
      when String
        # Parse "up 5 days, 3:21" format
        days = uptime_data.scan(/(\d+)\s+days?/).first&.first&.to_i || 0
        hours = uptime_data.scan(/(\d+):/).first&.first&.to_i || 0
        minutes = uptime_data.scan(/:(\d+)/).first&.first&.to_i || 0

        {
          days: days,
          hours: hours,
          minutes: minutes,
          formatted: uptime_data
        }
      else
        {}
      end
    end

    # Parse load average data
    def parse_load_average(load_data)
      case load_data
      when Hash
        {
          load_1m: load_data['1m']&.to_f || load_data['1-min']&.to_f || 0.0,
          load_5m: load_data['5m']&.to_f || load_data['5-min']&.to_f || 0.0,
          load_15m: load_data['15m']&.to_f || load_data['15-min']&.to_f || 0.0
        }
      when Array
        {
          load_1m: load_data[0]&.to_f || 0.0,
          load_5m: load_data[1]&.to_f || 0.0,
          load_15m: load_data[2]&.to_f || 0.0
        }
      else
        { load_1m: 0.0, load_5m: 0.0, load_15m: 0.0 }
      end
    end

    # Store metrics in database
    def store_metrics(server, metrics_data)
      # Calculate aggregated values
      cpu_count = metrics_data.dig(:processes, :cpu_count) || 4
      cpu_percent = calculate_cpu_percent(metrics_data[:load], cpu_count)
      memory_data = metrics_data[:memory] || {}
      disk_data = metrics_data[:disk] || {}
      load_data = metrics_data[:load] || {}

      # Create metric record
      metric = ServerMetric.create!(
        server: server,
        cpu_percent: cpu_percent,
        memory_percent: memory_data[:percent_used] || 0.0,
        memory_used_gb: memory_data[:used_gb] || 0.0,
        memory_total_gb: memory_data[:total_gb] || 0.0,
        disk_usage: disk_data,
        network_io: metrics_data[:network] || {},
        load_1m: load_data[:load_1m] || 0.0,
        load_5m: load_data[:load_5m] || 0.0,
        load_15m: load_data[:load_15m] || 0.0,
        process_count: metrics_data.dig(:processes, :cpu_count) || 0,
        tcp_connections: 0, # TODO: Implement TCP connection counting
        swap_percent: memory_data[:swap_percent] || 0.0,
        collected_at: Time.current
      )

      Rails.logger.debug "Stored metrics for #{server.hostname}: #{metric.id}"
      metric
    end

    # Update server with latest metrics
    def update_server_status(server, metrics_data)
      server.update!(
        latest_metrics: metrics_data,
        last_heartbeat: Time.current,
        memory_gb: metrics_data.dig(:memory, :total_gb),
        disk_gb: calculate_total_disk(metrics_data[:disk])
      )
    end

    # Calculate CPU percentage from load average
    # @param load_data [Hash] Load average data with :load_1m key
    # @param cpu_count [Integer] Number of CPU cores
    # @return [Float] CPU percentage (0.0-100.0)
    def calculate_cpu_percent(load_data, cpu_count = 4)
      return 0.0 unless load_data

      # Use 1-minute load average
      load_1m = load_data[:load_1m] || 0.0

      # Calculate percentage (load / cpu_count * 100)
      # Cap at 100%
      [(load_1m / cpu_count * 100).round(2), 100.0].min
    end

    # Calculate total disk space
    def calculate_total_disk(disk_data)
      return 0.0 unless disk_data.is_a?(Hash)

      # Sum up all mount points except special ones
      total = 0.0
      disk_data.each do |mount, data|
        next if mount.start_with?('/dev', '/sys', '/proc', '/run')
        next unless data.is_a?(Hash)

        total += data[:total_gb] || 0.0
      end

      total.round(2)
    end
  end
end