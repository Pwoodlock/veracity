# Initialize Borg Backup scheduler on Rails startup
Rails.application.config.after_initialize do
  # Only run if Sidekiq and database are available
  next unless defined?(Sidekiq::Cron::Job)

  # Check database connection and table existence
  begin
    next unless ActiveRecord::Base.connection.active?
    next unless ActiveRecord::Base.connection.table_exists?('backup_configurations')
  rescue ActiveRecord::NoDatabaseError, PG::ConnectionBad
    # Database doesn't exist yet (during initial setup)
    next
  end

  # Load the current backup configuration and register its schedule
  begin
    config = BackupConfiguration.current

    if config && config.enabled? && config.backup_schedule.present?
      Sidekiq::Cron::Job.create(
        name: 'borg_backup',
        cron: config.backup_schedule,
        class: 'BorgBackupJob',
        queue: 'default',
        description: 'Automated Borg backup of PostgreSQL database and config files'
      )
      Rails.logger.info "[BACKUP SCHEDULER] Loaded backup schedule: #{config.backup_schedule} (#{config.schedule_display})"
    else
      Rails.logger.info "[BACKUP SCHEDULER] Backups are disabled or not configured"
    end
  rescue StandardError => e
    Rails.logger.error "[BACKUP SCHEDULER] Failed to initialize backup scheduler: #{e.message}"
  end
end
