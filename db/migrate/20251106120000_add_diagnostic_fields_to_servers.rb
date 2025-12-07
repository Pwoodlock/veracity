class AddDiagnosticFieldsToServers < ActiveRecord::Migration[7.1]
  def change
    add_column :servers, :last_ping_attempt, :datetime
    add_column :servers, :last_ping_success, :datetime
    add_column :servers, :last_ping_error, :text
    add_column :servers, :ping_failure_count, :integer, default: 0, null: false

    add_index :servers, :last_ping_attempt
    add_index :servers, :last_ping_success
    add_index :servers, :ping_failure_count
  end
end
