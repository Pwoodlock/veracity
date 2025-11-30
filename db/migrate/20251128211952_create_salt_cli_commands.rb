class CreateSaltCliCommands < ActiveRecord::Migration[8.0]
  def change
    create_table :salt_cli_commands do |t|
      t.references :user, null: false, foreign_key: true
      t.text :command, null: false
      t.text :output
      t.integer :exit_status
      t.string :status, default: 'pending' # pending, running, completed, failed
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :salt_cli_commands, :status
    add_index :salt_cli_commands, :created_at
  end
end
