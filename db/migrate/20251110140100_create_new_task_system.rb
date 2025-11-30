class CreateNewTaskSystem < ActiveRecord::Migration[7.1]
  def change
    # Create tasks table
    create_table :tasks, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :command, null: false
      t.string :target_type, null: false # 'server', 'group', 'all', 'pattern'
      t.uuid :target_id
      t.string :target_pattern # For pattern-based targeting
      t.string :cron_schedule
      t.datetime :next_run_at
      t.boolean :enabled, default: true
      t.references :user, null: false, foreign_key: true
      t.timestamps

      t.index :enabled
      t.index :next_run_at
      t.index [:user_id, :enabled]
    end

    # Create task_runs table (execution history)
    create_table :task_runs, id: :uuid do |t|
      t.references :task, type: :uuid, null: false, foreign_key: true
      t.string :status, null: false # 'pending', 'running', 'completed', 'failed'
      t.datetime :started_at
      t.datetime :completed_at
      t.text :output
      t.integer :exit_code
      t.integer :duration_seconds
      t.references :user, foreign_key: true # Who triggered it (null for scheduled)
      t.timestamps

      t.index :status
      t.index :started_at
      t.index [:task_id, :status]
      t.index [:task_id, :created_at]
    end

    # Create task_templates table
    create_table :task_templates, id: :uuid do |t|
      t.string :name, null: false
      t.text :description
      t.string :category, null: false # 'updates', 'maintenance', 'backups', 'monitoring', 'security'
      t.string :command_template, null: false
      t.jsonb :default_parameters, default: {}
      t.boolean :active, default: true
      t.timestamps

      t.index :category
      t.index :active
      t.index [:category, :active]
    end

    # Add some default templates
    reversible do |dir|
      dir.up do
        execute <<-SQL
          INSERT INTO task_templates (id, name, description, category, command_template, default_parameters, created_at, updated_at)
          VALUES
            (gen_random_uuid(), 'System Update', 'Update all packages on the server', 'updates',
             'pkg.upgrade', '{"refresh": true}', NOW(), NOW()),
            (gen_random_uuid(), 'Security Updates Only', 'Apply only security updates', 'updates',
             'pkg.list_upgrades', '{"refresh": true}', NOW(), NOW()),
            (gen_random_uuid(), 'Disk Usage Check', 'Check disk usage on all partitions', 'monitoring',
             'disk.usage', '{}', NOW(), NOW()),
            (gen_random_uuid(), 'Service Status Check', 'Check the status of a specific service', 'monitoring',
             'service.status {{service_name}}', '{"service_name": "sshd"}', NOW(), NOW()),
            (gen_random_uuid(), 'Backup Database', 'Perform database backup', 'backups',
             'cmd.run "{{backup_command}}"', '{"backup_command": "pg_dump mydb > /backup/mydb.sql"}', NOW(), NOW()),
            (gen_random_uuid(), 'Clear Old Logs', 'Clear logs older than specified days', 'maintenance',
             'cmd.run "find /var/log -type f -name \"*.log\" -mtime +{{days}} -delete"',
             '{"days": 30}', NOW(), NOW()),
            (gen_random_uuid(), 'Restart Service', 'Restart a specified service', 'maintenance',
             'service.restart {{service_name}}', '{"service_name": "nginx"}', NOW(), NOW()),
            (gen_random_uuid(), 'Check SSL Certificate', 'Check SSL certificate expiration', 'security',
             'cmd.run "echo | openssl s_client -connect {{host}}:{{port}} 2>/dev/null | openssl x509 -noout -dates"',
             '{"host": "localhost", "port": 443}', NOW(), NOW()),
            (gen_random_uuid(), 'Memory Usage', 'Check memory usage statistics', 'monitoring',
             'status.meminfo', '{}', NOW(), NOW()),
            (gen_random_uuid(), 'Network Connectivity', 'Test network connectivity', 'monitoring',
             'network.ping {{target}}', '{"target": "8.8.8.8"}', NOW(), NOW());
        SQL
      end
    end
  end
end