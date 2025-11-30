# frozen_string_literal: true

class AddNotificationSettingsToCveWatchlists < ActiveRecord::Migration[8.0]
  def change
    # Add per-watchlist notification configuration
    add_column :cve_watchlists, :notification_enabled, :boolean, default: true
    add_column :cve_watchlists, :notification_threshold, :string, default: 'high'
    add_column :cve_watchlists, :last_scan_duration, :integer, comment: 'Scan duration in milliseconds'

    # Add indexes for efficient querying
    add_index :cve_watchlists, :notification_enabled
    add_index :cve_watchlists, :notification_threshold

    # Add a check constraint to ensure notification_threshold has valid values
    reversible do |dir|
      dir.up do
        execute <<-SQL
          ALTER TABLE cve_watchlists
          ADD CONSTRAINT check_notification_threshold
          CHECK (notification_threshold IN ('info', 'low', 'medium', 'high', 'critical'));
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE cve_watchlists
          DROP CONSTRAINT IF EXISTS check_notification_threshold;
        SQL
      end
    end
  end
end
