class CreateBackupConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :backup_configurations, id: :uuid do |t|
      t.string :repository_url, null: false
      t.string :repository_type, default: 'borgbase', null: false  # borgbase, ssh, local
      t.text :passphrase  # Encrypted
      t.text :ssh_key     # Encrypted
      t.string :backup_schedule, default: '0 2 * * *'  # Daily at 2 AM
      t.datetime :last_backup_at
      t.datetime :next_backup_at
      t.boolean :enabled, default: false, null: false
      t.integer :retention_daily, default: 7
      t.integer :retention_weekly, default: 4
      t.integer :retention_monthly, default: 6

      t.timestamps
    end
  end
end
