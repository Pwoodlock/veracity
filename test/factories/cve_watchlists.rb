# frozen_string_literal: true

FactoryBot.define do
  factory :cve_watchlist do
    sequence(:vendor) { |n| "vendor#{n}" }
    sequence(:product) { |n| "product#{n}" }
    frequency { "daily" }
    active { true }

    trait :active do
      active { true }
    end

    trait :inactive do
      active { false }
    end

    trait :hourly do
      frequency { "hourly" }
    end

    trait :daily do
      frequency { "daily" }
    end

    trait :weekly do
      frequency { "weekly" }
    end

    trait :global do
      server { nil }
    end

    trait :server_specific do
      association :server
    end

    trait :with_version do
      version { "1.0.0" }
    end

    trait :with_cpe do
      cpe_string { "cpe:2.3:a:vendor:product:1.0.0:*:*:*:*:*:*:*" }
    end

    trait :checked do
      last_checked_at { 1.hour.ago }
      last_execution_time { 1.hour.ago }
    end

    trait :never_checked do
      last_checked_at { nil }
      last_execution_time { nil }
    end

    trait :due_for_check do
      frequency { "hourly" }
      last_checked_at { 2.hours.ago }
    end

    trait :nginx do
      vendor { "nginx" }
      product { "nginx" }
      description { "NGINX Web Server" }
    end

    trait :openssl do
      vendor { "openssl" }
      product { "openssl" }
      description { "OpenSSL Cryptographic Library" }
    end

    trait :ubuntu do
      vendor { "canonical" }
      product { "ubuntu_linux" }
      description { "Ubuntu Linux" }
    end

    trait :with_alerts do
      after(:create) do |watchlist|
        create_list(:vulnerability_alert, 3, cve_watchlist: watchlist)
      end
    end
  end
end
