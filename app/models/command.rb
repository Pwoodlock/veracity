class Command < ApplicationRecord
  belongs_to :server, optional: true  # Optional for Salt Master commands (salt-key, etc.)
  belongs_to :user, optional: true  # Optional - null for system/automated commands

  # Validations
  validates :command, presence: true
  validates :status, inclusion: { in: %w[pending running completed failed timeout cancelled partial_success] }

  # Scopes
  scope :pending, -> { where(status: 'pending') }
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :timeout, -> { where(status: 'timeout') }
  scope :recent, -> { where('started_at > ?', 1.hour.ago) }
  scope :last_24_hours, -> { where('created_at >= ?', 24.hours.ago) }
  scope :last_7_days, -> { where('created_at >= ?', 7.days.ago) }
  scope :for_server, ->(server_id) { where(server_id: server_id) }
  scope :by_type, ->(type) { where(command_type: type) }

  # Instance methods

  # Get display name for the user who executed the command
  def user_display_name
    return 'System' if user.nil?
    user.name.presence || user.email
  end

  # Check if command was executed by a user (vs system/automated)
  def user_executed?
    user_id.present?
  end

  # Display title for Avo and views
  def display_title
    target = if server.present?
               server.hostname
             elsif command&.start_with?('salt-key', 'salt-run')
               'Salt Master'
             else
               'Multiple Servers'
             end
    "#{command_type || 'Command'} on #{target}"
  end

  # Check if command succeeded
  def succeeded?
    status == 'completed' && (exit_code.nil? || exit_code.zero?)
  end

  # Check if command is still in progress
  def in_progress?
    status.in?(%w[pending running])
  end

  # Check if command is finished
  def finished?
    status.in?(%w[completed failed timeout cancelled partial_success])
  end

  # Duration in human-readable format
  def duration_human
    return 'N/A' unless duration_seconds

    if duration_seconds < 60
      "#{duration_seconds}s"
    elsif duration_seconds < 3600
      minutes = (duration_seconds / 60).to_i
      seconds = (duration_seconds % 60).to_i
      "#{minutes}m #{seconds}s"
    else
      hours = (duration_seconds / 3600).to_i
      minutes = ((duration_seconds % 3600) / 60).to_i
      "#{hours}h #{minutes}m"
    end
  end

  # Badge color for status display
  def status_badge_color
    case status
    when 'completed'
      succeeded? ? 'green' : 'yellow'
    when 'partial_success'
      'yellow'
    when 'running'
      'blue'
    when 'pending'
      'gray'
    when 'failed', 'timeout'
      'red'
    when 'cancelled'
      'yellow'
    else
      'gray'
    end
  end

  # Get truncated output for display
  def output_preview(length = 200)
    return 'No output' if output.blank?

    output.length > length ? "#{output[0...length]}..." : output
  end

  # Get truncated error output for display
  def error_preview(length = 200)
    return nil if error_output.blank?

    error_output.length > length ? "#{error_output[0...length]}..." : error_output
  end

  # Check if command has error output
  def has_errors?
    error_output.present? || (exit_code.present? && exit_code != 0)
  end
end
