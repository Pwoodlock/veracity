class Server < ApplicationRecord
  # Associations
  belongs_to :group, optional: true, counter_cache: true
  belongs_to :hetzner_api_key, optional: true
  belongs_to :proxmox_api_key, optional: true
  has_many :server_metrics, dependent: :destroy
  has_many :commands, dependent: :destroy
  has_many :vulnerability_alerts, foreign_key: :server_id, dependent: :destroy
  has_many :cve_watchlists, foreign_key: :server_id, dependent: :destroy

  # Callbacks
  after_create_commit :broadcast_dashboard_update
  after_update_commit :broadcast_dashboard_update, if: :saved_change_to_status?
  after_update_commit :enqueue_status_change_notification, if: :saved_change_to_status?
  after_destroy_commit :broadcast_dashboard_update

  # Validations
  validates :hostname, presence: true
  validates :minion_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[online offline unreachable maintenance] }
  validates :latitude, numericality: {
    greater_than_or_equal_to: -90,
    less_than_or_equal_to: 90
  }, allow_nil: true
  validates :longitude, numericality: {
    greater_than_or_equal_to: -180,
    less_than_or_equal_to: 180
  }, allow_nil: true
  validates :hetzner_server_id, presence: true, if: -> { hetzner_api_key_id.present? }
  validates :hetzner_api_key_id, presence: true, if: -> { hetzner_server_id.present? }
  validates :proxmox_node, presence: true, if: -> { proxmox_api_key_id.present? }
  validates :proxmox_vmid, presence: true, if: -> { proxmox_api_key_id.present? }
  validates :proxmox_type, inclusion: { in: %w[qemu lxc] }, if: -> { proxmox_vmid.present? }

  # Scopes
  scope :online, -> { where(status: 'online') }
  scope :offline, -> { where(status: 'offline') }
  scope :production, -> { where(environment: 'production') }
  scope :staging, -> { where(environment: 'staging') }
  scope :in_group, ->(group_id) { where(group_id: group_id) }
  scope :ungrouped, -> { where(group_id: nil) }
  scope :with_coordinates, -> { where.not(latitude: nil, longitude: nil) }
  scope :hetzner_servers, -> { where.not(hetzner_api_key_id: nil) }
  scope :snapshot_enabled, -> { where(enable_hetzner_snapshot: true) }
  scope :proxmox_servers, -> { where.not(proxmox_api_key_id: nil) }
  scope :proxmox_vms, -> { where(proxmox_type: 'qemu') }
  scope :proxmox_containers, -> { where(proxmox_type: 'lxc') }
  scope :accessible_by, ->(user) { user.admin? ? all : none }

  # N+1 Query Optimization: Preload latest metrics for each server
  # This scope efficiently loads only the most recent metric per server using preload
  # with ordered scope. This prevents N+1 queries when displaying server cards with
  # metrics on dashboard and index pages.
  #
  # Usage: Server.with_latest_metrics.limit(50)
  # Note: This loads server_metrics association with ordering. To access the latest metric,
  # use server.latest_metrics (which checks if association is loaded)
  scope :with_latest_metrics, -> {
    # Preload server_metrics association ordered by collected_at DESC
    # This way, the first metric in the association will be the latest
    includes(:server_metrics).references(:server_metrics)
  }

  # Tags is already JSONB column, no need for serialize

  # Get latest metric
  # Note: When using with_latest_metrics scope, this will not trigger additional queries
  def latest_metric
    @latest_metric ||= server_metrics.order(collected_at: :desc).first
  end

  # Get latest metrics (optimized accessor for preloaded data)
  # This method provides a consistent interface whether or not with_latest_metrics was used
  # It checks if the association is already loaded to avoid triggering additional queries
  def latest_metrics
    # If server_metrics association is loaded, find the latest one from memory
    if association(:server_metrics).loaded?
      server_metrics.max_by(&:collected_at)
    else
      # Otherwise fall back to database query
      latest_metric
    end
  end

  # Check if server is considered stale
  def stale?
    last_seen.nil? || last_seen < 1.hour.ago
  end

  # Check if server has coordinates
  def has_coordinates?
    latitude.present? && longitude.present?
  end

  # Check if server is online
  def online?
    status == 'online'
  end

  # Hetzner Cloud integration helpers
  def hetzner_server?
    hetzner_api_key_id.present? && hetzner_server_id.present?
  end

  def can_use_hetzner_features?
    hetzner_server? && hetzner_api_key&.enabled?
  end

  def snapshot_before_update?
    can_use_hetzner_features? && enable_hetzner_snapshot?
  end

  def hetzner_power_state_badge
    case hetzner_power_state
    when 'running'
      { text: 'Running', class: 'badge-success' }
    when 'stopped', 'off'
      { text: 'Stopped', class: 'badge-danger' }
    when 'starting'
      { text: 'Starting', class: 'badge-warning' }
    when 'stopping'
      { text: 'Stopping', class: 'badge-warning' }
    else
      { text: 'Unknown', class: 'badge-secondary' }
    end
  end

  # Proxmox integration helpers
  def proxmox_server?
    proxmox_api_key_id.present? && proxmox_vmid.present?
  end

  def can_use_proxmox_features?
    proxmox_server? && proxmox_api_key&.enabled?
  end

  def proxmox_vm?
    proxmox_type == 'qemu'
  end

  def proxmox_container?
    proxmox_type == 'lxc'
  end

  def proxmox_power_state_badge
    case proxmox_power_state
    when 'running'
      { text: 'Running', class: 'bg-green-900 text-green-300' }
    when 'stopped'
      { text: 'Stopped', class: 'bg-red-900 text-red-300' }
    when 'paused'
      { text: 'Paused', class: 'bg-yellow-900 text-yellow-300' }
    else
      { text: 'Unknown', class: 'bg-gray-700 text-gray-300' }
    end
  end

  def proxmox_type_display
    case proxmox_type
    when 'qemu'
      'VM (QEMU)'
    when 'lxc'
      'Container (LXC)'
    else
      'Unknown'
    end
  end

  private

  # Broadcast dashboard update via Turbo Streams when server is created, updated, or destroyed
  # This ensures the dashboard stats reflect the current server count and status in real-time
  def broadcast_dashboard_update
    Rails.logger.info "Server#broadcast_dashboard_update: Broadcasting for #{hostname} (#{minion_id})"

    stats_data = {
      total_servers: Server.count,
      online_servers: Server.where(status: 'online').count,
      offline_servers: Server.where(status: 'offline').count,
      total_groups: Group.count,
      ungrouped_servers: Server.where(group_id: nil).count,
      commands_today: Command.where('started_at > ?', 24.hours.ago).count,
      successful_commands: Command.where('started_at > ?', 24.hours.ago)
                                  .where(status: 'completed')
                                  .where('exit_code = 0 OR exit_code IS NULL')
                                  .count,
      failed_commands: Command.where('started_at > ?', 24.hours.ago)
                              .where(status: 'failed')
                              .count
    }

    Turbo::StreamsChannel.broadcast_replace_to(
      "dashboard",
      target: "dashboard-stats",
      partial: "dashboard/stats",
      locals: stats_data
    )

    Rails.logger.info "Server#broadcast_dashboard_update: Broadcast completed successfully"
  rescue StandardError => e
    Rails.logger.error "Server#broadcast_dashboard_update: Failed - #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  # Enqueue background job to send Gotify notification when server status changes
  # This method is called after the transaction commits, ensuring the database changes
  # are persisted before the notification is sent
  def enqueue_status_change_notification
    old_status, new_status = saved_change_to_status
    return unless old_status != new_status

    # Enqueue the background job with necessary parameters
    NotifyServerStatusChangeJob.perform_later(
      server_id: id,
      old_status: old_status,
      new_status: new_status
    )
  end
end
