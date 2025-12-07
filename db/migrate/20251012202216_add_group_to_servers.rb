class AddGroupToServers < ActiveRecord::Migration[8.0]
  def change
    add_reference :servers, :group, type: :uuid, foreign_key: true, null: true
    add_index :servers, [:group_id, :status]
  end
end
