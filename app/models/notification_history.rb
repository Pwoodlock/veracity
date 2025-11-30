class NotificationHistory < ApplicationRecord
  # Notification types
  NOTIFICATION_TYPES = %w[
    server_event
    cve_alert
    task_execution
    backup
    user_event
    system_event
  ].freeze

  # Statuses
  STATUSES = %w[pending sent failed].freeze

  # Priorities (Gotify scale: 0-10)
  # 0 = lowest, 5 = normal, 10 = highest/emergency
  PRIORITY_LOW = 2
  PRIORITY_NORMAL = 5
  PRIORITY_HIGH = 7
  PRIORITY_CRITICAL = 10

  # Validations
  validates :notification_type, presence: true, inclusion: { in: NOTIFICATION_TYPES }
  validates :title, presence: true
  validates :message, presence: true
  validates :priority, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }
  validates :status, presence: true, inclusion: { in: STATUSES }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :sent, -> { where(status: 'sent') }
  scope :failed, -> { where(status: 'failed') }
  scope :pending, -> { where(status: 'pending') }
  scope :by_type, ->(type) { where(notification_type: type) }
  scope :last_n, ->(n) { recent.limit(n) }
  scope :today, -> { where('created_at >= ?', Time.current.beginning_of_day) }
  scope :this_week, -> { where('created_at >= ?', Time.current.beginning_of_week) }
  scope :critical, -> { where('priority >= ?', PRIORITY_HIGH) }

  # Mark as sent
  def mark_sent!(gotify_message_id)
    update!(
      status: 'sent',
      sent_at: Time.current,
      gotify_message_id: gotify_message_id
    )
  end

  # Mark as failed
  def mark_failed!(error)
    update!(
      status: 'failed',
      error_message: error.to_s
    )
  end

  # Success rate calculation
  def self.success_rate
    total = count
    return 0 if total.zero?

    (sent.count.to_f / total * 100).round(2)
  end

  # Statistics for dashboard
  def self.statistics
    {
      total_sent: sent.count,
      total_failed: failed.count,
      total_pending: pending.count,
      success_rate: success_rate,
      last_notification: recent.first&.created_at,
      notifications_today: today.count,
      notifications_this_week: this_week.count,
      critical_today: today.critical.count
    }
  end
end
