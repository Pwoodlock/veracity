# frozen_string_literal: true

class AddMinionIdToProxmoxApiKeys < ActiveRecord::Migration[8.0]
  def change
    add_column :proxmox_api_keys, :minion_id, :string

    # For existing records, try to extract minion_id from proxmox_url hostname
    reversible do |dir|
      dir.up do
        ProxmoxApiKey.find_each do |key|
          if key.proxmox_url.present?
            # Extract hostname from URL (e.g., https://pve-1.fritz.box:8006 -> pve-1.fritz.box)
            begin
              uri = URI.parse(key.proxmox_url)
              key.update_column(:minion_id, uri.host) if uri.host.present?
            rescue URI::InvalidURIError
              # Skip if URL is invalid
            end
          end
        end
      end
    end
  end
end
