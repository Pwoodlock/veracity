class TaskRun < ApplicationRecord
  belongs_to :task
  belongs_to :user, optional: true # nil for scheduled runs

  validates :status, presence: true, inclusion: {
    in: %w[pending running completed failed cancelled]
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :finished, -> { where(status: %w[completed failed cancelled]) }

  before_save :calculate_duration
  after_update_commit :broadcast_update, if: :saved_change_to_status?

  def pending?
    status == 'pending'
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

  def cancelled?
    status == 'cancelled'
  end

  def finished?
    %w[completed failed cancelled].include?(status)
  end

  def success?
    completed? && (exit_code.nil? || exit_code == 0)
  end

  def mark_as_running!
    update!(
      status: 'running',
      started_at: Time.current
    )
  end

  def mark_as_completed!(output_text, exit_code_val = 0)
    update!(
      status: 'completed',
      completed_at: Time.current,
      output: output_text,
      exit_code: exit_code_val
    )
  end

  def mark_as_failed!(output_text, exit_code_val = 1)
    update!(
      status: 'failed',
      completed_at: Time.current,
      output: output_text,
      exit_code: exit_code_val
    )
  end

  def mark_as_cancelled!
    update!(
      status: 'cancelled',
      completed_at: Time.current
    )
  end

  def duration_human
    return nil unless duration_seconds

    if duration_seconds < 60
      "#{duration_seconds}s"
    elsif duration_seconds < 3600
      minutes = duration_seconds / 60
      seconds = duration_seconds % 60
      "#{minutes}m #{seconds}s"
    else
      hours = duration_seconds / 3600
      minutes = (duration_seconds % 3600) / 60
      "#{hours}h #{minutes}m"
    end
  end

  def trigger_source
    user ? "Manual (#{user.email})" : "Scheduled"
  end

  private

  def calculate_duration
    if started_at && completed_at
      self.duration_seconds = (completed_at - started_at).to_i
    end
  end

  def broadcast_update
    broadcast_replace_to(
      "task_run_#{id}",
      target: "task_run_content",
      partial: "task_runs/task_run_content",
      locals: { task_run: self }
    )
  end
end