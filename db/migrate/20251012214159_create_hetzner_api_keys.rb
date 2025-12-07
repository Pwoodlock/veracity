class CreateHetznerApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :hetzner_api_keys, id: :uuid do |t|
      t.string :name, null: false  # Friendly name (e.g., "Production", "Development")
      t.text :api_token  # Encrypted Hetzner Cloud API token
      t.string :project_id  # Hetzner project ID (optional)
      t.boolean :enabled, default: true, null: false
      t.datetime :last_used_at
      t.text :notes  # Optional notes about this API key

      t.timestamps
    end

    add_index :hetzner_api_keys, :enabled
  end
end
