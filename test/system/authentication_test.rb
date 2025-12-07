# frozen_string_literal: true

require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @user = users(:regular_user)
  end

  # ---------------------------------------------------------------------------
  # Basic Authentication Flow Tests
  # ---------------------------------------------------------------------------

  test "visiting login page shows sign in form" do
    visit new_user_session_path

    assert_selector "input[name='user[email]']"
    assert_selector "input[name='user[password]']"
  end

  test "login with valid credentials redirects to dashboard" do
    visit new_user_session_path

    fill_in "Email", with: @admin.email
    fill_in "Password", with: "password123!"

    find("input[type='submit'], button[type='submit']").click

    wait_for_page_load
    assert_current_path root_path
  end

  test "login with invalid credentials shows error" do
    visit new_user_session_path

    fill_in "Email", with: @admin.email
    fill_in "Password", with: "wrongpassword"
    find("input[type='submit'], button[type='submit']").click

    wait_for_page_load
    # Should stay on login page after failed attempt
    assert_current_path new_user_session_path
  end

  test "logout clears session and redirects to login" do
    sign_in @admin
    visit root_path

    # Verify we are logged in
    assert_current_path root_path

    # Find and click the logout link/button (typically in sidebar or nav)
    # The app may have a sidebar with sign out link
    if page.has_link?("Sign Out")
      click_link "Sign Out"
    elsif page.has_button?("Sign Out")
      click_button "Sign Out"
    elsif page.has_css?("a[href='#{destroy_user_session_path}']")
      find("a[href='#{destroy_user_session_path}']").click
    else
      # Manually navigate to logout
      visit destroy_user_session_path
    end

    wait_for_page_load

    # After logout, accessing protected page should redirect to login
    visit dashboard_path
    assert_current_path new_user_session_path
  end

  test "unauthenticated user is redirected to login" do
    visit dashboard_path

    assert_current_path new_user_session_path
  end

  # ---------------------------------------------------------------------------
  # Two-Factor Authentication Tests
  # ---------------------------------------------------------------------------

  test "user with 2FA enabled sees verification page after login" do
    # Create a user with 2FA enabled
    user_with_2fa = User.create!(
      email: "twofa@test.com",
      password: "password123!",
      password_confirmation: "password123!",
      name: "2FA User",
      role: "admin"
    )
    user_with_2fa.enable_two_factor!

    visit new_user_session_path

    fill_in "Email", with: user_with_2fa.email
    fill_in "Password", with: "password123!"
    find("input[type='submit'], button[type='submit']").click

    wait_for_page_load

    # Should see the 2FA verification page
    assert_text "Two-Factor Verification"
    assert_selector "input[name='otp_code']"
  end

  test "2FA verification with valid OTP code succeeds" do
    # Create a user with 2FA enabled
    user_with_2fa = User.create!(
      email: "twofa-verify@test.com",
      password: "password123!",
      password_confirmation: "password123!",
      name: "2FA Verify User",
      role: "admin"
    )
    user_with_2fa.enable_two_factor!

    # Get a valid OTP code
    totp = ROTP::TOTP.new(user_with_2fa.otp_secret)
    valid_otp = totp.now

    visit new_user_session_path

    fill_in "Email", with: user_with_2fa.email
    fill_in "Password", with: "password123!"
    find("input[type='submit'], button[type='submit']").click

    wait_for_page_load

    # Enter the OTP code
    fill_in "otp_code", with: valid_otp
    click_button "Verify"

    wait_for_page_load

    # Should be redirected to dashboard after successful 2FA
    assert_current_path root_path
  end

  test "2FA verification with invalid OTP code shows error" do
    # Create a user with 2FA enabled
    user_with_2fa = User.create!(
      email: "twofa-invalid@test.com",
      password: "password123!",
      password_confirmation: "password123!",
      name: "2FA Invalid User",
      role: "admin"
    )
    user_with_2fa.enable_two_factor!

    visit new_user_session_path

    fill_in "Email", with: user_with_2fa.email
    fill_in "Password", with: "password123!"
    find("input[type='submit'], button[type='submit']").click

    wait_for_page_load

    # Enter an invalid OTP code
    fill_in "otp_code", with: "000000"
    click_button "Verify"

    wait_for_page_load

    # Should show error and remain on verification page
    assert_text "Invalid verification code"
    assert_selector "input[name='otp_code']"
  end

  # ---------------------------------------------------------------------------
  # Role-Based Access Tests
  # ---------------------------------------------------------------------------

  test "viewer user can access dashboard" do
    sign_in @user
    visit dashboard_path

    wait_for_page_load
    assert_current_path dashboard_path
    assert_selector "#dashboard-stats"
  end
end
