class CreateProxmoxApiKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :proxmox_api_keys, id: :uuid do |t|
      t.string :name, null: false  # Friendly name (e.g., "Production Proxmox", "Home Lab")
      t.string :proxmox_url, null: false  # Base URL (e.g., https://pve-1.fritz.box:8006)
      t.text :api_token  # Encrypted Proxmox API token (encrypted with attr_encrypted)
      t.string :username, null: false  # Proxmox username (e.g., root@pam, api@pve)
      t.string :realm, default: 'pam'  # Authentication realm (pam, pve, ldap, etc.)
      t.boolean :verify_ssl, default: true, null: false  # SSL certificate verification
      t.boolean :enabled, default: true, null: false
      t.datetime :last_used_at
      t.text :notes  # Optional notes about this Proxmox instance

      t.timestamps
    end

    add_index :proxmox_api_keys, :enabled
    add_index :proxmox_api_keys, :name, unique: true
  end
end
