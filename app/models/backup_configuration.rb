class BackupConfiguration < ApplicationRecord
  # Encrypt sensitive fields
  # Use ENV-based secret key for encryption (fallback if credentials not available)
  ENCRYPTION_KEY = (Rails.application.credentials.secret_key_base rescue nil) || ENV['SECRET_KEY_BASE']

  attr_encrypted :passphrase, key: ENCRYPTION_KEY[0..31]
  attr_encrypted :ssh_key, key: ENCRYPTION_KEY[0..31]

  # Validations
  validates :repository_url, presence: true, if: :enabled?
  validates :passphrase, presence: true, if: :enabled?
  validates :repository_type, presence: true, inclusion: { in: %w[borgbase ssh local] }
  validates :backup_schedule, presence: true
  validates :retention_daily, numericality: { greater_than_or_equal_to: 0 }
  validates :retention_weekly, numericality: { greater_than_or_equal_to: 0 }
  validates :retention_monthly, numericality: { greater_than_or_equal_to: 0 }

  # Associations
  has_many :backup_histories, dependent: :destroy

  # Callbacks - Update Sidekiq-cron job when schedule or enabled status changes
  after_save :update_sidekiq_cron_job
  after_destroy :remove_sidekiq_cron_job

  # Constants
  REPOSITORY_TYPES = {
    'borgbase' => 'BorgBase.com (Recommended)',
    'ssh' => 'Remote Server (SSH)',
    'local' => 'Local Storage'
  }.freeze

  # Class methods
  def self.current
    first_or_create(
      repository_url: '',
      repository_type: 'borgbase',
      enabled: false
    )
  end

  # Instance methods
  def repository_display_name
    REPOSITORY_TYPES[repository_type] || repository_type.titleize
  end

  def schedule_display
    case backup_schedule
    when '0 2 * * *'
      'Daily at 2:00 AM'
    when '0 3 * * 0'
      'Weekly on Sunday at 3:00 AM'
    when '0 4 1 * *'
      'Monthly on 1st at 4:00 AM'
    else
      backup_schedule
    end
  end

  def formatted_repository_url
    # Hide sensitive parts of the URL
    return repository_url if repository_url.blank?

    if repository_type == 'borgbase'
      # Format: ssh://xxxxx@xxxxx.repo.borgbase.com/./repo
      repository_url.gsub(/ssh:\/\/(.*?)@/, 'ssh://***@')
    elsif repository_type == 'ssh'
      # Format: ssh://user@host:/path
      repository_url.gsub(/@.*?:/, '@***:')
    else
      repository_url
    end
  end

  def last_backup_status
    backup_histories.order(started_at: :desc).first&.status || 'never'
  end

  def last_backup_duration
    return nil unless last_backup_at

    last_history = backup_histories.where.not(duration_seconds: nil).order(started_at: :desc).first
    return nil unless last_history

    minutes = last_history.duration_seconds / 60
    seconds = last_history.duration_seconds % 60
    "#{minutes}m #{seconds}s"
  end

  private

  def update_sidekiq_cron_job
    # Only update if Sidekiq is running and schedule has changed
    return unless defined?(Sidekiq::Cron::Job)

    job_name = 'borg_backup'

    if enabled? && backup_schedule.present?
      # Create or update the Sidekiq-cron job
      Sidekiq::Cron::Job.create(
        name: job_name,
        cron: backup_schedule,
        class: 'BorgBackupJob',
        queue: 'default',
        description: 'Automated Borg backup of PostgreSQL database and config files'
      )
      Rails.logger.info "[BACKUP CONFIG] Sidekiq-cron job '#{job_name}' updated with schedule: #{backup_schedule}"
    else
      # Remove the job if backups are disabled
      remove_sidekiq_cron_job
    end
  rescue StandardError => e
    Rails.logger.error "[BACKUP CONFIG] Failed to update Sidekiq-cron job: #{e.message}"
  end

  def remove_sidekiq_cron_job
    return unless defined?(Sidekiq::Cron::Job)

    job_name = 'borg_backup'
    job = Sidekiq::Cron::Job.find(job_name)
    if job
      job.destroy
      Rails.logger.info "[BACKUP CONFIG] Sidekiq-cron job '#{job_name}' removed"
    end
  rescue StandardError => e
    Rails.logger.error "[BACKUP CONFIG] Failed to remove Sidekiq-cron job: #{e.message}"
  end
end
