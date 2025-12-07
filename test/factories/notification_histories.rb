# frozen_string_literal: true

FactoryBot.define do
  factory :notification_history do
    notification_type { "system_event" }
    title { "Test Notification" }
    message { "This is a test notification message." }
    priority { 5 }
    status { "sent" }

    trait :pending do
      status { "pending" }
      sent_at { nil }
    end

    trait :sent do
      status { "sent" }
      sent_at { Time.current }
      gotify_message_id { rand(1000..9999) }
    end

    trait :failed do
      status { "failed" }
      sent_at { nil }
      error_message { "Connection refused" }
      retry_count { 3 }
    end

    trait :server_event do
      notification_type { "server_event" }
      title { "Server OFFLINE: web-server-01" }
      message { "**Server:** web-server-01\n**Status:** OFFLINE" }
      metadata { { server_id: 1, event: "offline" } }
    end

    trait :cve_alert do
      notification_type { "cve_alert" }
      title { "CVE Alert: CVE-2024-00001" }
      message { "**[HIGH] CVE-2024-00001**\nA vulnerability was found..." }
      priority { 8 }
      metadata { { cve_id: "CVE-2024-00001", severity: "HIGH" } }
    end

    trait :backup do
      notification_type { "backup" }
      title { "Backup COMPLETED: daily-backup" }
      message { "**Backup:** daily-backup\n**Status:** COMPLETED" }
      metadata { { backup_name: "daily-backup", status: "completed" } }
    end

    trait :low_priority do
      priority { 2 }
    end

    trait :normal_priority do
      priority { 5 }
    end

    trait :high_priority do
      priority { 8 }
    end

    trait :critical_priority do
      priority { 10 }
    end
  end
end
