# frozen_string_literal: true

FactoryBot.define do
  factory :proxmox_api_key do
    sequence(:name) { |n| "Proxmox API Key #{n}" }
    proxmox_url { "https://pve.example.com:8006" }
    minion_id { "pve-1.example.com" }
    username { "apiuser" }
    token_name { "automation" }
    api_token { SecureRandom.uuid }
    realm { "pam" }
    enabled { true }
    verify_ssl { true }

    trait :enabled do
      enabled { true }
    end

    trait :disabled do
      enabled { false }
    end

    trait :pam_auth do
      realm { "pam" }
    end

    trait :pve_auth do
      realm { "pve" }
    end

    trait :ldap_auth do
      realm { "ldap" }
    end

    trait :ad_auth do
      realm { "ad" }
    end

    trait :insecure do
      verify_ssl { false }
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
        create(:server, :proxmox, proxmox_api_key: api_key)
        create(:server, :proxmox_lxc, proxmox_api_key: api_key)
      end
    end
  end
end
