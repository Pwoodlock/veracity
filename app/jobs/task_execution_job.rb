class TaskExecutionJob < ApplicationJob
  queue_as :default

  # Configurable timeout based on command type and number of targets
  def calculate_timeout(target_count, command = nil)
    # Upgrade operations need much more time (can take 30+ minutes per server)
    if command && (command.match?(/pkg\.upgrade/) || command.match?(/apt-get\s+(upgrade|dist-upgrade)/) || command.match?(/yum\s+update/) || command.match?(/dnf\s+upgrade/))
      base_timeout = 1800  # 30 minutes base
      per_target = 600     # 10 minutes per additional target
      max_timeout = 3600   # 60 minutes maximum
    else
      # Standard commands
      base_timeout = 120   # 2 minutes
      per_target = 30      # 30 seconds per target
      max_timeout = 1800   # 30 minutes maximum
    end

    timeout = base_timeout + (target_count * per_target)
    [timeout, max_timeout].min
  end

  def perform(task_run)
    return if task_run.finished?

    task = task_run.task
    task_run.mark_as_running!

    # Get target minion IDs
    minion_ids = task.target_minion_ids

    if minion_ids.empty?
      task_run.mark_as_failed!("No valid targets found", 1)
      return
    end

    # Check if this task needs multi-level execution (snapshots before updates)
    if requires_snapshots?(task.command)
      execute_with_snapshots(task, task_run, minion_ids)
    else
      # Standard execution path
      execute_standard(task, task_run, minion_ids)
    end

  rescue StandardError => e
    Rails.logger.error "Task execution failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    task_run.mark_as_failed!("Execution error: #{e.message}", 1)
  end

  private

  # Check if the command is an update-related command that needs snapshots
  def requires_snapshots?(command)
    update_patterns = [
      /pkg\.upgrade/,
      /pkg\.install/,
      /apt-get\s+upgrade/,
      /apt-get\s+dist-upgrade/,
      /yum\s+update/,
      /dnf\s+upgrade/
    ]

    update_patterns.any? { |pattern| command.match?(pattern) }
  end

  # Check for and clear apt locks before package operations
  def clear_apt_locks_if_needed(command, minion_ids)
    # Only check for Debian/Ubuntu package operations
    return unless command.match?(/pkg\.(upgrade|install|remove)/) || command.match?(/apt-get/)

    Rails.logger.info "TaskExecution: Checking for apt locks on #{minion_ids.count} server(s)"

    target = minion_ids.join(',')

    # Check if apt.systemd.daily is running
    check_cmd = "sudo salt -L '#{target}' cmd.run 'pgrep -a apt.systemd.daily' --timeout=10 --output=json"
    output = `#{check_cmd} 2>&1`

    if $?.exitstatus == 0 && !output.empty?
      begin
        result = JSON.parse(output)
        locked_servers = result.select { |_, v| v.is_a?(String) && !v.empty? }.keys

        if locked_servers.any?
          Rails.logger.warn "TaskExecution: apt.systemd.daily running on #{locked_servers.join(', ')} - clearing locks"

          # Kill automatic update processes
          kill_cmd = "sudo salt -L '#{target}' cmd.run 'killall -9 apt.systemd.daily apt-get 2>/dev/null || true' --timeout=10"
          `#{kill_cmd} 2>&1`

          # Remove lock files
          unlock_cmd = "sudo salt -L '#{target}' cmd.run 'rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null || true' --timeout=10"
          `#{unlock_cmd} 2>&1`

          # Wait a moment for locks to clear
          sleep 2

          Rails.logger.info "TaskExecution: apt locks cleared"
        end
      rescue JSON::ParserError
        # Ignore parsing errors, proceed with execution
      end
    end
  end

  # Execute standard task without snapshots
  def execute_standard(task, task_run, minion_ids)
    # Clear apt locks if this is a package operation
    clear_apt_locks_if_needed(task.command, minion_ids)

    result = execute_salt_command(task.command, minion_ids)

    if result[:success]
      task_run.mark_as_completed!(format_output(result[:output]), 0)

      # Check thresholds and send alerts if needed
      check_thresholds_and_alert(task, result[:raw_data]) if task.alert_on_threshold
    else
      task_run.mark_as_failed!(result[:error] || "Command execution failed", 1)
    end
  end

  # Execute task with multi-level workflow (snapshots → wait → execute)
  def execute_with_snapshots(task, task_run, minion_ids)
    Rails.logger.info "TaskExecution: Multi-level execution for #{task.name}"

    # Get target servers and check which need snapshots
    servers = Server.where(minion_id: minion_ids)
    snapshot_servers = servers.select(&:snapshot_before_update?)

    if snapshot_servers.any?
      Rails.logger.info "TaskExecution: Creating snapshots for #{snapshot_servers.count} server(s)"

      # Create snapshots for all servers that need them
      snapshot_results = create_server_snapshots(snapshot_servers)

      # Check if any snapshots failed
      failed_snapshots = snapshot_results.select { |r| !r[:success] }
      if failed_snapshots.any?
        error_msg = "Snapshot creation failed for #{failed_snapshots.count} server(s)"
        failed_snapshots.each do |r|
          error_msg += "\n- #{r[:hostname]}: #{r[:error]}"
        end
        task_run.mark_as_failed!(error_msg, 1)
        return
      end

      Rails.logger.info "TaskExecution: All snapshots created successfully"
    end

    # Clear apt locks if this is a package operation
    clear_apt_locks_if_needed(task.command, minion_ids)

    # Execute the actual command
    result = execute_salt_command(task.command, minion_ids)

    if result[:success]
      task_run.mark_as_completed!(format_output(result[:output]), 0)

      # Check thresholds and send alerts if needed
      check_thresholds_and_alert(task, result[:raw_data]) if task.alert_on_threshold

      # Cleanup old snapshots in the background (don't wait)
      cleanup_old_snapshots(snapshot_servers) if snapshot_servers.any?
    else
      task_run.mark_as_failed!(result[:error] || "Command execution failed", 1)
    end
  end

  # Create snapshots for multiple servers
  def create_server_snapshots(servers)
    results = []

    servers.each do |server|
      begin
        Rails.logger.info "TaskExecution: Creating snapshot for #{server.hostname}"

        # Call class method directly (not an instance method)
        result = HetznerSnapshotService.create_and_wait(
          server,
          description: "Pre-task snapshot (#{Date.current})",
          timeout: 900 # 15 minutes
        )

        snapshot_id = result[:data]&.[](:snapshot_id) if result[:success]

        results << {
          server_id: server.id,
          hostname: server.hostname,
          success: result[:success],
          snapshot_id: snapshot_id,
          error: result[:error]
        }

        if result[:success]
          Rails.logger.info "TaskExecution: Snapshot created for #{server.hostname}: #{snapshot_id}"
        else
          Rails.logger.error "TaskExecution: Snapshot failed for #{server.hostname}: #{result[:error]}"
        end

      rescue StandardError => e
        Rails.logger.error "TaskExecution: Snapshot exception for #{server.hostname}: #{e.message}"
        results << {
          server_id: server.id,
          hostname: server.hostname,
          success: false,
          error: "Exception: #{e.message}"
        }
      end
    end

    results
  end

  # Cleanup old snapshots (non-blocking)
  def cleanup_old_snapshots(servers)
    servers.each do |server|
      begin
        # Call class method directly (not an instance method)
        result = HetznerSnapshotService.cleanup_old_snapshots(server, keep_last: 3)

        if result[:success]
          deleted = result[:data]&.[](:deleted) || 0
          Rails.logger.info "TaskExecution: Cleaned up #{deleted} old snapshot(s) for #{server.hostname}"
        else
          Rails.logger.warn "TaskExecution: Cleanup failed for #{server.hostname}: #{result[:error]}"
        end
      rescue StandardError => e
        # Don't fail the job if cleanup fails
        Rails.logger.warn "TaskExecution: Cleanup exception for #{server.hostname}: #{e.message}"
      end
    end
  end

  def execute_salt_command(command, minion_ids)
    # Build the Salt command
    target = minion_ids.join(',')
    salt_cmd = build_salt_command(command, target)

    # Calculate timeout based on command type and number of targets
    timeout = calculate_timeout(minion_ids.count, command)
    Rails.logger.info "Executing Salt command: #{salt_cmd} (timeout: #{timeout}s for #{minion_ids.count} targets)"

    # Execute via Open3 with timeout
    require 'open3'
    require 'timeout'

    begin
      Timeout.timeout(timeout) do
        stdout, stderr, status = Open3.capture3(salt_cmd)

        # Parse raw JSON data regardless of exit status
        # Salt returns exit code 1 for many reasons: minion offline, command failed, etc.
        raw_data = begin
          JSON.parse(stdout)
        rescue JSON::ParserError
          nil
        end

        if status.success?
          {
            success: true,
            output: parse_salt_output(stdout, command),
            raw_data: raw_data
          }
        elsif raw_data && raw_data.any?
          # We have results despite non-zero exit code
          # Categorize responses: actual data, errors, or non-responding
          results = categorize_salt_responses(raw_data)

          if results[:with_data].any?
            # We have actual results from at least one minion
            output = parse_salt_output(stdout, command)

            # Add warnings for problematic minions
            warnings = []

            if results[:not_responding].any?
              warnings << "⚠️ #{results[:not_responding].size} minion(s) did not respond:"
              warnings += results[:not_responding].map { |m| "  • #{m}" }
            end

            if results[:with_errors].any?
              warnings << "⚠️ #{results[:with_errors].size} minion(s) returned errors:"
              results[:with_errors].each do |minion, error|
                warnings << "  • #{minion}: #{error.to_s.truncate(100)}"
              end
            end

            output += "\n\n" + warnings.join("\n") if warnings.any?

            {
              success: true,
              output: output,
              raw_data: raw_data,
              partial: results[:not_responding].any? || results[:with_errors].any?
            }
          elsif results[:with_errors].any?
            # All minions returned errors
            error_details = results[:with_errors].map { |m, e| "#{m}: #{e.to_s.truncate(100)}" }.join("\n")
            {
              success: false,
              error: "All minions returned errors:\n#{error_details}"
            }
          else
            # No minions responded at all
            {
              success: false,
              error: "No minions responded. All targeted minions may be offline or unreachable."
            }
          end
        else
          # No parseable results - check if stderr has useful info
          error_msg = stderr.presence || stdout.presence || "Unknown error"
          # Strip common Salt wrapper messages to get to the real error
          error_msg = error_msg.gsub(/ERROR: Minions returned with non-zero exit code\n?/, '').strip
          error_msg = "Command failed with no output" if error_msg.empty?

          {
            success: false,
            error: "Command failed: #{error_msg}"
          }
        end
      end
    rescue Timeout::Error
      {
        success: false,
        error: "Command timed out after #{timeout} seconds. Try targeting fewer servers or specific groups."
      }
    end
  rescue StandardError => e
    {
      success: false,
      error: "Execution error: #{e.message}"
    }
  end

  # Categorize Salt responses into: with_data, with_errors, not_responding
  def categorize_salt_responses(raw_data)
    with_data = {}
    with_errors = {}
    not_responding = []

    raw_data.each do |minion, response|
      if response.nil? || response == false
        # Minion didn't respond
        not_responding << minion
      elsif response.is_a?(String) && is_salt_error_string?(response)
        # Salt returned an error string
        with_errors[minion] = response
      elsif response.is_a?(Hash) && response.key?('retcode') && response['retcode'] != 0
        # Command returned non-zero exit code
        error_msg = response['stderr'] || response['stdout'] || response['comment'] || 'Non-zero exit code'
        with_errors[minion] = error_msg
      else
        # Actual data (including empty hashes which mean "no changes needed")
        with_data[minion] = response
      end
    end

    { with_data: with_data, with_errors: with_errors, not_responding: not_responding }
  end

  # Check if a string response is a Salt error message
  def is_salt_error_string?(str)
    error_patterns = [
      /Minion did not return/i,
      /No response/i,
      /Timed out/i,
      /not connected/i,
      /Unable to connect/i,
      /Authentication error/i,
      /Minion .* is not responding/i,
      /Salt request timed out/i
    ]

    error_patterns.any? { |pattern| str.match?(pattern) }
  end

  def build_salt_command(command, target)
    # Check if command looks like a Salt module call
    if command.match?(/^\w+\.\w+/)
      # It's a Salt module command (e.g., pkg.upgrade, disk.usage)
      parts = command.split(' ', 2)
      module_function = parts[0]
      args = parts[1] || ''

      # --static combines all minion results into a single JSON object
      "sudo salt -L '#{target}' #{module_function} #{args} --output=json --static"
    else
      # It's a shell command to run via cmd.run
      escaped_cmd = command.gsub("'", "'\\''")
      "sudo salt -L '#{target}' cmd.run '#{escaped_cmd}' --output=json --static"
    end
  end

  def parse_salt_output(output, command = nil)
    # Try to parse JSON output
    begin
      result = JSON.parse(output)
      format_json_output(result, command)
    rescue JSON::ParserError
      # Fallback to raw output
      output
    end
  end

  def format_json_output(result, command = nil)
    output = []

    result.each do |minion, response|
      output << "━━━ #{minion} ━━━"
      output << ""

      # Handle different Salt response formats
      if response.is_a?(Hash)
        # Empty hash - command succeeded with no output (check this FIRST)
        if response.empty?
          output << interpret_empty_response(command)
        # Check for Salt error format (explicit errors)
        elsif response['ret'] == false || (response.key?('retcode') && response['retcode'] != 0)
          output << "❌ ERROR"
          output << "Message: #{response['comment'] || response['stderr'] || 'Command failed'}"
          output << "Return code: #{response['retcode']}" if response['retcode']
        # Check if response has nested result
        elsif response.key?('return') || response.key?('ret')
          actual_result = response['return'] || response['ret']
          output << format_result_data(actual_result)
        # Has data - show it formatted
        else
          output << format_result_data(response)
        end
      elsif response.is_a?(String)
        output << response.strip
      elsif response.is_a?(Array)
        response.each { |item| output << "  • #{item}" }
      elsif response == true
        output << "✓ Success"
      elsif response == false
        output << "❌ Failed"
      else
        output << response.to_s
      end

      output << ""
    end

    output.join("\n")
  end

  def format_result_data(data)
    lines = []

    case data
    when String
      lines << data.strip
    when Hash
      if data.empty?
        lines << "✓ Command completed successfully (no output)"
      # Try intelligent formatting for known data structures
      elsif formatted = format_known_structure(data)
        lines << formatted
      elsif data.size <= 5
        # Small hash - show inline
        data.each do |key, value|
          lines << "#{key}: #{format_value(value)}"
        end
      else
        # Large hash - show formatted JSON (last resort)
        lines << JSON.pretty_generate(data)
      end
    when Array
      if data.empty?
        lines << "(empty list)"
      else
        data.each_with_index do |item, idx|
          lines << "#{idx + 1}. #{format_value(item)}"
        end
      end
    when TrueClass
      lines << "✓ True"
    when FalseClass
      lines << "✗ False"
    when NilClass
      lines << "(null)"
    else
      lines << data.to_s
    end

    lines.join("\n")
  end

  # Format known data structures in human-readable way
  def format_known_structure(data)
    # Memory information (from /proc/meminfo or status.meminfo)
    if data.key?('MemTotal') && data.key?('MemFree')
      return format_memory_info(data)
    end

    # Package upgrade results (hash of package => {old: version, new: version})
    if data.values.first.is_a?(Hash) && data.values.first.key?('old') && data.values.first.key?('new')
      return format_package_upgrades(data)
    end

    # Disk usage information (from disk.usage)
    if data.values.first.is_a?(Hash) && data.values.first.key?('1K-blocks') && data.values.first.key?('used')
      return format_disk_usage(data)
    end

    # Package list (hash of package => version)
    if data.size > 10 && data.values.all? { |v| v.is_a?(String) && v.match?(/^\d/) }
      return format_package_list(data)
    end

    nil # No special formatting found
  end

  def format_memory_info(data)
    lines = []

    # Convert kB to GB for readability
    mem_total_gb = data['MemTotal']['value'].to_f / 1024 / 1024
    mem_free_gb = data['MemFree']['value'].to_f / 1024 / 1024
    mem_available_gb = data['MemAvailable']['value'].to_f / 1024 / 1024
    cached_gb = data['Cached']['value'].to_f / 1024 / 1024
    buffers_gb = data['Buffers']['value'].to_f / 1024 / 1024

    mem_used_gb = mem_total_gb - mem_free_gb
    mem_used_percent = (mem_used_gb / mem_total_gb * 100).round(1)

    lines << "Memory Summary:"
    lines << "  Total:     #{mem_total_gb.round(2)} GB"
    lines << "  Used:      #{mem_used_gb.round(2)} GB (#{mem_used_percent}%)"
    lines << "  Free:      #{mem_free_gb.round(2)} GB"
    lines << "  Available: #{mem_available_gb.round(2)} GB"
    lines << "  Cached:    #{cached_gb.round(2)} GB"
    lines << "  Buffers:   #{buffers_gb.round(2)} GB"

    if data['SwapTotal']
      swap_total_gb = data['SwapTotal']['value'].to_f / 1024 / 1024
      swap_free_gb = data['SwapFree']['value'].to_f / 1024 / 1024
      swap_used_gb = swap_total_gb - swap_free_gb

      lines << ""
      lines << "Swap:"
      if swap_total_gb > 0
        swap_used_percent = (swap_used_gb / swap_total_gb * 100).round(1)
        lines << "  Total:     #{swap_total_gb.round(2)} GB"
        lines << "  Used:      #{swap_used_gb.round(2)} GB (#{swap_used_percent}%)"
        lines << "  Free:      #{swap_free_gb.round(2)} GB"
      else
        lines << "  No swap configured"
      end
    end

    lines.join("\n")
  end

  def format_package_upgrades(data)
    lines = []
    lines << "✓ Upgraded #{data.size} package#{'s' if data.size != 1}:"
    lines << ""

    # Find the longest package name for alignment
    max_name_length = data.keys.map(&:length).max
    max_old_length = data.values.map { |v| v['old'].to_s.length }.max

    data.each do |package, versions|
      old_version = versions['old']
      new_version = versions['new']

      lines << sprintf("  %-#{max_name_length}s  %-#{max_old_length}s  →  %s",
                      package, old_version, new_version)
    end

    lines.join("\n")
  end

  def format_disk_usage(data)
    lines = []
    lines << "Disk Usage:"
    lines << ""
    lines << sprintf("%-30s %10s %10s %10s %8s", "Mount Point", "Size", "Used", "Available", "Use%")
    lines << "-" * 75

    # Filter out small tmpfs mounts and docker overlays to reduce clutter
    main_mounts = data.select do |mount, info|
      # Keep main filesystems
      next true if mount == '/' || mount.start_with?('/boot') || mount.start_with?('/home')
      # Keep large tmpfs (> 100MB)
      total_kb = info['1K-blocks'].to_f
      next true if total_kb > 100000
      # Skip docker overlays and tiny tmpfs
      false
    end

    main_mounts.each do |mount, info|
      # Convert from KB to GB
      total_gb = info['1K-blocks'].to_f / 1024 / 1024
      used_gb = info['used'].to_f / 1024 / 1024
      avail_gb = info['available'].to_f / 1024 / 1024
      capacity = info['capacity'] # Already a string like "31%"

      # Truncate long mount paths
      display_mount = mount.length > 30 ? mount[0..26] + "..." : mount

      lines << sprintf("%-30s %8.1fG %8.1fG %10.1fG %8s",
                      display_mount, total_gb, used_gb, avail_gb, capacity)
    end

    # Show count of filtered mounts if any
    filtered_count = data.size - main_mounts.size
    if filtered_count > 0
      lines << ""
      lines << "  (#{filtered_count} temporary/overlay filesystem#{'s' if filtered_count != 1} hidden)"
    end

    lines.join("\n")
  end

  def format_package_list(data)
    lines = []
    lines << "Packages (#{data.size} total):"
    lines << ""

    # Show first 20 packages
    data.first(20).each do |pkg, version|
      lines << "  #{pkg.ljust(40)} #{version}"
    end

    if data.size > 20
      lines << ""
      lines << "  ... and #{data.size - 20} more packages"
      lines << "  (showing first 20 of #{data.size})"
    end

    lines.join("\n")
  end

  def format_value(value)
    case value
    when Hash
      value.size <= 3 ? value.inspect : "(#{value.size} items)"
    when Array
      value.size <= 3 ? value.join(", ") : "(#{value.size} items)"
    when String
      value.length > 100 ? "#{value[0..100]}..." : value
    else
      value.to_s
    end
  end

  def interpret_empty_response(command)
    return "✓ Command completed successfully (no output)" unless command

    case command
    when /pkg\.list_upgrades?/
      "✓ No updates available - system is up to date"
    when /pkg\.upgrade/
      "✓ System updated successfully - no packages needed upgrading"
    when /test\.ping/
      "✓ Server is responding"
    when /disk\.usage/
      "✓ Command completed (no disk usage data returned)"
    when /service\.(status|restart|start|stop)/
      "✓ Service command completed successfully"
    when /network\.ping/
      "✓ Network connectivity check completed"
    else
      "✓ Command completed successfully (no output)"
    end
  end

  def format_output(output)
    # Ensure output is properly formatted and not too large
    formatted = output.to_s

    # Truncate if too large (e.g., > 1MB)
    max_size = 1.megabyte
    if formatted.bytesize > max_size
      truncated_size = max_size - 1000 # Leave room for truncation message
      formatted = formatted.byteslice(0, truncated_size)
      formatted += "\n\n[Output truncated - exceeded #{max_size / 1024}KB limit]"
    end

    formatted
  end

  # Check thresholds and send Gotify alerts if exceeded
  def check_thresholds_and_alert(task, raw_data)
    return unless raw_data.is_a?(Hash)

    alerts = []

    raw_data.each do |server_name, data|
      next unless data.is_a?(Hash)

      # Check disk usage thresholds (data is a hash of mount points)
      if task.disk_usage_threshold && data.values.first.is_a?(Hash) && data.values.first.key?('1K-blocks')
        alerts.concat(check_disk_thresholds(server_name, data, task.disk_usage_threshold))
      end

      # Check memory usage thresholds
      if task.memory_usage_threshold && data.key?('MemTotal')
        alert = check_memory_threshold(server_name, data, task.memory_usage_threshold)
        alerts << alert if alert
      end
    end

    # Send Gotify alert if any thresholds exceeded
    if alerts.any?
      send_threshold_alert(task, alerts)
    end
  rescue StandardError => e
    Rails.logger.error "TaskExecution: Error checking thresholds: #{e.message}"
  end

  def check_disk_thresholds(server_name, disk_data, threshold)
    alerts = []

    disk_data.each do |mount, info|
      next unless info.is_a?(Hash) && info.key?('capacity')

      # Extract percentage from capacity string (e.g., "85%")
      usage_percent = info['capacity'].to_i

      if usage_percent >= threshold
        total_gb = (info['1K-blocks'].to_f / 1024 / 1024).round(2)
        avail_gb = (info['available'].to_f / 1024 / 1024).round(2)

        alerts << {
          server: server_name,
          type: 'disk',
          mount: mount,
          usage: usage_percent,
          threshold: threshold,
          total: total_gb,
          available: avail_gb
        }
      end
    end

    alerts
  end

  def check_memory_threshold(server_name, mem_data, threshold)
    mem_total_kb = mem_data['MemTotal']['value'].to_f
    mem_free_kb = mem_data['MemFree']['value'].to_f

    mem_used_kb = mem_total_kb - mem_free_kb
    usage_percent = ((mem_used_kb / mem_total_kb) * 100).round(1)

    if usage_percent >= threshold
      {
        server: server_name,
        type: 'memory',
        usage: usage_percent,
        threshold: threshold,
        total_gb: (mem_total_kb / 1024 / 1024).round(2),
        used_gb: (mem_used_kb / 1024 / 1024).round(2),
        free_gb: (mem_free_kb / 1024 / 1024).round(2)
      }
    end
  end

  def send_threshold_alert(task, alerts)
    return unless GotifyNotificationService.enabled?

    message_lines = []
    message_lines << "**Task:** #{task.name}"
    message_lines << ""

    alerts.each do |alert|
      if alert[:type] == 'disk'
        message_lines << "**[DISK] #{alert[:server]}:#{alert[:mount]}**"
        message_lines << "  Usage: **#{alert[:usage]}%** (threshold: #{alert[:threshold]}%)"
        message_lines << "  Total: #{alert[:total]}GB | Available: #{alert[:available]}GB"
      elsif alert[:type] == 'memory'
        message_lines << "**[MEMORY] #{alert[:server]}**"
        message_lines << "  Usage: **#{alert[:usage]}%** (threshold: #{alert[:threshold]}%)"
        message_lines << "  Total: #{alert[:total_gb]}GB | Used: #{alert[:used_gb]}GB | Free: #{alert[:free_gb]}GB"
      end
      message_lines << ""
    end

    GotifyNotificationService.send_notification(
      title: "⚠️ Threshold Alert: #{task.name}",
      message: message_lines.join("\n"),
      priority: task.alert_priority || 5,
      extras: {
        task_id: task.id,
        task_name: task.name,
        alert_count: alerts.size
      }
    )
  rescue StandardError => e
    Rails.logger.error "TaskExecution: Failed to send threshold alert: #{e.message}"
  end
end