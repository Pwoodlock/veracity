class CreateBackupHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :backup_histories, id: :uuid do |t|
      t.string :backup_name, null: false
      t.string :status, default: 'pending', null: false  # pending, running, completed, failed
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :duration_seconds
      t.bigint :original_size
      t.bigint :compressed_size
      t.bigint :deduplicated_size
      t.integer :files_count
      t.text :error_message
      t.text :output

      t.timestamps
    end

    add_index :backup_histories, :status
    add_index :backup_histories, :started_at
  end
end
