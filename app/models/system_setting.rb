class SystemSetting < ApplicationRecord
  # Validations
  validates :key, presence: true, uniqueness: true

  # Environment variable mapping for system settings
  # ENV variables take precedence over database values when set
  ENV_MAPPING = {
    # Gotify notification settings
    'gotify_url' => 'GOTIFY_URL',
    'gotify_app_token' => 'GOTIFY_APP_TOKEN',
    'gotify_enabled' => 'GOTIFY_ENABLED',
    'gotify_admin_url' => 'GOTIFY_ADMIN_URL',
    'gotify_admin_username' => 'GOTIFY_ADMIN_USERNAME',
    'gotify_admin_password' => 'GOTIFY_ADMIN_PASSWORD',
    'gotify_ssl_verify' => 'GOTIFY_SSL_VERIFY',

    # PyVulnerabilityLookup settings
    'vulnerability_lookup_url' => 'VULNERABILITY_LOOKUP_URL',
    'vulnerability_lookup_enabled' => 'VULNERABILITY_LOOKUP_ENABLED',
    'vulnerability_lookup_scan_schedule' => 'VULNERABILITY_LOOKUP_SCAN_SCHEDULE',
    'vulnerability_lookup_notification_threshold' => 'VULNERABILITY_LOOKUP_NOTIFICATION_THRESHOLD',
    'vulnerability_lookup_python_path' => 'VULNERABILITY_LOOKUP_PYTHON_PATH',
    'vulnerability_lookup_timeout' => 'VULNERABILITY_LOOKUP_TIMEOUT'
  }.freeze

  # Class methods for easy access
  def self.get(key, default = nil)
    # Check ENV first (takes precedence for production/container deployments)
    env_value = check_env(key)
    return env_value unless env_value.nil?

    # Fall back to database
    setting = find_by(key: key)
    return default unless setting

    cast_value(setting)
  end

  # Get value with source information (for UI display)
  # Returns: { value: <value>, source: :env | :db | :default }
  def self.get_with_source(key, default = nil)
    env_value = check_env(key)
    if env_value
      { value: env_value, source: :env }
    else
      setting = find_by(key: key)
      if setting
        { value: cast_value(setting), source: :db }
      else
        { value: default, source: :default }
      end
    end
  end

  # Check if a setting is controlled by an environment variable
  def self.env_override?(key)
    ENV_MAPPING.key?(key) && ENV[ENV_MAPPING[key]].present?
  end

  def self.set(key, value, value_type = 'string')
    setting = find_or_initialize_by(key: key)
    setting.value = value.to_s
    setting.value_type = value_type
    setting.save!
  end

  def self.logo_url
    logo_filename = get('custom_logo')
    if logo_filename.present?
      "/uploads/#{logo_filename}"
    else
      # Default Veracity logo from assets
      ActionController::Base.helpers.asset_path('veracity-logo.svg')
    end
  end

  def self.company_name
    get('company_name', 'Veracity')
  end

  def self.tagline
    get('tagline', 'Infrastructure Management Platform with Batteries Included')
  end

  def self.glassmorphism_enabled?
    get('glassmorphism_enabled', false) == true
  end

  private

  # Check environment variable for a given setting key
  def self.check_env(key)
    env_key = ENV_MAPPING[key]
    return nil unless env_key

    env_value = ENV[env_key]
    return nil if env_value.blank?

    # Infer type from existing setting or use string
    setting = find_by(key: key)
    value_type = setting&.value_type || 'string'

    cast_env_value(env_value, value_type)
  end

  # Cast environment variable value to appropriate type
  def self.cast_env_value(value, value_type)
    case value_type
    when 'boolean'
      ['true', '1', 'yes', 'on'].include?(value.downcase)
    when 'integer'
      value.to_i
    else
      value
    end
  end

  # Cast database value to appropriate type
  def self.cast_value(setting)
    case setting.value_type
    when 'boolean'
      setting.value == 'true'
    when 'integer'
      setting.value.to_i
    when 'file'
      setting.value
    else
      setting.value
    end
  end
end
