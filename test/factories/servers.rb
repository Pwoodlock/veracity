# frozen_string_literal: true

FactoryBot.define do
  factory :server do
    sequence(:hostname) { |n| "server-#{n}" }
    sequence(:minion_id) { |n| "minion-#{n}.example.com" }
    sequence(:ip_address) { |n| "192.168.1.#{n % 254 + 1}" }
    status { "online" }
    os_family { "Debian" }
    os_name { "Ubuntu" }
    os_version { "22.04" }
    environment { "production" }

    trait :online do
      status { "online" }
      last_seen { Time.current }
      last_heartbeat { Time.current }
    end

    trait :offline do
      status { "offline" }
      last_seen { 2.hours.ago }
      last_heartbeat { 2.hours.ago }
    end

    trait :unreachable do
      status { "unreachable" }
      last_seen { 1.day.ago }
    end

    trait :maintenance do
      status { "maintenance" }
    end

    trait :with_group do
      association :group
    end

    trait :with_coordinates do
      latitude { 52.5200 }
      longitude { 13.4050 }
    end

    trait :with_metrics do
      after(:create) do |server|
        create(:server_metric, server: server)
      end
    end

    trait :hetzner do
      association :hetzner_api_key
      hetzner_server_id { "12345678" }
      enable_hetzner_snapshot { true }
      hetzner_power_state { "running" }
    end

    trait :proxmox do
      association :proxmox_api_key
      proxmox_node { "pve-1.example.com" }
      proxmox_vmid { 100 }
      proxmox_type { "qemu" }
      proxmox_power_state { "running" }
    end

    trait :proxmox_lxc do
      association :proxmox_api_key
      proxmox_node { "pve-1.example.com" }
      proxmox_vmid { 200 }
      proxmox_type { "lxc" }
      proxmox_power_state { "running" }
    end

    trait :debian do
      os_family { "Debian" }
      os_name { "Debian" }
      os_version { "12" }
    end

    trait :ubuntu do
      os_family { "Debian" }
      os_name { "Ubuntu" }
      os_version { "22.04" }
    end

    trait :redhat do
      os_family { "RedHat" }
      os_name { "AlmaLinux" }
      os_version { "9" }
    end

    trait :with_grains do
      grains do
        {
          "os" => "Ubuntu",
          "os_family" => "Debian",
          "osrelease" => "22.04",
          "ip4_interfaces" => { "eth0" => ["192.168.1.10"] },
          "mem_total" => 8192,
          "num_cpus" => 4
        }
      end
    end
  end
end
