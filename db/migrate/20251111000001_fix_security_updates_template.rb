class FixSecurityUpdatesTemplate < ActiveRecord::Migration[7.1]
  def up
    # Change "Security Updates Only" to "List Available Updates"
    # And add a new "Install All Updates" template
    execute <<-SQL
      UPDATE task_templates
      SET name = 'List Available Updates',
          description = 'List all packages that have updates available'
      WHERE name = 'Security Updates Only';

      -- Add new template for installing updates
      INSERT INTO task_templates (id, name, description, category, command_template, default_parameters, created_at, updated_at)
      VALUES
        (gen_random_uuid(), 'Install All Updates', 'Install all available package updates', 'updates',
         'pkg.upgrade', '{"refresh": true}', NOW(), NOW())
      ON CONFLICT DO NOTHING;
    SQL
  end

  def down
    execute <<-SQL
      UPDATE task_templates
      SET name = 'Security Updates Only',
          description = 'Apply only security updates'
      WHERE name = 'List Available Updates';

      DELETE FROM task_templates WHERE name = 'Install All Updates';
    SQL
  end
end
