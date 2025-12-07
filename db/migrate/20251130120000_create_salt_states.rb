# frozen_string_literal: true

class CreateSaltStates < ActiveRecord::Migration[8.0]
  def change
    create_table :salt_states do |t|
      # Core fields
      t.string :name, null: false
      t.integer :state_type, null: false, default: 0
      t.text :content, null: false
      t.text :description

      # Organization
      t.string :category
      t.boolean :is_template, default: false
      t.boolean :is_active, default: false

      # Deployment tracking
      t.string :file_path
      t.datetime :last_deployed_at

      # Audit
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :salt_states, :name
    add_index :salt_states, :state_type
    add_index :salt_states, :category
    add_index :salt_states, :is_template
    add_index :salt_states, :is_active
    add_index :salt_states, [:name, :state_type], unique: true
  end
end
