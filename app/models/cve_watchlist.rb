# frozen_string_literal: true

class CveWatchlist < ApplicationRecord
  # Associations
  belongs_to :server, optional: true
  has_many :vulnerability_alerts, dependent: :destroy

  # Validations
  validates :vendor, presence: true
  validates :product, presence: true
  validates :frequency, inclusion: { in: %w[hourly daily weekly] }
  validates :vendor, uniqueness: { scope: [:product, :server_id] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :global, -> { where(server_id: nil) }
  scope :server_specific, -> { where.not(server_id: nil) }
  scope :due_for_check, -> {
    active.where(
      'last_checked_at IS NULL OR last_checked_at < ?',
      check_interval_threshold
    )
  }

  # Class methods
  def self.check_interval_threshold
    {
      'hourly' => 1.hour.ago,
      'daily' => 1.day.ago,
      'weekly' => 1.week.ago
    }
  end

  # Instance methods
  def display_name
    "#{vendor}/#{product}#{version.present? ? " (#{version})" : ''}"
  end

  def cpe_pattern
    if cpe_string.present?
      cpe_string
    else
      # Build CPE 2.3 pattern
      "cpe:2.3:*:#{vendor}:#{product}:#{version || '*'}:*:*:*:*:*:*:*"
    end
  end

  def due_for_check?
    return true if last_checked_at.nil?

    case frequency
    when 'hourly'
      last_checked_at < 1.hour.ago
    when 'daily'
      last_checked_at < 1.day.ago
    when 'weekly'
      last_checked_at < 1.week.ago
    else
      false
    end
  end

  def check_for_vulnerabilities
    # This will be called by the CVE monitoring service
    CveMonitoringService.check_watchlist(self)
  end

  def mark_checked!
    update!(
      last_checked_at: Time.current,
      last_execution_time: Time.current
    )
  end

  # Create watchlists from server's installed software
  def self.create_from_server(server)
    return unless server.grains.present?

    # Extract OS information
    os_vendor = detect_os_vendor(server.os_family, server.os_name)
    if os_vendor.present? && server.os_name.present?
      find_or_create_by!(
        vendor: os_vendor.downcase,
        product: server.os_name.downcase,
        version: server.os_version,
        server: server,
        description: "#{server.hostname} - OS"
      )
    end

    # Extract installed packages if available
    if server.installed_packages.present?
      create_from_packages(server, server.installed_packages)
    end
  end

  def self.detect_os_vendor(os_family, os_name)
    case os_family&.downcase
    when 'debian', 'ubuntu'
      os_name&.downcase == 'ubuntu' ? 'canonical' : 'debian'
    when 'redhat', 'rhel'
      'redhat'
    when 'centos'
      'centos'
    when 'almalinux'
      'almalinux'
    when 'rocky'
      'rocky'
    when 'suse', 'opensuse'
      'suse'
    when 'arch'
      'arch'
    when 'freebsd'
      'freebsd'
    when 'windows'
      'microsoft'
    else
      nil
    end
  end

  def self.create_from_packages(server, packages)
    # Parse common packages that have CVEs
    important_packages = %w[
      apache2 nginx mysql postgresql redis mongodb
      docker kubernetes openssh openssl curl wget
      php python ruby nodejs java tomcat
      wordpress drupal joomla jenkins gitlab
    ]

    packages.each do |package_name, package_info|
      next unless important_packages.any? { |imp| package_name.downcase.include?(imp) }

      vendor = detect_package_vendor(package_name)
      next unless vendor

      find_or_create_by(
        vendor: vendor,
        product: package_name.downcase,
        version: package_info['version'],
        server: server,
        description: "#{server.hostname} - #{package_name}"
      )
    end
  end

  def self.detect_package_vendor(package_name)
    package_vendors = {
      'apache2' => 'apache',
      'nginx' => 'nginx',
      'mysql' => 'oracle',
      'mariadb' => 'mariadb',
      'postgresql' => 'postgresql',
      'redis' => 'redis',
      'mongodb' => 'mongodb',
      'docker' => 'docker',
      'kubernetes' => 'kubernetes',
      'openssh' => 'openbsd',
      'openssl' => 'openssl',
      'php' => 'php',
      'python' => 'python',
      'ruby' => 'ruby-lang',
      'nodejs' => 'nodejs',
      'java' => 'oracle',
      'tomcat' => 'apache',
      'wordpress' => 'wordpress',
      'drupal' => 'drupal',
      'jenkins' => 'jenkins',
      'gitlab' => 'gitlab'
    }

    package_vendors.each do |key, vendor|
      return vendor if package_name.downcase.include?(key)
    end
    nil
  end

  # Create default global watchlists for common products
  def self.create_default_watchlists
    default_watchlists = [
      { vendor: 'microsoft', product: 'windows_server', description: 'Windows Server (all versions)' },
      { vendor: 'canonical', product: 'ubuntu_linux', description: 'Ubuntu Linux' },
      { vendor: 'debian', product: 'debian_linux', description: 'Debian Linux' },
      { vendor: 'redhat', product: 'enterprise_linux', description: 'Red Hat Enterprise Linux' },
      { vendor: 'centos', product: 'centos', description: 'CentOS Linux' },
      { vendor: 'proxmox', product: 'proxmox_ve', description: 'Proxmox Virtual Environment' },
      { vendor: 'docker', product: 'docker', description: 'Docker Engine' },
      { vendor: 'kubernetes', product: 'kubernetes', description: 'Kubernetes' },
      { vendor: 'apache', product: 'http_server', description: 'Apache HTTP Server' },
      { vendor: 'nginx', product: 'nginx', description: 'NGINX Web Server' },
      { vendor: 'openssl', product: 'openssl', description: 'OpenSSL' },
      { vendor: 'openssh', product: 'openssh', description: 'OpenSSH' },
      { vendor: 'mysql', product: 'mysql', description: 'MySQL Database' },
      { vendor: 'postgresql', product: 'postgresql', description: 'PostgreSQL Database' }
    ]

    default_watchlists.each do |watchlist|
      find_or_create_by!(
        vendor: watchlist[:vendor],
        product: watchlist[:product],
        description: watchlist[:description],
        active: false # Start inactive, let user enable what they need
      )
    end
  end
end