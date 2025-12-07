class AddUserToCommands < ActiveRecord::Migration[8.0]
  def change
    # Add user_id column to commands table for audit trail
    # Optional (nullable) for backward compatibility with existing records and background jobs
    add_reference :commands, :user, type: :bigint, foreign_key: true, null: true, index: true

    # Add a comment to document the purpose
    change_column_comment :commands, :user_id, 'User who executed the command (null for system/automated commands)'
  end
end