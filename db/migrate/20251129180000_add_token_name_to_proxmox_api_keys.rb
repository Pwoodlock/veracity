# frozen_string_literal: true

class AddTokenNameToProxmoxApiKeys < ActiveRecord::Migration[8.0]
  def change
    add_column :proxmox_api_keys, :token_name, :string

    # For existing records, try to extract token_name from username if it contains '!'
    reversible do |dir|
      dir.up do
        ProxmoxApiKey.find_each do |key|
          if key.username.include?('!')
            # Format was: user@realm!tokenname - extract the token name
            parts = key.username.split('!')
            key.update_columns(
              username: parts[0],
              token_name: parts[1]
            )
          end
        end
      end
    end
  end
end
