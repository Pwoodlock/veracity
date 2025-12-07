# frozen_string_literal: true

FactoryBot.define do
  factory :hetzner_api_key do
    sequence(:name) { |n| "Hetzner API Key #{n}" }
    api_token { SecureRandom.hex(32) }
    enabled { true }

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_project do
      project_id { "12345" }
    end

    trait :recently_used do
      last_used_at { 1.hour.ago }
    end

    trait :never_used do
      last_used_at { nil }
    end

    trait :stale do
      last_used_at { 30.days.ago }
    end

    trait :with_servers do
      after(:create) do |api_key|
        create_list(:server, 2,
          hetzner_api_key: api_key,
          hetzner_server_id: "#{rand(10000000..99999999)}"
        )
      end
    end
  end
end
