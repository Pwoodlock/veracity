class AddGotifyAdminSettings < ActiveRecord::Migration[8.0]
  def up
    # Initialize Gotify admin settings with default values
    # These settings allow the admin interface to connect to Gotify

    # Admin URL - where Gotify server is running
    SystemSetting.find_or_create_by!(key: 'gotify_admin_url') do |setting|
      setting.value = 'http://localhost:8080'
      setting.value_type = 'string'
    end

    # Admin username for full API access
    SystemSetting.find_or_create_by!(key: 'gotify_admin_username') do |setting|
      setting.value = 'admin'
      setting.value_type = 'string'
    end

    # Admin password (change this after Gotify installation!)
    SystemSetting.find_or_create_by!(key: 'gotify_admin_password') do |setting|
      setting.value = 'admin'
      setting.value_type = 'string'
    end

    # Whether admin interface is enabled
    SystemSetting.find_or_create_by!(key: 'gotify_admin_enabled') do |setting|
      setting.value = 'false'
      setting.value_type = 'boolean'
    end

    puts "✓ Gotify admin settings initialized"
    puts "  URL: http://localhost:8080"
    puts "  Username: admin"
    puts "  Password: admin (change this!)"
    puts ""
    puts "To configure, run: sudo bash deployment/gotify/install-gotify-baremental.sh"
    puts "Then go to Admin > Push Notifications in the web interface"
  end

  def down
    # Remove Gotify admin settings
    SystemSetting.where(key: [
      'gotify_admin_url',
      'gotify_admin_username',
      'gotify_admin_password',
      'gotify_admin_enabled'
    ]).destroy_all
  end
end
