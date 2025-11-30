# frozen_string_literal: true

class CreateCveMonitoringTables < ActiveRecord::Migration[8.0]
  def change
    # CVE Watchlist table - monitors specific vendor/product combinations
    create_table :cve_watchlists, id: :uuid do |t|
      t.string :vendor, null: false
      t.string :product, null: false
      t.string :version # Optional: specific version to monitor
      t.string :cpe_string # Full CPE 2.3 string if available
      t.string :description # User-friendly description
      t.boolean :active, default: true
      t.string :frequency, default: 'hourly' # hourly, daily, weekly
      t.datetime :last_checked_at
      t.datetime :last_execution_time
      t.integer :hits_count, default: 0 # Number of CVEs found
      t.jsonb :metadata, default: {} # Store additional configuration
      t.references :server, type: :uuid, foreign_key: true # Optional: link to specific server

      t.timestamps

      t.index [:vendor, :product], unique: true, where: 'server_id IS NULL', name: 'idx_unique_global_watchlist'
      t.index [:vendor, :product, :server_id], unique: true, where: 'server_id IS NOT NULL', name: 'idx_unique_server_watchlist'
      t.index :active
      t.index :last_checked_at
    end

    # Vulnerability Alerts table - stores detected CVEs
    create_table :vulnerability_alerts, id: :uuid do |t|
      t.string :cve_id, null: false # e.g., CVE-2024-12345
      t.references :cve_watchlist, type: :uuid, foreign_key: true
      t.references :server, type: :uuid, foreign_key: true # Which server is affected
      t.string :severity # CRITICAL, HIGH, MEDIUM, LOW
      t.decimal :cvss_score, precision: 3, scale: 1 # e.g., 9.8
      t.string :cvss_vector # CVSS vector string
      t.decimal :epss_score, precision: 5, scale: 4 # EPSS probability score
      t.string :status, default: 'new' # new, acknowledged, investigating, patched, ignored
      t.text :description
      t.text :solution
      t.jsonb :vulnerability_data, default: {} # Full CVE data from API
      t.jsonb :affected_systems, default: [] # Array of affected server IDs/names
      t.boolean :is_exploited, default: false # CISA KEV or active exploitation
      t.boolean :has_patch, default: false
      t.datetime :published_at
      t.datetime :modified_at
      t.datetime :acknowledged_at
      t.datetime :resolved_at
      t.string :acknowledged_by # User who acknowledged
      t.string :resolved_by # User who marked as resolved
      t.text :notes # Internal notes about this vulnerability

      t.timestamps

      t.index :cve_id
      t.index [:cve_id, :server_id], unique: true # Prevent duplicate alerts per server
      t.index :status
      t.index :severity
      t.index :is_exploited
      t.index :published_at
      t.index :created_at
    end

    # Add CPE information to servers table
    add_column :servers, :cpe_strings, :jsonb, default: []
    add_column :servers, :installed_packages, :jsonb, default: {}
    add_column :servers, :cve_scan_enabled, :boolean, default: true
    add_column :servers, :last_cve_scan_at, :datetime
    add_column :servers, :vulnerability_count, :integer, default: 0
    add_column :servers, :critical_vulnerability_count, :integer, default: 0

    add_index :servers, :cve_scan_enabled
    add_index :servers, :last_cve_scan_at

    # CVE Scan History table for audit trail
    create_table :cve_scan_histories, id: :uuid do |t|
      t.references :server, type: :uuid, foreign_key: true
      t.datetime :scan_started_at
      t.datetime :scan_completed_at
      t.integer :vulnerabilities_found, default: 0
      t.integer :new_vulnerabilities, default: 0
      t.integer :resolved_vulnerabilities, default: 0
      t.jsonb :scan_results, default: {}
      t.string :status # running, completed, failed
      t.text :error_message

      t.timestamps

      t.index :scan_started_at
      t.index :status
    end
  end
end