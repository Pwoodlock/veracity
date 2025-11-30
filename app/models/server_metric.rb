class ServerMetric < ApplicationRecord
  belongs_to :server

  # Validations
  validates :server, presence: true
  validates :collected_at, presence: true

  # Scopes
  scope :recent, -> { where('collected_at > ?', 1.hour.ago) }
  scope :today, -> { where('collected_at > ?', Date.current.beginning_of_day) }
  scope :high_cpu, -> { where('cpu_percent > ?', 80) }
  scope :high_memory, -> { where('memory_percent > ?', 80) }

  # Display title for Avo
  def display_title
    "#{server&.hostname || 'Unknown'} - #{collected_at&.strftime('%Y-%m-%d %H:%M:%S')}"
  end
end
