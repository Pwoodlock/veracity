# frozen_string_literal: true

FactoryBot.define do
  factory :task do
    association :user
    sequence(:name) { |n| "Task #{n}" }
    command { "cmd.run 'echo test'" }
    target_type { "all" }
    enabled { true }

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :target_server do
      target_type { "server" }

      transient do
        target_server { nil }
      end

      after(:build) do |task, evaluator|
        server = evaluator.target_server || create(:server)
        task.target_id = server.id
      end
    end

    trait :target_group do
      target_type { "group" }

      transient do
        target_group { nil }
      end

      after(:build) do |task, evaluator|
        group = evaluator.target_group || create(:group)
        task.target_id = group.id
      end
    end

    trait :target_all do
      target_type { "all" }
      target_id { nil }
    end

    trait :target_pattern do
      target_type { "pattern" }
      target_pattern { "web-*" }
    end

    trait :scheduled do
      cron_schedule { "0 2 * * *" }
      next_run_at { 1.day.from_now.beginning_of_day + 2.hours }
    end

    trait :hourly do
      cron_schedule { "0 * * * *" }
    end

    trait :daily do
      cron_schedule { "0 2 * * *" }
    end

    trait :weekly do
      cron_schedule { "0 3 * * 0" }
    end

    trait :unscheduled do
      cron_schedule { nil }
      next_run_at { nil }
    end

    trait :due do
      enabled { true }
      cron_schedule { "0 * * * *" }
      next_run_at { 1.minute.ago }
    end

    trait :with_description do
      description { "A detailed description of what this task does" }
    end

    trait :update_task do
      name { "System Update" }
      command { "pkg.upgrade" }
      description { "Run system updates on target servers" }
    end

    trait :backup_task do
      name { "Database Backup" }
      command { "cmd.run 'pg_dump -Fc mydb > /backups/mydb.dump'" }
      description { "Backup PostgreSQL database" }
    end

    trait :with_runs do
      after(:create) do |task|
        create_list(:task_run, 3, task: task)
      end
    end
  end

  factory :task_template do
    sequence(:name) { |n| "Template #{n}" }
    command_template { "cmd.run '{{command}}'" }
    category { "maintenance" }
    active { true }

    trait :updates do
      sequence(:name) { |n| "System Updates #{n}" }
      command_template { "pkg.upgrade" }
      category { "updates" }
      description { "Run system package updates" }
    end

    trait :security_updates do
      name { "Security Updates Only" }
      command_template { "pkg.upgrade security=True" }
      category { "security" }
      description { "Apply security updates only" }
    end

    trait :maintenance do
      name { "Disk Cleanup" }
      command_template { "cmd.run 'apt-get clean && apt-get autoremove -y'" }
      category { "maintenance" }
      description { "Clean up disk space" }
    end

    trait :backups do
      name { "Database Backup" }
      command_template { "cmd.run 'pg_dump -Fc {{database}} > {{backup_path}}'" }
      category { "backups" }
      default_parameters { { "database" => "mydb", "backup_path" => "/backups/db.dump" } }
    end

    trait :monitoring do
      name { "Health Check" }
      command_template { "status.ping" }
      category { "monitoring" }
    end

    trait :inactive do
      active { false }
    end

    trait :with_parameters do
      default_parameters { { "param1" => "value1", "param2" => "value2" } }
    end
  end

  factory :task_run do
    association :task
    status { "pending" }

    trait :pending do
      status { "pending" }
      started_at { nil }
      completed_at { nil }
    end

    trait :running do
      status { "running" }
      started_at { Time.current }
      completed_at { nil }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_seconds { 300 }
      output { "Task completed successfully" }
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
      duration_seconds { 60 }
      output { "Task failed: connection timeout" }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 5.minutes.ago }
      completed_at { Time.current }
    end

    trait :with_user do
      association :user
    end
  end
end
