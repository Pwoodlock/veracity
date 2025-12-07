class AddBackupConfigurationToBackupHistories < ActiveRecord::Migration[8.0]
  def change
    add_reference :backup_histories, :backup_configuration, type: :uuid, null: true, foreign_key: true
  end
end
