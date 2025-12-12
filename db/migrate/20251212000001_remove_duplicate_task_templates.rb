# frozen_string_literal: true

class RemoveDuplicateTaskTemplates < ActiveRecord::Migration[8.1]
  def up
    # Remove duplicate task templates, keeping only one instance of each
    # This fixes duplicates created by migrations and seeds

    execute <<-SQL
      -- Keep only the first (oldest) instance of each unique command_template
      -- Using DISTINCT ON which works with UUID columns in PostgreSQL
      DELETE FROM task_templates
      WHERE id NOT IN (
        SELECT DISTINCT ON (command_template) id
        FROM task_templates
        ORDER BY command_template, created_at
      );
    SQL

    puts "✓ Removed duplicate task templates"

    # Add unique constraint to prevent future duplicates
    add_index :task_templates, :command_template, unique: true,
              name: 'index_task_templates_on_command_template_unique'

    puts "✓ Added unique constraint on command_template"
  end

  def down
    # Remove the unique constraint
    remove_index :task_templates, name: 'index_task_templates_on_command_template_unique'
  end
end
