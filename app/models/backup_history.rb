class BackupHistory < ApplicationRecord
  # Associations
  belongs_to :backup_configuration, optional: true

  # Validations
  validates :backup_name, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending running completed failed] }

  # Scopes
  scope :recent, -> { order(started_at: :desc) }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :running, -> { where(status: 'running') }

  # Instance methods
  def duration_formatted
    return 'N/A' unless duration_seconds

    minutes = duration_seconds / 60
    seconds = duration_seconds % 60
    hours = minutes / 60
    minutes = minutes % 60

    if hours > 0
      "#{hours}h #{minutes}m #{seconds}s"
    elsif minutes > 0
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end

  def size_formatted(bytes)
    return 'N/A' unless bytes

    units = ['B', 'KB', 'MB', 'GB', 'TB']
    size = bytes.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end

    "#{size.round(2)} #{units[unit_index]}"
  end

  def original_size_formatted
    size_formatted(original_size)
  end

  def compressed_size_formatted
    size_formatted(compressed_size)
  end

  def deduplicated_size_formatted
    size_formatted(deduplicated_size)
  end

  def compression_ratio
    return 'N/A' unless original_size && compressed_size && original_size > 0

    ratio = ((1 - (compressed_size.to_f / original_size)) * 100).round(1)
    "#{ratio}%"
  end

  def deduplication_ratio
    return 'N/A' unless compressed_size && deduplicated_size && compressed_size > 0

    ratio = ((1 - (deduplicated_size.to_f / compressed_size)) * 100).round(1)
    "#{ratio}%"
  end

  def status_badge_class
    case status
    when 'completed'
      'bg-green-100 text-green-800'
    when 'failed'
      'bg-red-100 text-red-800'
    when 'running'
      'bg-blue-100 text-blue-800'
    when 'pending'
      'bg-yellow-100 text-yellow-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end
end
