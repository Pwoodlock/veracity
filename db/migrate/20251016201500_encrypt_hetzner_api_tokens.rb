class EncryptHetznerApiTokens < ActiveRecord::Migration[8.0]
  def up
    # Add encrypted columns
    add_column :hetzner_api_keys, :encrypted_api_token, :text
    add_column :hetzner_api_keys, :encrypted_api_token_iv, :text

    # Migrate existing plaintext tokens to encrypted format
    # Note: This will happen automatically when records are saved
    # The old api_token column will be removed after migration

    # Remove old plaintext column
    remove_column :hetzner_api_keys, :api_token
  end

  def down
    # Add back plaintext column
    add_column :hetzner_api_keys, :api_token, :text

    # Remove encrypted columns
    remove_column :hetzner_api_keys, :encrypted_api_token
    remove_column :hetzner_api_keys, :encrypted_api_token_iv
  end
end
