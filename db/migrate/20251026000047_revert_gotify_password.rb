class RevertGotifyPassword < ActiveRecord::Migration[8.0]
  def up
    # Revert password back to 'admin' to match existing Gotify server
    admin_password_setting = SystemSetting.find_by(key: 'gotify_admin_password')
    if admin_password_setting
      admin_password_setting.update!(value: 'admin')
      puts "✓ Gotify admin password reverted to 'admin' to match existing server"
    end
  end

  def down
    # No-op - we want to keep 'admin' if rolling back
  end
end
