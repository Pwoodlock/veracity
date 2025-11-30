class FixProxmoxApiKeyEncryption < ActiveRecord::Migration[8.0]
  def up
    # Remove the old unencrypted api_token column
    remove_column :proxmox_api_keys, :api_token if column_exists?(:proxmox_api_keys, :api_token)

    # Add encrypted columns for attr_encrypted
    add_column :proxmox_api_keys, :encrypted_api_token, :text unless column_exists?(:proxmox_api_keys, :encrypted_api_token)
    add_column :proxmox_api_keys, :encrypted_api_token_iv, :string unless column_exists?(:proxmox_api_keys, :encrypted_api_token_iv)
  end

  def down
    # Restore the old api_token column
    add_column :proxmox_api_keys, :api_token, :text unless column_exists?(:proxmox_api_keys, :api_token)

    # Remove encrypted columns
    remove_column :proxmox_api_keys, :encrypted_api_token if column_exists?(:proxmox_api_keys, :encrypted_api_token)
    remove_column :proxmox_api_keys, :encrypted_api_token_iv if column_exists?(:proxmox_api_keys, :encrypted_api_token_iv)
  end
end
