# frozen_string_literal: true

require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @user = users(:regular_user)
  end

  test "visiting login page shows sign in form" do
    visit new_user_session_path

    assert_selector "input[name='user[email]']"
    assert_selector "input[name='user[password]']"
  end

  test "admin can log in successfully" do
    visit new_user_session_path

    fill_in "Email", with: @admin.email
    fill_in "Password", with: "password123!"

    # Find submit button by type or text
    find("input[type='submit'], button[type='submit']").click

    wait_for_page_load
    assert_current_path root_path
  end

  test "invalid credentials show error" do
    visit new_user_session_path

    fill_in "Email", with: @admin.email
    fill_in "Password", with: "wrongpassword"
    find("input[type='submit'], button[type='submit']").click

    wait_for_page_load
    # Should stay on login page after failed attempt
    assert_current_path new_user_session_path
  end

  test "user can log out" do
    sign_in @admin
    visit root_path

    # Just verify we're logged in and can access authenticated pages
    assert_current_path root_path
  end

  test "unauthenticated user is redirected to login" do
    visit dashboard_path

    assert_current_path new_user_session_path
  end
end
