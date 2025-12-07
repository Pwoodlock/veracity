# frozen_string_literal: true

FactoryBot.define do
  factory :server_metric do
    association :server
    cpu_percent { rand(5.0..95.0).round(2) }
    memory_percent { rand(20.0..80.0).round(2) }
    disk_percent { rand(10.0..90.0).round(2) }
    load_average { rand(0.1..4.0).round(2) }
    collected_at { Time.current }

    trait :healthy do
      cpu_percent { 25.0 }
      memory_percent { 45.0 }
      disk_percent { 35.0 }
      load_average { 0.5 }
    end

    trait :warning do
      cpu_percent { 75.0 }
      memory_percent { 80.0 }
      disk_percent { 75.0 }
      load_average { 2.5 }
    end

    trait :critical do
      cpu_percent { 95.0 }
      memory_percent { 95.0 }
      disk_percent { 95.0 }
      load_average { 8.0 }
    end

    trait :high_cpu do
      cpu_percent { 90.0 }
    end

    trait :high_memory do
      memory_percent { 90.0 }
    end

    trait :high_disk do
      disk_percent { 90.0 }
    end

    trait :old do
      collected_at { 1.day.ago }
    end

    trait :recent do
      collected_at { 5.minutes.ago }
    end
  end
end
