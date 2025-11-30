class AddGotifySettingsToSystemSettings < ActiveRecord::Migration[8.0]
  def up
    # Add Gotify configuration via SystemSetting model
    # These will be stored as individual key-value pairs:
    # - gotify_url (string)
    # - gotify_app_token (encrypted via attr_encrypted)
    # - gotify_enabled (boolean)

    # No schema changes needed - using existing system_settings table
    # Configuration will be managed via SystemSetting.set/get methods
  end

  def down
    # No schema changes to revert
  end
end
