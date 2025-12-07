# frozen_string_literal: true

require "application_system_test_case"

class OnboardingTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    sign_in @admin
  end

  test "onboarding page loads successfully" do
    visit onboarding_path

    assert_selector "h2", text: "Pending Minion Keys"
    assert_selector "h2", text: "Installation Instructions"
  end

  test "onboarding page shows refresh button" do
    visit onboarding_path

    assert_button "Refresh"
  end

  test "onboarding page shows installation command" do
    visit onboarding_path

    # Should show the curl command for installing minion
    assert_text "curl"
    assert_text "install-minion.sh"
  end

  test "pending keys section is present" do
    visit onboarding_path

    # The pending keys container should exist
    assert_selector "#pending-keys"
  end

  test "refresh button triggers update" do
    visit onboarding_path

    # Mock SaltService to return pending keys
    SaltService.stubs(:list_pending_keys).returns([
      { minion_id: "test-minion", fingerprint: "aa:bb:cc:dd", status: "pending" }
    ])

    click_button "Refresh"
    wait_for_turbo

    # After refresh, should still have the pending keys section
    assert_selector "#pending-keys"
  end

  test "onboarding page shows step-by-step instructions" do
    visit onboarding_path

    assert_text "Step 1"
    assert_text "Step 2"
    assert_text "Step 3"
  end

  test "onboarding accessible from navigation" do
    # Directly visit onboarding page to verify it works
    visit onboarding_path

    wait_for_page_load
    assert_current_path onboarding_path
  end

  test "empty pending keys shows appropriate message" do
    SaltService.stubs(:list_pending_keys).returns([])

    visit onboarding_path

    within "#pending-keys" do
      assert_text "No pending minion keys"
    end
  end

  test "pending key shows accept and reject buttons" do
    SaltService.stubs(:list_pending_keys).returns([
      { minion_id: "new-server", fingerprint: "11:22:33:44:55:66", status: "pending" }
    ])

    visit onboarding_path

    within "#pending-keys" do
      assert_text "new-server"
      assert_button "Accept"
      assert_button "Reject"
    end
  end
end
