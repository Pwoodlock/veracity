class AddDetailsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :name, :string
    add_column :users, :role, :string, default: 'viewer', null: false
    add_index :users, :role
  end
end
