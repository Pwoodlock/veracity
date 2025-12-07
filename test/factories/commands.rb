# frozen_string_literal: true

FactoryBot.define do
  factory :command do
    association :server
    command { "cmd.run 'echo hello'" }
    command_type { "shell" }
    status { "pending" }
    started_at { Time.current }

    trait :pending do
      status { "pending" }
      completed_at { nil }
      output { nil }
    end

    trait :running do
      status { "running" }
      completed_at { nil }
    end

    trait :completed do
      status { "completed" }
      completed_at { Time.current }
      exit_code { 0 }
      output { "Command output here" }
      duration_seconds { 1.5 }
    end

    trait :failed do
      status { "failed" }
      completed_at { Time.current }
      exit_code { 1 }
      output { "Command output" }
      error_output { "Error: Command failed" }
      duration_seconds { 2.0 }
    end

    trait :timeout do
      status { "timeout" }
      completed_at { Time.current }
      error_output { "Command timed out after 60 seconds" }
      duration_seconds { 60.0 }
    end

    trait :cancelled do
      status { "cancelled" }
      completed_at { Time.current }
    end

    trait :partial_success do
      status { "partial_success" }
      completed_at { Time.current }
      exit_code { 0 }
      output { "Some servers succeeded" }
      error_output { "Some servers failed" }
    end

    trait :with_user do
      association :user
    end

    trait :salt_state do
      command_type { "state" }
      command { "state.apply highstate" }
    end

    trait :salt_ping do
      command_type { "ping" }
      command { "test.ping" }
    end

    trait :salt_grains do
      command_type { "grains" }
      command { "grains.items" }
    end

    trait :old do
      started_at { 2.days.ago }
      completed_at { 2.days.ago }
    end

    trait :recent do
      started_at { 30.minutes.ago }
      completed_at { 29.minutes.ago }
    end
  end
end
