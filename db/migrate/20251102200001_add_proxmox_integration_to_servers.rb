class AddProxmoxIntegrationToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :proxmox_api_key_id, :uuid
    add_column :servers, :proxmox_node, :string  # Proxmox node name (e.g., "pve-1", "pve-1.fritz.box")
    add_column :servers, :proxmox_vmid, :integer  # VM/Container ID (e.g., 100, 101, 102)
    add_column :servers, :proxmox_type, :string  # "qemu" for VMs, "lxc" for containers
    add_column :servers, :proxmox_power_state, :string  # "running", "stopped", "paused", etc.
    add_column :servers, :proxmox_cluster, :string  # Optional cluster name

    # Add foreign key constraint
    add_foreign_key :servers, :proxmox_api_keys, column: :proxmox_api_key_id

    # Add indexes for performance
    add_index :servers, :proxmox_api_key_id
    add_index :servers, :proxmox_vmid
    add_index :servers, [:proxmox_node, :proxmox_vmid]
    add_index :servers, :proxmox_type
  end
end
