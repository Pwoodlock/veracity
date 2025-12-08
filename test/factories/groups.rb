# frozen_string_literal: true

FactoryBot.define do
  factory :group do
    sequence(:name) { |n| "Group #{n}" }
    sequence(:slug) { |n| "group-#{n}" }
    description { "A test group" }
    servers_count { 0 }

    trait :production do
      sequence(:name) { |n| "Production #{n}" }
      sequence(:slug) { |n| "production-#{n}" }
      description { "Production servers" }
      color { "#EF4444" }
    end

    trait :staging do
      sequence(:name) { |n| "Staging #{n}" }
      sequence(:slug) { |n| "staging-#{n}" }
      description { "Staging servers" }
      color { "#F59E0B" }
    end

    trait :development do
      sequence(:name) { |n| "Development #{n}" }
      sequence(:slug) { |n| "development-#{n}" }
      description { "Development servers" }
      color { "#10B981" }
    end

    trait :with_color do
      color { "#3B82F6" }
    end

    trait :with_servers do
      transient do
        server_count { 3 }
      end

      after(:create) do |group, evaluator|
        create_list(:server, evaluator.server_count, group: group)
        group.update!(servers_count: evaluator.server_count)
      end
    end
  end
end
