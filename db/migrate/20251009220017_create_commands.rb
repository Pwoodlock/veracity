class CreateCommands < ActiveRecord::Migration[8.0]
  def change
    create_table :commands, id: :uuid do |t|
      t.references :server, null: false, foreign_key: true, type: :uuid
      # t.references :user, null: false, foreign_key: true, type: :uuid  # TODO: Add after creating User model
      t.string :command_type
      t.text :command
      t.jsonb :arguments
      t.string :status
      t.text :output
      t.text :error_output
      t.integer :exit_code
      t.float :duration_seconds
      t.string :salt_job_id
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
