# frozen_string_literal: true

FactoryBot.define do
  factory :backup_configuration do
    repository_url { "ssh://backup@borgbase.repo.borgbase.com/./repo" }
    repository_type { "borgbase" }
    passphrase { "secure_passphrase_123!" }
    backup_schedule { "0 2 * * *" }
    enabled { false }
    retention_daily { 7 }
    retention_weekly { 4 }
    retention_monthly { 6 }

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :borgbase do
      repository_type { "borgbase" }
      repository_url { "ssh://backup@borgbase.repo.borgbase.com/./repo" }
    end

    trait :ssh do
      repository_type { "ssh" }
      repository_url { "ssh://backupuser@backup.example.com:/backups/server" }
      ssh_key { "-----BEGIN OPENSSH PRIVATE KEY-----\ntest_key_content\n-----END OPENSSH PRIVATE KEY-----" }
    end

    trait :local do
      repository_type { "local" }
      repository_url { "/var/backups/borg" }
    end

    trait :daily do
      backup_schedule { "0 2 * * *" }
    end

    trait :weekly do
      backup_schedule { "0 3 * * 0" }
    end

    trait :monthly do
      backup_schedule { "0 4 1 * *" }
    end

    trait :with_last_backup do
      last_backup_at { 1.day.ago }

      after(:create) do |config|
        create(:backup_history, :completed, backup_configuration: config)
      end
    end

    trait :never_backed_up do
      last_backup_at { nil }
    end
  end

  factory :backup_history do
    association :backup_configuration
    backup_name { "backup-#{Time.current.strftime('%Y%m%d-%H%M%S')}" }
    status { "completed" }
    started_at { 1.hour.ago }

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
      duration_seconds { 300 }
      deduplicated_size { 1024 * 1024 * 100 }
      original_size { 1024 * 1024 * 500 }
      files_count { 1500 }
    end

    trait :failed do
      status { "failed" }
      completed_at { Time.current }
      duration_seconds { 60 }
      error_message { "Repository connection failed: timeout" }
    end

    trait :running do
      status { "running" }
      completed_at { nil }
    end

    trait :pending do
      status { "pending" }
      started_at { nil }
      completed_at { nil }
    end
  end
end
