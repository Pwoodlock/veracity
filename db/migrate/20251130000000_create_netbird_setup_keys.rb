class CreateNetbirdSetupKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :netbird_setup_keys, id: :uuid do |t|
      t.string :name, null: false                    # Friendly name (e.g., "Production Servers", "Dev Group")
      t.string :management_url, null: false          # Management URL (e.g., https://cacs.devsec.ie)
      t.integer :port, default: 443                  # Port (defaults to 443)
      t.text :setup_key                              # Encrypted setup key (UUID format)
      t.string :encrypted_setup_key_iv               # IV for encryption
      t.string :netbird_group                        # NetBird group this key belongs to (for reference)
      t.boolean :enabled, default: true, null: false
      t.datetime :last_used_at
      t.integer :usage_count, default: 0             # Track how many times this key has been used
      t.text :notes                                  # Optional notes about this setup key

      t.timestamps
    end

    add_index :netbird_setup_keys, :enabled
    add_index :netbird_setup_keys, :name, unique: true
  end
end
