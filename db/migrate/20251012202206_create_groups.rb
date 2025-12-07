class CreateGroups < ActiveRecord::Migration[8.0]
  def change
    create_table :groups, id: :uuid do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :color, default: '#3B82F6' # Tailwind blue-500
      t.jsonb :tags, default: {}
      t.jsonb :metadata, default: {}
      t.integer :servers_count, default: 0

      t.timestamps
    end

    add_index :groups, :slug, unique: true
    add_index :groups, :name
  end
end
