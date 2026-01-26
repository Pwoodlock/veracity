class AddDisplayNameToServers < ActiveRecord::Migration[8.0]
  def change
    add_column :servers, :display_name, :string
  end
end
