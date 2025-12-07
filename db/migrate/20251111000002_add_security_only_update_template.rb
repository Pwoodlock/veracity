class AddSecurityOnlyUpdateTemplate < ActiveRecord::Migration[7.1]
  def up
    execute <<-SQL
      -- Add security-only update template
      INSERT INTO task_templates (id, name, description, category, command_template, default_parameters, created_at, updated_at)
      VALUES
        (gen_random_uuid(),
         'Install Security Updates Only',
         'Install only security updates - RHEL/CentOS: yum/dnf --security, Debian/Ubuntu: unattended-upgrades',
         'updates',
         'cmd.run "if command -v yum >/dev/null 2>&1; then yum update --security -y; elif command -v dnf >/dev/null 2>&1; then dnf upgrade-minimal --security -y; elif command -v unattended-upgrades >/dev/null 2>&1; then unattended-upgrades; else echo ''Installing unattended-upgrades package...''; apt-get update && apt-get install -y unattended-upgrades && unattended-upgrades; fi"',
         '{}',
         NOW(),
         NOW())
      ON CONFLICT DO NOTHING;
    SQL
  end

  def down
    execute <<-SQL
      DELETE FROM task_templates WHERE name = 'Install Security Updates Only';
    SQL
  end
end
