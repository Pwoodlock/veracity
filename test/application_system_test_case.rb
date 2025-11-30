# frozen_string_literal: true

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Use headless Chrome for CI environments
  if ENV["CI"]
    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 900]
  else
    driven_by :selenium, using: :chrome, screen_size: [1400, 900]
  end

  include Devise::Test::IntegrationHelpers

  # Wait for page to fully load
  def wait_for_page_load
    sleep 0.5 # Brief pause for JS to execute
  end

  # Wait for Turbo to complete
  def wait_for_turbo
    sleep 0.3
  end

  # Assert flash message appears
  def assert_flash(type, text = nil)
    case type
    when :success, :notice
      assert_selector ".alert-success", text: text
    when :error, :alert
      assert_selector ".alert-error", text: text
    when :warning
      assert_selector ".alert-warning", text: text
    end
  end

  # Helper to log in via UI
  def login_as_user(user, password = "password123!")
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: password
    click_button "Log in"
    wait_for_page_load
  end

  # Helper to check if element is visible
  def element_visible?(selector)
    page.has_selector?(selector, visible: true)
  end
end
