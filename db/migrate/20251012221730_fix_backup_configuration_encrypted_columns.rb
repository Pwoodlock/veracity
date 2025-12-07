class FixBackupConfigurationEncryptedColumns < ActiveRecord::Migration[8.0]
  def change
    # Make repository_url nullable (will be validated in model when enabled)
    change_column_null :backup_configurations, :repository_url, true

    # Rename existing columns to encrypted versions
    rename_column :backup_configurations, :passphrase, :encrypted_passphrase
    rename_column :backup_configurations, :ssh_key, :encrypted_ssh_key

    # Add IV columns for encryption
    add_column :backup_configurations, :encrypted_passphrase_iv, :string
    add_column :backup_configurations, :encrypted_ssh_key_iv, :string
  end
end
