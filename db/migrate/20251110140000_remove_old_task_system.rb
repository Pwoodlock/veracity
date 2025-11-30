class RemoveOldTaskSystem < ActiveRecord::Migration[7.1]
  def change
    # First, remove the foreign key column from commands table
    if column_exists?(:commands, :task_execution_id)
      remove_foreign_key :commands, :task_executions if foreign_key_exists?(:commands, :task_executions)
      remove_index :commands, :task_execution_id if index_exists?(:commands, :task_execution_id)
      remove_column :commands, :task_execution_id
    end

    # Drop task-related tables in dependency order
    drop_table :task_steps if table_exists?(:task_steps)
    drop_table :task_executions if table_exists?(:task_executions)
    drop_table :task_templates if table_exists?(:task_templates)
    drop_table :scheduled_tasks if table_exists?(:scheduled_tasks)
  end

  private

  def foreign_key_exists?(from_table, to_table)
    foreign_keys(from_table).any? { |fk| fk.to_table == to_table.to_s }
  end
end