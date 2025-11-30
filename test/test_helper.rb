# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "mocha/minitest"

# Code coverage
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/vendor/"

  add_group "Models", "app/models"
  add_group "Controllers", "app/controllers"
  add_group "Services", "app/services"
  add_group "Jobs", "app/jobs"
  add_group "Channels", "app/channels"
  add_group "Helpers", "app/helpers"
end

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order
  fixtures :all

  # Add more helper methods to be used by all tests here...

  # Helper to sign in a user for controller tests
  def sign_in(user)
    post user_session_path, params: {
      user: {
        email: user.email,
        password: "password123!"
      }
    }
  end

  # Helper to create a test server
  def create_test_server(attributes = {})
    Server.create!({
      hostname: "test-server-#{SecureRandom.hex(4)}",
      minion_id: "test-minion-#{SecureRandom.hex(4)}",
      ip_address: "192.168.1.#{rand(1..254)}",
      status: "online"
    }.merge(attributes))
  end

  # Helper to create a test command
  def create_test_command(server, attributes = {})
    Command.create!({
      server: server,
      command_type: "shell",
      command: "cmd.run",
      arguments: { args: ["echo test"] },
      status: "pending",
      started_at: Time.current
    }.merge(attributes))
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
end
