class CreateServers < ActiveRecord::Migration[8.0]
  def change
    create_table :servers, id: :uuid do |t|
      t.string :hostname
      t.string :minion_id
      t.string :ip_address
      t.string :status
      t.string :os_family
      t.string :os_name
      t.string :os_version
      t.integer :cpu_cores
      t.float :memory_gb
      t.float :disk_gb
      t.jsonb :grains
      t.jsonb :latest_metrics
      t.datetime :last_seen
      t.datetime :last_heartbeat
      t.string :environment
      t.string :location
      t.string :provider
      t.jsonb :tags
      t.text :notes

      t.timestamps
    end
    add_index :servers, :hostname, unique: true
    add_index :servers, :minion_id, unique: true
  end
end
