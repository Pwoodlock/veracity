# frozen_string_literal: true

require_relative "salt_integration_test"

# Integration tests for Salt key management operations
# Tests real key management against the staging Salt API
#
# These tests verify:
# - Listing minion keys (accepted, pending, rejected)
# - Key fingerprint retrieval
# - Key acceptance flow (limited - won't create new pending keys)
# - Key rejection handling
#
# SAFETY NOTE: These tests are read-mostly to avoid disrupting the staging environment.
# We only verify that the key management APIs work correctly, not that we can
# accept/reject real keys (which would require creating test minions).
class SaltKeyManagementTest < SaltIntegrationTest
  # =========================================================================
  # Key Listing Operations
  # =========================================================================

  test "list_keys returns actual key status" do
    result = SaltService.list_keys

    assert result.is_a?(Hash), "Expected Hash result"
    assert result["return"].present?, "Expected 'return' key"

    # Navigate to the key data
    return_data = result["return"].first
    assert return_data.is_a?(Hash), "Expected first return element to be Hash"

    key_data = return_data.dig("data", "return")
    assert key_data.present?, "Expected key data in response"

    # Verify expected key categories are present
    assert key_data.key?("minions"), "Expected 'minions' (accepted keys) in response"
    assert key_data.key?("minions_pre"), "Expected 'minions_pre' (pending keys) in response"
    assert key_data.key?("minions_rejected"), "Expected 'minions_rejected' in response"

    # The test minion should be in accepted keys
    accepted_minions = key_data["minions"]
    assert accepted_minions.is_a?(Array), "Expected minions to be an Array"
    assert accepted_minions.include?(TEST_MINION_ID),
           "Expected test minion '#{TEST_MINION_ID}' to be in accepted keys"
  end

  test "list_keys returns arrays for all key categories" do
    result = SaltService.list_keys
    key_data = result.dig("return", 0, "data", "return")

    # All categories should be arrays (even if empty)
    assert key_data["minions"].is_a?(Array), "minions should be Array"
    assert key_data["minions_pre"].is_a?(Array), "minions_pre should be Array"
    assert key_data["minions_rejected"].is_a?(Array), "minions_rejected should be Array"
  end

  # =========================================================================
  # Key Fingerprint Operations
  # =========================================================================

  test "get_key_fingerprint returns fingerprint for accepted minion" do
    skip_unless_test_minion_available

    fingerprint = SaltService.get_key_fingerprint(TEST_MINION_ID)

    assert fingerprint.present?, "Expected fingerprint for test minion"
    assert fingerprint.is_a?(String), "Expected fingerprint to be a String"
    # Fingerprints are typically in format like "ab:cd:ef:12:34:..."
    assert fingerprint.include?(":"), "Expected fingerprint to contain colons"
    assert fingerprint.length >= 47, "Expected fingerprint to be at least 47 chars (SHA256)"
  end

  test "get_key_fingerprint handles non-existent minion" do
    fingerprint = SaltService.get_key_fingerprint("nonexistent-minion-xyz-123")

    # Should return nil for non-existent minion, not crash
    assert_nil fingerprint, "Expected nil fingerprint for non-existent minion"
  end

  # =========================================================================
  # Pending Key Operations
  # =========================================================================

  test "list_pending_keys returns structured data" do
    pending_keys = SaltService.list_pending_keys

    assert pending_keys.is_a?(Array), "Expected Array of pending keys"

    # If there are pending keys, verify structure
    if pending_keys.any?
      first_key = pending_keys.first
      assert first_key.key?(:minion_id), "Expected :minion_id in pending key"
      assert first_key.key?(:fingerprint), "Expected :fingerprint in pending key"
      assert first_key.key?(:status), "Expected :status in pending key"
      assert_equal "pending", first_key[:status]
    end
  end

  # =========================================================================
  # Key Acceptance Flow (Read-only verification)
  # =========================================================================

  test "accept_key API call structure is correct" do
    # We can't easily test actual key acceptance without a pending key
    # Instead, verify that accepting an already-accepted key doesn't break things

    result = SaltService.accept_key(TEST_MINION_ID)

    assert result.is_a?(Hash), "Expected Hash result"
    assert result["return"].present?, "Expected 'return' key"

    # Verify the API responded (even if the key was already accepted)
    return_data = result["return"].first
    assert return_data.is_a?(Hash), "Expected Hash in return"
  end

  # =========================================================================
  # Key Rejection Handling
  # =========================================================================

  test "reject_key API handles non-pending key gracefully" do
    # Rejecting an accepted or non-existent key should not crash
    result = SaltService.reject_key("nonexistent-minion-xyz-123")

    assert result.is_a?(Hash), "Expected Hash result"
    assert result["return"].present?, "Expected 'return' key"
    # API should respond even if there's nothing to reject
  end

  test "reject_key API call structure is correct" do
    # Test the API structure without actually rejecting a real minion
    # Use a fake minion ID that doesn't exist
    result = SaltService.reject_key("integration-test-fake-minion")

    assert result.is_a?(Hash), "Expected Hash result"
    assert result["return"].present?, "Expected 'return' key"

    return_data = result["return"].first
    assert return_data.is_a?(Hash), "Expected Hash in return"

    # Verify the response has the expected structure
    if return_data["data"]
      assert return_data["data"].key?("success") || return_data["data"].key?("return"),
             "Expected success or return key in data"
    end
  end

  # =========================================================================
  # Discover All Minions
  # =========================================================================

  test "discover_all_minions returns structured minion data" do
    minions = SaltService.discover_all_minions

    assert minions.is_a?(Array), "Expected Array of minions"

    # Should find at least the test minion
    assert minions.any?, "Expected at least one minion"

    # Verify structure of minion data
    test_minion_data = minions.find { |m| m[:minion_id] == TEST_MINION_ID }

    if test_minion_data
      assert test_minion_data.key?(:minion_id), "Expected :minion_id"
      assert test_minion_data.key?(:online), "Expected :online"
      assert test_minion_data.key?(:grains), "Expected :grains"
      assert test_minion_data.key?(:last_checked), "Expected :last_checked"

      # Test minion should be online (if available)
      if test_minion_available?
        assert test_minion_data[:online], "Expected test minion to be online"
        assert test_minion_data[:grains].is_a?(Hash), "Expected grains to be Hash"
      end
    end
  end

  test "discover_all_minions includes offline status tracking" do
    minions = SaltService.discover_all_minions

    # Find any offline minion or verify structure for online minions
    minions.each do |minion|
      assert minion.key?(:online), "Every minion should have :online status"
      assert minion.key?(:ping_error), "Every minion should have :ping_error field"

      # If offline, should have an error reason
      unless minion[:online]
        assert minion[:ping_error].present?, "Offline minion should have ping_error reason"
      end
    end
  end
end
