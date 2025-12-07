class AddAlertThresholdsToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :alert_on_threshold, :boolean, default: false
    add_column :tasks, :disk_usage_threshold, :integer # Percentage (e.g., 80 for 80%)
    add_column :tasks, :memory_usage_threshold, :integer # Percentage (e.g., 90 for 90%)
    add_column :tasks, :alert_priority, :integer, default: 5 # Gotify priority 0-10

    add_index :tasks, :alert_on_threshold
  end
end
