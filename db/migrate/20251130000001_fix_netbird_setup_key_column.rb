class FixNetbirdSetupKeyColumn < ActiveRecord::Migration[8.0]
  def change
    # attr_encrypted expects 'encrypted_setup_key' column, not 'setup_key'
    rename_column :netbird_setup_keys, :setup_key, :encrypted_setup_key
  end
end
