class AddHetznerIntegrationToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :hetzner_api_key_id, :uuid
    add_column :servers, :hetzner_server_id, :bigint
    add_column :servers, :enable_hetzner_snapshot, :boolean, default: false, null: false
    add_column :servers, :hetzner_power_state, :string

    # Add foreign key constraint
    add_foreign_key :servers, :hetzner_api_keys, column: :hetzner_api_key_id

    # Add indexes for performance
    add_index :servers, :hetzner_api_key_id
    add_index :servers, :hetzner_server_id
    add_index :servers, :enable_hetzner_snapshot
  end
end
