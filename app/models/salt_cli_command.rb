class SaltCliCommand < ApplicationRecord
  belongs_to :user

  validates :command, presence: true
  validates :status, inclusion: { in: %w[pending running completed failed] }

  scope :recent, -> { order(created_at: :desc) }
  scope :by_user, ->(user) { where(user: user) }

  # Allowed Salt commands (unrestricted for admin)
  ALLOWED_COMMANDS = %w[salt salt-key salt-run salt-call].freeze

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def running?
    status == 'running'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def success?
    completed? && exit_status == 0
  end

  # Extract the base command (salt, salt-key, etc.)
  def base_command
    command.to_s.split.first
  end

  # Validate the command is a Salt command
  def valid_salt_command?
    ALLOWED_COMMANDS.include?(base_command)
  end
end
