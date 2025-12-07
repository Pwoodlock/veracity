# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123!" }
    password_confirmation { "password123!" }
    name { "Test User" }
    role { "viewer" }

    trait :admin do
      role { "admin" }
      name { "Admin User" }
    end

    trait :operator do
      role { "operator" }
      name { "Operator User" }
    end

    trait :viewer do
      role { "viewer" }
      name { "Viewer User" }
    end

    trait :with_2fa do
      otp_required_for_login { true }
      encrypted_otp_secret { User.generate_otp_secret }

      after(:create) do |user|
        user.generate_otp_backup_codes!
      end
    end

    trait :locked do
      locked_at { Time.current }
      failed_attempts { 5 }
    end

    trait :oauth do
      provider { "zitadel" }
      sequence(:uid) { |n| "oauth_uid_#{n}" }
    end
  end
end
