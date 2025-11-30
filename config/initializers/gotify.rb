# frozen_string_literal: true

#
# Gotify Configuration & Security Validator
#
# This initializer validates Gotify configuration at Rails boot
# and warns about insecure settings in production.
#

Rails.application.configure do
  config.after_initialize do
    next unless ActiveRecord::Base.connection.table_exists?('system_settings')

    # Check for insecure configurations in production
    if Rails.env.production?
      # Check 1: Default password
      password_info = SystemSetting.get_with_source('gotify_admin_password', 'admin')
      if password_info[:source] == :db && password_info[:value] == 'admin'
        Rails.logger.warn "[SECURITY] Gotify using default 'admin' password! Set GOTIFY_ADMIN_PASSWORD env variable."
      end

      # Check 2: SSL verification
      ssl_verify = SystemSetting.get('gotify_ssl_verify', true)
      unless ssl_verify
        Rails.logger.warn "[SECURITY] Gotify SSL verification is DISABLED. Enable for production or use GOTIFY_SSL_VERIFY=true"
      end

      # Check 3: ENV variable usage (informational)
      unless SystemSetting.env_override?('gotify_admin_password')
        Rails.logger.info "[INFO] Consider setting GOTIFY_ADMIN_PASSWORD in ENV for better security"
      end
    end

    # Log configuration source for transparency
    if SystemSetting.get('gotify_enabled', false)
      url_source = SystemSetting.env_override?('gotify_admin_url') ? 'ENV' : 'Database'
      Rails.logger.info "[Gotify] Configuration loaded from: #{url_source}"
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    # Database not ready yet (e.g., during migration)
    nil
  end
end
