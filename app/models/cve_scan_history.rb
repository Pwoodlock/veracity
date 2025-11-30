# frozen_string_literal: true

class CveScanHistory < ApplicationRecord
  # Associations
  belongs_to :server

  # Validations
  validates :status, inclusion: { in: %w[running completed failed] }

  # Scopes
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :running, -> { where(status: 'running') }
  scope :recent, -> { order(scan_started_at: :desc) }

  # Instance methods
  def duration
    return nil unless scan_started_at && scan_completed_at
    (scan_completed_at - scan_started_at).to_i
  end

  def duration_in_words
    return 'N/A' unless duration

    seconds = duration
    if seconds < 60
      "#{seconds} seconds"
    elsif seconds < 3600
      "#{seconds / 60} minutes"
    else
      "#{seconds / 3600} hours"
    end
  end

  def success?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def running?
    status == 'running'
  end

  def status_badge_class
    case status
    when 'completed'
      'badge-success'
    when 'running'
      'badge-info'
    when 'failed'
      'badge-danger'
    else
      'badge-secondary'
    end
  end
end