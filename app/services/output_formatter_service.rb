# frozen_string_literal: true

# Service for formatting Salt command output into human-readable text
# Converts JSON/Hash structures into admin-friendly summaries
class OutputFormatterService
  class << self
    # Main entry point for formatting any Salt command output
    # @param command_type [String] The Salt function called (e.g., 'pkg.list_upgrades', 'cmd.run')
    # @param output [String, Hash, Array] The raw Salt output
    # @param server [Server] The server this output is from
    # @return [String] Human-readable formatted output
    def format(command_type, output, server = nil)
      return "No output" if output.blank?

      case command_type
      when 'pkg.list_upgrades', 'pkg.list_updates'
        format_package_list(output)
      when 'pkg.upgrade', 'pkg.update'
        format_package_upgrade_result(output)
      when 'system.reboot'
        format_reboot_result(output)
      when 'test.ping'
        format_ping_result(output)
      when 'cmd.run'
        format_command_result(output)
      when 'state.apply', 'state.sls'
        format_state_result(output)
      when 'grains.items', 'grains.item'
        format_grains_result(output)
      when 'status.uptime'
        format_uptime_result(output)
      when 'disk.usage'
        format_disk_usage(output)
      when 'service.status'
        format_service_status(output)
      else
        # Fallback: try to intelligently format unknown types
        format_generic(output)
      end
    rescue StandardError => e
      "Error formatting output: #{e.message}\n\nRaw output:\n#{output.inspect}"
    end

    # Format package list (available updates)
    def format_package_list(packages)
      return "No packages available for update" if packages.blank? || packages.empty?

      if packages.is_a?(Hash)
        lines = ["Available Updates (#{packages.size} packages):"]
        lines << "=" * 60

        packages.each do |pkg_name, version_info|
          if version_info.is_a?(Hash)
            old_ver = version_info['old'] || version_info['current'] || 'unknown'
            new_ver = version_info['new'] || version_info['available'] || 'unknown'
            lines << "  #{pkg_name.ljust(40)} #{old_ver} → #{new_ver}"
          elsif version_info.is_a?(String)
            lines << "  #{pkg_name.ljust(40)} → #{version_info}"
          else
            lines << "  #{pkg_name}"
          end
        end

        lines.join("\n")
      elsif packages.is_a?(Array)
        lines = ["Available Updates (#{packages.size} packages):"]
        lines << "=" * 60
        packages.each { |pkg| lines << "  • #{pkg}" }
        lines.join("\n")
      else
        packages.to_s
      end
    end

    # Format package upgrade results
    def format_package_upgrade_result(result)
      return "No upgrade information available" if result.blank?

      if result.is_a?(Hash)
        lines = []

        # Check for changes
        if result['changes'].present?
          changes = result['changes']
          upgraded = changes.select { |_k, v| v.is_a?(Hash) && v['new'].present? }

          if upgraded.any?
            lines << "✅ Successfully upgraded #{upgraded.size} packages:"
            lines << "=" * 60
            upgraded.each do |pkg_name, versions|
              old_ver = versions['old'] || 'unknown'
              new_ver = versions['new'] || 'unknown'
              lines << "  #{pkg_name.ljust(40)} #{old_ver} → #{new_ver}"
            end
          else
            lines << "✅ System is already up to date"
          end
        elsif result['comment'].present?
          lines << result['comment']
        elsif result['result'] == true
          lines << "✅ Updates applied successfully"
        elsif result['result'] == false
          lines << "❌ Update failed: #{result['comment'] || 'Unknown error'}"
        else
          lines << format_generic(result)
        end

        lines.join("\n")
      else
        result.to_s
      end
    end

    # Format reboot command result
    def format_reboot_result(output)
      if output.is_a?(Hash) && output['result'] == true
        "✅ Reboot command sent successfully"
      elsif output == true || output.to_s.include?('reboot')
        "✅ System reboot initiated"
      else
        "⚠️ Reboot status: #{output}"
      end
    end

    # Format ping result
    def format_ping_result(output)
      if output == true || output.to_s.downcase == 'true'
        "✅ Minion responding (online)"
      else
        "❌ Minion not responding (offline)"
      end
    end

    # Format command.run result
    def format_command_result(output)
      return "Command executed (no output)" if output.blank?

      if output.is_a?(String)
        # Clean up and format command output
        lines = output.split("\n")
        if lines.size > 50
          # Truncate very long output
          truncated = lines.first(50)
          truncated << "... (#{lines.size - 50} more lines)"
          truncated.join("\n")
        else
          output
        end
      elsif output.is_a?(Hash)
        if output['stdout'].present?
          output['stdout']
        elsif output['result'].present?
          output['result'].to_s
        else
          format_generic(output)
        end
      else
        output.to_s
      end
    end

    # Format state.apply result
    def format_state_result(states)
      return "No state changes" if states.blank?

      if states.is_a?(Hash)
        lines = ["State Application Results:"]
        lines << "=" * 60

        succeeded = 0
        failed = 0

        states.each do |state_id, state_result|
          next if state_id == 'retcode' # Skip metadata

          if state_result.is_a?(Hash)
            result = state_result['result']
            comment = state_result['comment']
            changes = state_result['changes']

            if result == true
              succeeded += 1
              status = "✅"
            else
              failed += 1
              status = "❌"
            end

            lines << "\n#{status} #{state_id}"
            lines << "   #{comment}" if comment.present?

            if changes.present? && changes.any?
              lines << "   Changes:"
              format_changes(changes).each { |line| lines << "     #{line}" }
            end
          end
        end

        lines.unshift("\nSummary: #{succeeded} succeeded, #{failed} failed")
        lines.join("\n")
      else
        states.to_s
      end
    end

    # Format grains (server metadata)
    def format_grains_result(grains)
      return "No grains data" if grains.blank?

      if grains.is_a?(Hash)
        lines = ["Server Information:"]
        lines << "=" * 60

        # Format common grains
        important_grains = {
          'os' => 'Operating System',
          'osrelease' => 'OS Release',
          'osfullname' => 'OS Full Name',
          'kernel' => 'Kernel',
          'kernelrelease' => 'Kernel Release',
          'num_cpus' => 'CPU Cores',
          'mem_total' => 'Total Memory',
          'fqdn' => 'Hostname (FQDN)',
          'ip4_interfaces' => 'IP Addresses',
          'host' => 'Hostname'
        }

        important_grains.each do |key, label|
          next unless grains[key].present?

          value = if key == 'mem_total' && grains[key].is_a?(Numeric)
                    "#{(grains[key] / 1024.0).round(1)} GB"
                  elsif key == 'ip4_interfaces' && grains[key].is_a?(Hash)
                    grains[key].map { |iface, ips| "#{iface}: #{ips.join(', ')}" }.join('; ')
                  else
                    grains[key].to_s
                  end

          lines << "  #{label.ljust(20)}: #{value}"
        end

        lines.join("\n")
      else
        grains.to_s
      end
    end

    # Format uptime result
    def format_uptime_result(uptime)
      return "Uptime data unavailable" if uptime.blank?

      if uptime.is_a?(Numeric)
        seconds = uptime.to_i
        days = seconds / 86400
        hours = (seconds % 86400) / 3600
        minutes = (seconds % 3600) / 60

        parts = []
        parts << "#{days} days" if days > 0
        parts << "#{hours} hours" if hours > 0
        parts << "#{minutes} minutes" if minutes > 0

        "⏱️  Uptime: #{parts.join(', ')}"
      else
        uptime.to_s
      end
    end

    # Format disk usage
    def format_disk_usage(disk_data)
      return "No disk data" if disk_data.blank?

      if disk_data.is_a?(Hash)
        lines = ["Disk Usage:"]
        lines << "=" * 60

        disk_data.each do |mount_point, usage|
          if usage.is_a?(Hash)
            total = usage['total']
            used = usage['used']
            available = usage['available']
            percent = usage['capacity']

            lines << "\n#{mount_point}:"
            lines << "  Total:     #{format_bytes(total)}" if total
            lines << "  Used:      #{format_bytes(used)} (#{percent})" if used && percent
            lines << "  Available: #{format_bytes(available)}" if available
          end
        end

        lines.join("\n")
      else
        disk_data.to_s
      end
    end

    # Format service status
    def format_service_status(status)
      if status == true || status.to_s.include?('running')
        "✅ Service is running"
      elsif status == false || status.to_s.include?('stopped')
        "⏸️  Service is stopped"
      else
        "Status: #{status}"
      end
    end

    # Generic formatter for unknown types
    def format_generic(output)
      if output.is_a?(Hash)
        # Try to extract meaningful data from hash
        if output['result'].present? && output['comment'].present?
          result_icon = output['result'] == true ? "✅" : "❌"
          "#{result_icon} #{output['comment']}"
        elsif output.size < 10
          # Small hash - format as key-value pairs
          output.map { |k, v| "#{k}: #{v}" }.join("\n")
        else
          # Large hash - format as JSON
          JSON.pretty_generate(output)
        end
      elsif output.is_a?(Array)
        output.join("\n")
      elsif output.is_a?(TrueClass) || output.is_a?(FalseClass)
        output ? "✅ Success" : "❌ Failed"
      else
        output.to_s
      end
    end

    private

    # Format state changes (nested hash)
    def format_changes(changes, indent = 0)
      lines = []
      prefix = "  " * indent

      changes.each do |key, value|
        if value.is_a?(Hash) && (value['old'].present? || value['new'].present?)
          old_val = value['old'] || '(none)'
          new_val = value['new'] || '(none)'
          lines << "#{prefix}#{key}: #{old_val} → #{new_val}"
        elsif value.is_a?(Hash)
          lines << "#{prefix}#{key}:"
          lines.concat(format_changes(value, indent + 1))
        elsif value.is_a?(Array)
          lines << "#{prefix}#{key}: #{value.join(', ')}"
        else
          lines << "#{prefix}#{key}: #{value}"
        end
      end

      lines
    end

    # Format bytes to human-readable size
    def format_bytes(bytes)
      return bytes.to_s unless bytes.is_a?(Numeric)

      units = ['B', 'KB', 'MB', 'GB', 'TB']
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.size - 1
        size /= 1024.0
        unit_index += 1
      end

      "#{size.round(1)} #{units[unit_index]}"
    end
  end
end
