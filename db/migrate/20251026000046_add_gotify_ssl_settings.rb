class AddGotifySslSettings < ActiveRecord::Migration[8.0]
  def up
    # Add SSL verification setting (enabled by default for security)
    SystemSetting.find_or_create_by!(key: 'gotify_ssl_verify') do |setting|
      setting.value = 'true'
      setting.value_type = 'boolean'
    end

    # Update default admin password if it's still 'admin' (insecure!)
    admin_password_setting = SystemSetting.find_by(key: 'gotify_admin_password')
    if admin_password_setting&.value == 'admin'
      # Generate a secure random password
      secure_password = SecureRandom.alphanumeric(32)
      admin_password_setting.update!(value: secure_password)

      puts "\n" + "=" * 80
      puts "⚠️  SECURITY UPDATE: Gotify Admin Password Changed"
      puts "=" * 80
      puts "The default 'admin' password has been replaced with a secure random password."
      puts ""
      puts "NEW PASSWORD: #{secure_password}"
      puts ""
      puts "IMPORTANT: Save this password securely!"
      puts ""
      puts "Options:"
      puts "  1. Use this password in Gotify web interface"
      puts "  2. Set GOTIFY_ADMIN_PASSWORD in ENV (recommended for production)"
      puts "  3. Change via Admin > Push Notifications > Settings"
      puts "=" * 80
      puts "\n"
    end

    puts "✓ Gotify SSL verification enabled by default"
    puts "  To disable (self-signed certs): Set gotify_ssl_verify = false or GOTIFY_SSL_VERIFY=false"
  end

  def down
    SystemSetting.where(key: 'gotify_ssl_verify').destroy_all
  end
end
