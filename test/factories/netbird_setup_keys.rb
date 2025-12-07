# frozen_string_literal: true

FactoryBot.define do
  factory :netbird_setup_key do
    sequence(:name) { |n| "NetBird Setup Key #{n}" }
    management_url { "https://netbird.example.com" }
    setup_key { SecureRandom.uuid.upcase }
    enabled { true }
    port { 443 }
    usage_count { 0 }

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_custom_port do
      port { 33073 }
    end

    trait :recently_used do
      last_used_at { 1.hour.ago }
      usage_count { 5 }
    end

    trait :never_used do
      last_used_at { nil }
      usage_count { 0 }
    end

    trait :heavily_used do
      last_used_at { 1.day.ago }
      usage_count { 50 }
    end

    trait :cloud do
      management_url { "https://app.netbird.io" }
    end

    trait :self_hosted do
      management_url { "https://netbird.internal.example.com" }
      port { 33073 }
    end
  end
end
