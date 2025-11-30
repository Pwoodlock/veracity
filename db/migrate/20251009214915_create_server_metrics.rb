class CreateServerMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :server_metrics do |t|
      t.references :server, null: false, foreign_key: true, type: :uuid
      t.float :cpu_percent
      t.float :memory_percent
      t.float :memory_used_gb
      t.float :memory_total_gb
      t.jsonb :disk_usage
      t.jsonb :network_io
      t.float :load_1m
      t.float :load_5m
      t.float :load_15m
      t.integer :process_count
      t.integer :tcp_connections
      t.float :swap_percent
      t.datetime :collected_at

      t.timestamps
    end
    add_index :server_metrics, :collected_at
  end
end
