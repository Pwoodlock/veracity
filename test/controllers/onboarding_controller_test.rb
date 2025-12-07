# frozen_string_literal: true

require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin)
  end

  test "should redirect to login when not authenticated" do
    get onboarding_path
    assert_redirected_to new_user_session_path
  end

  test "should get index when authenticated" do
    sign_in @admin

    # Stub Salt API call
    SaltService.stubs(:list_pending_keys).returns([])

    get onboarding_path
    assert_response :success
  end

  test "index shows pending keys section" do
    sign_in @admin
    SaltService.stubs(:list_pending_keys).returns([])

    get onboarding_path

    assert_select "#pending-keys"
  end

  test "index shows installation instructions" do
    sign_in @admin
    SaltService.stubs(:list_pending_keys).returns([])

    get onboarding_path

    assert_select "h2", text: /Installation Instructions/i
  end

  test "refresh updates pending keys via turbo stream" do
    sign_in @admin
    SaltService.stubs(:list_pending_keys).returns([])

    post refresh_onboarding_path, as: :turbo_stream
    assert_response :success
  end

  test "accept_key requires minion_id" do
    sign_in @admin

    post accept_key_onboarding_path, params: { fingerprint: "aa:bb:cc" }
    assert_redirected_to onboarding_path
    assert_equal "Minion ID and fingerprint are required", flash[:error]
  end

  test "accept_key calls SaltService" do
    sign_in @admin

    # Mock the Salt API calls
    SaltService.stubs(:accept_key_with_verification).returns({
      success: true,
      minion_id: "test-minion",
      message: "Key accepted"
    })

    # Mock grains sync
    SaltService.stubs(:sync_minion_grains).returns({
      "os" => "Ubuntu",
      "osrelease" => "22.04"
    })

    post accept_key_onboarding_path, params: {
      minion_id: "test-minion",
      fingerprint: "aa:bb:cc:dd"
    }

    assert_redirected_to onboarding_path
  end

  test "reject_key requires minion_id" do
    sign_in @admin

    post reject_key_onboarding_path, params: {}
    assert_redirected_to onboarding_path
    assert_equal "Minion ID is required", flash[:error]
  end

  test "reject_key calls SaltService" do
    sign_in @admin

    SaltService.stubs(:reject_key).returns({ "return" => [{ "data" => { "success" => true } }] })

    post reject_key_onboarding_path, params: { minion_id: "bad-minion" }

    assert_redirected_to onboarding_path
    assert_match /rejected/i, flash[:success]
  end
end
