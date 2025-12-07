class AddSessionValidationToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :auth_time, :datetime
    add_column :users, :session_id, :string
    add_column :users, :token_expires_at, :datetime
    add_column :users, :last_auth_check, :datetime
  end
end
