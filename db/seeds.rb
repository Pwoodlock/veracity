# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# For sample data management, we use dedicated rake tasks
# This allows easy addition and removal of test data without affecting real servers

puts "\n========================================="
puts "Database Seed File"
puts "========================================="
puts ""
puts "This seed file is kept minimal to avoid conflicts with real data."
puts ""
puts "For sample/test data, use these commands:"
puts ""
puts "  rails sample_data:add     # Add sample servers and data"
puts "  rails sample_data:list    # List current sample data"
puts "  rails sample_data:remove  # Remove all sample data"
puts "  rails sample_data:refresh # Refresh sample data (remove & re-add)"
puts ""
puts "Sample data is marked with special tags and can be safely removed"
puts "without affecting real servers from Salt minions."
puts "========================================="

# Add any essential seed data here that should always exist
# For example, default configurations, admin users, etc.

# Currently, no essential seed data is required
# The system will create servers automatically when Salt minions connect

# ===========================================
# Task Templates - Pre-built Salt commands
# ===========================================

puts "\nSeeding Task Templates..."

task_templates = [
  # System Monitoring
  {
    name: "System Update (pkg.upgrade)",
    command_template: "pkg.upgrade",
    description: "Upgrade all packages to latest versions",
    category: "updates"
  },
  {
    name: "Check Available Updates",
    command_template: "pkg.list_upgrades",
    description: "List packages with available updates",
    category: "updates"
  },
  {
    name: "System Load Average",
    command_template: "status.loadavg",
    description: "Get CPU load average (1, 5, 15 min)",
    category: "monitoring"
  },
  {
    name: "System Uptime",
    command_template: "status.uptime",
    description: "Get system uptime information",
    category: "monitoring"
  },
  {
    name: "Memory Info",
    command_template: "status.meminfo",
    description: "Get detailed memory usage information",
    category: "monitoring"
  },
  {
    name: "OS Information",
    command_template: "grains.item os osrelease kernelrelease",
    description: "Get OS and kernel version details",
    category: "monitoring"
  },
  {
    name: "Top Processes",
    command_template: "ps.top num_processes=10",
    description: "Show top 10 processes by CPU usage",
    category: "monitoring"
  },

  # Disk & Storage
  {
    name: "Disk Usage",
    command_template: "disk.usage",
    description: "Get disk space usage for all mounted filesystems",
    category: "monitoring"
  },
  {
    name: "Inode Usage",
    command_template: "disk.inodeusage",
    description: "Check inode usage (important for many small files)",
    category: "monitoring"
  },
  {
    name: "Log Directory Sizes",
    command_template: "cmd.run 'du -sh /var/log/* 2>/dev/null | sort -hr | head -20'",
    description: "Show sizes of log directories",
    category: "maintenance"
  },

  # Service Management
  {
    name: "Running Services",
    command_template: "service.get_running",
    description: "List all currently running services",
    category: "monitoring"
  },
  {
    name: "Enabled Services",
    command_template: "service.get_enabled",
    description: "List all enabled services",
    category: "monitoring"
  },
  {
    name: "Check Service Status",
    command_template: "service.status {{service_name}}",
    description: "Check status of a specific service",
    category: "maintenance",
    default_parameters: { "service_name" => "nginx" }
  },
  {
    name: "Restart Service",
    command_template: "service.restart {{service_name}}",
    description: "Restart a specific service",
    category: "maintenance",
    default_parameters: { "service_name" => "nginx" }
  },

  # Security
  {
    name: "List System Users",
    command_template: "user.list_users",
    description: "List all system user accounts",
    category: "security"
  },
  {
    name: "Recent Logins",
    command_template: "cmd.run 'last -20'",
    description: "Show last 20 login sessions",
    category: "security"
  },
  {
    name: "Open Ports",
    command_template: "cmd.run 'ss -tlnp'",
    description: "List all listening ports and services",
    category: "security"
  },
  {
    name: "Failed Login Attempts",
    command_template: "cmd.run 'grep \"Failed password\" /var/log/auth.log 2>/dev/null | tail -20 || grep \"Failed password\" /var/log/secure 2>/dev/null | tail -20'",
    description: "Show recent failed SSH login attempts",
    category: "security"
  },

  # Network
  {
    name: "Network Interfaces",
    command_template: "network.interfaces",
    description: "Get network interface details",
    category: "monitoring"
  },
  {
    name: "IP Addresses",
    command_template: "network.ip_addrs",
    description: "List all IP addresses",
    category: "monitoring"
  },
  {
    name: "Connectivity Test",
    command_template: "cmd.run 'ping -c 3 8.8.8.8'",
    description: "Test internet connectivity",
    category: "monitoring"
  },

  # Logs & Troubleshooting
  {
    name: "Recent System Errors",
    command_template: "cmd.run 'journalctl -p err -n 50 --no-pager'",
    description: "Show last 50 error-level log entries",
    category: "maintenance"
  },
  {
    name: "Kernel Messages",
    command_template: "cmd.run 'dmesg | tail -50'",
    description: "Show recent kernel messages",
    category: "maintenance"
  },
  {
    name: "System Reboot History",
    command_template: "cmd.run 'last reboot | head -10'",
    description: "Show recent system reboots",
    category: "maintenance"
  },

  # Backups
  {
    name: "Check Disk Space for Backups",
    command_template: "cmd.run 'df -h /var/backups 2>/dev/null || df -h /'",
    description: "Check available space for backups",
    category: "backups"
  }
]

task_templates.each do |template_attrs|
  TaskTemplate.find_or_create_by!(name: template_attrs[:name]) do |template|
    template.command_template = template_attrs[:command_template]
    template.description = template_attrs[:description]
    template.category = template_attrs[:category]
    template.default_parameters = template_attrs[:default_parameters] || {}
    template.active = true
  end
end

puts "Created #{TaskTemplate.count} task templates"
