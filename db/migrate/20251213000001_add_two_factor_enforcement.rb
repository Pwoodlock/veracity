class AddTwoFactorEnforcement < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :two_factor_enforced_at, :datetime
    add_index :users, :otp_required_for_login
  end
end
