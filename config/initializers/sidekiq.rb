# frozen_string_literal: true

# Sidekiq Configuration and Scheduling

# Basic Sidekiq configuration
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }

  # Load sidekiq-cron schedules
  schedule_file = 'config/schedule.yml'

  if File.exist?(schedule_file)
    schedule = YAML.load_file(schedule_file)
    Sidekiq::Cron::Job.load_from_hash(schedule)
    Rails.logger.info 'Sidekiq-cron schedules loaded successfully'
  else
    Rails.logger.warn "Sidekiq-cron schedule file not found: #{schedule_file}"
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

# Optional: Enable Sidekiq Web UI
# Add this to config/routes.rb to mount:
#   require 'sidekiq/web'
#   mount Sidekiq::Web => '/sidekiq'
