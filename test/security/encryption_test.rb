# frozen_string_literal: true

require 'test_helper'

# Test suite for encryption of sensitive credentials
# Ensures that API keys and tokens are properly encrypted at rest
# and never appear in plaintext in logs or JSON output
class EncryptionTest < ActiveSupport::TestCase
  # =============================================================================
  # HetznerApiKey Encryption Tests
  # =============================================================================

  test "HetznerApiKey encrypts api_token field" do
    # Create a Hetzner API key with a known token
    plaintext_token = "hetzner_test_token_#{SecureRandom.hex(16)}"
    api_key = create(:hetzner_api_key, api_token: plaintext_token)

    # Verify the token can be read back (decryption works)
    assert_equal plaintext_token, api_key.api_token

    # Reload from database and verify decryption still works
    api_key.reload
    assert_equal plaintext_token, api_key.api_token

    # Verify encrypted value is different from plaintext
    encrypted_value = api_key.encrypted_api_token
    assert_not_nil encrypted_value
    assert_not_equal plaintext_token, encrypted_value

    # Verify encrypted value looks encrypted (base64-like)
    assert_match(/\A[A-Za-z0-9+\/]+=*\z/, encrypted_value)
  end

  test "HetznerApiKey plaintext never appears in database" do
    plaintext_token = "secret_hetzner_token_#{SecureRandom.hex(16)}"
    api_key = create(:hetzner_api_key, api_token: plaintext_token)

    # Query the database directly for the plaintext token
    result = ActiveRecord::Base.connection.execute(
      "SELECT * FROM hetzner_api_keys WHERE id = #{api_key.id}"
    )
    row = result.first

    # Verify plaintext does not appear in any column
    row.each_value do |value|
      next if value.nil?
      assert_not_equal plaintext_token, value.to_s,
        "Plaintext token found in database column"
    end
  end

  # =============================================================================
  # ProxmoxApiKey Encryption Tests
  # =============================================================================

  test "ProxmoxApiKey encrypts api_token field" do
    # Create a Proxmox API key with a known token
    plaintext_token = SecureRandom.uuid
    api_key = create(:proxmox_api_key, api_token: plaintext_token)

    # Verify the token can be read back (decryption works)
    assert_equal plaintext_token, api_key.api_token

    # Reload from database and verify decryption still works
    api_key.reload
    assert_equal plaintext_token, api_key.api_token

    # Verify encrypted value is different from plaintext
    encrypted_value = api_key.encrypted_api_token
    assert_not_nil encrypted_value
    assert_not_equal plaintext_token, encrypted_value

    # Verify encrypted value looks encrypted (base64-like)
    assert_match(/\A[A-Za-z0-9+\/]+=*\z/, encrypted_value)
  end

  test "ProxmoxApiKey plaintext never appears in database" do
    plaintext_token = SecureRandom.uuid
    api_key = create(:proxmox_api_key, api_token: plaintext_token)

    # Query the database directly for the plaintext token
    result = ActiveRecord::Base.connection.execute(
      "SELECT * FROM proxmox_api_keys WHERE id = #{api_key.id}"
    )
    row = result.first

    # Verify plaintext does not appear in any column
    row.each_value do |value|
      next if value.nil?
      assert_not_equal plaintext_token, value.to_s,
        "Plaintext token found in database column"
    end
  end

  # =============================================================================
  # NetbirdSetupKey Encryption Tests
  # =============================================================================

  test "NetbirdSetupKey encrypts setup_key field" do
    # Create a NetBird setup key with a known UUID
    plaintext_key = SecureRandom.uuid.upcase
    setup_key = create(:netbird_setup_key, setup_key: plaintext_key)

    # Verify the key can be read back (decryption works)
    assert_equal plaintext_key, setup_key.setup_key

    # Reload from database and verify decryption still works
    setup_key.reload
    assert_equal plaintext_key, setup_key.setup_key

    # Verify encrypted value is different from plaintext
    encrypted_value = setup_key.encrypted_setup_key
    assert_not_nil encrypted_value
    assert_not_equal plaintext_key, encrypted_value

    # Verify encrypted value looks encrypted (base64-like)
    assert_match(/\A[A-Za-z0-9+\/]+=*\z/, encrypted_value)
  end

  test "NetbirdSetupKey plaintext never appears in database" do
    plaintext_key = SecureRandom.uuid.upcase
    setup_key = create(:netbird_setup_key, setup_key: plaintext_key)

    # Query the database directly for the plaintext key
    result = ActiveRecord::Base.connection.execute(
      "SELECT * FROM netbird_setup_keys WHERE id = #{setup_key.id}"
    )
    row = result.first

    # Verify plaintext does not appear in any column
    row.each_value do |value|
      next if value.nil?
      assert_not_equal plaintext_key, value.to_s,
        "Plaintext setup key found in database column"
    end
  end

  # =============================================================================
  # JSON Serialization Security Tests
  # =============================================================================

  test "plaintext credentials never appear in to_json output" do
    # Create all three types of encrypted credentials
    hetzner_token = "hetzner_secret_#{SecureRandom.hex(16)}"
    proxmox_token = SecureRandom.uuid
    netbird_key = SecureRandom.uuid.upcase

    hetzner_key = create(:hetzner_api_key, api_token: hetzner_token)
    proxmox_key = create(:proxmox_api_key, api_token: proxmox_token)
    netbird_setup = create(:netbird_setup_key, setup_key: netbird_key)

    # Convert to JSON and verify plaintext never appears
    hetzner_json = hetzner_key.to_json
    assert_not_includes hetzner_json, hetzner_token,
      "HetznerApiKey plaintext token found in JSON output"

    proxmox_json = proxmox_key.to_json
    assert_not_includes proxmox_json, proxmox_token,
      "ProxmoxApiKey plaintext token found in JSON output"

    netbird_json = netbird_setup.to_json
    assert_not_includes netbird_json, netbird_key,
      "NetbirdSetupKey plaintext key found in JSON output"
  end

  test "plaintext credentials never appear in inspect output" do
    # Create all three types of encrypted credentials
    hetzner_token = "hetzner_secret_#{SecureRandom.hex(16)}"
    proxmox_token = SecureRandom.uuid
    netbird_key = SecureRandom.uuid.upcase

    hetzner_key = create(:hetzner_api_key, api_token: hetzner_token)
    proxmox_key = create(:proxmox_api_key, api_token: proxmox_token)
    netbird_setup = create(:netbird_setup_key, setup_key: netbird_key)

    # Use inspect and verify plaintext never appears
    hetzner_inspect = hetzner_key.inspect
    assert_not_includes hetzner_inspect, hetzner_token,
      "HetznerApiKey plaintext token found in inspect output"

    proxmox_inspect = proxmox_key.inspect
    assert_not_includes proxmox_inspect, proxmox_token,
      "ProxmoxApiKey plaintext token found in inspect output"

    netbird_inspect = netbird_setup.inspect
    assert_not_includes netbird_inspect, netbird_key,
      "NetbirdSetupKey plaintext key found in inspect output"
  end

  # =============================================================================
  # Formatted Display Methods Tests
  # =============================================================================

  test "formatted_token methods safely display partial credentials" do
    # Create credentials with known values
    hetzner_key = create(:hetzner_api_key, api_token: "hetzner_1234567890abcdef1234")
    proxmox_key = create(:proxmox_api_key, api_token: "abcd1234-5678-90ef-ghij-klmnopqrstuv")
    netbird_setup = create(:netbird_setup_key, setup_key: "4F0F9A28-C7F6-4E87-B855-015FC929FC63")

    # Verify formatted methods show partial data
    assert_match(/hetzner_1.*4567/, hetzner_key.formatted_token)
    assert_match(/abcd1234.*stuv/, proxmox_key.formatted_token)
    assert_match(/4F0F9A28.*FC63/, netbird_setup.formatted_setup_key)

    # Verify full plaintext never appears
    assert_not_equal hetzner_key.api_token, hetzner_key.formatted_token
    assert_not_equal proxmox_key.api_token, proxmox_key.formatted_token
    assert_not_equal netbird_setup.setup_key, netbird_setup.formatted_setup_key
  end
end
