class HetznerApiKey < ApplicationRecord
  # Encrypt API token
  # Use ENV-based secret key for encryption (fallback if credentials not available)
  ENCRYPTION_KEY = (Rails.application.credentials.secret_key_base rescue nil) || ENV['SECRET_KEY_BASE']

  attr_encrypted :api_token, key: ENCRYPTION_KEY[0..31]

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :api_token, presence: true

  # Scopes
  scope :enabled, -> { where(enabled: true) }

  # Callbacks
  after_save :update_salt_pillar
  after_destroy :update_salt_pillar

  # Instance methods
  def formatted_token
    return 'Not set' if api_token.blank?
    # Show first 8 and last 4 characters
    token = api_token.to_s
    if token.length > 12
      "#{token[0..7]}...#{token[-4..-1]}"
    else
      '***hidden***'
    end
  end

  def last_used_display
    return 'Never' unless last_used_at
    "#{time_ago_in_words(last_used_at)} ago"
  end

  def mark_as_used!
    update_column(:last_used_at, Time.current)
  end

  def test_connection
    # Test the Hetzner API connection
    require 'net/http'
    require 'json'

    uri = URI('https://api.hetzner.cloud/v1/servers')
    req = Net::HTTP::Get.new(uri)
    req['Authorization'] = "Bearer #{api_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    if response.code == '200'
      mark_as_used!
      { success: true, message: 'Connection successful' }
    else
      { success: false, message: "API Error: #{response.code}" }
    end
  rescue StandardError => e
    { success: false, message: e.message }
  end

  private

  def update_salt_pillar
    # Update Salt Cloud provider configuration with Hetzner API key
    # This allows Salt Cloud to provision/manage Hetzner Cloud instances
    # See: https://docs.saltproject.io/en/latest/ref/clouds/all/salt.cloud.clouds.hetzner.html
    #
    # NOTE: This feature is optional and will fail gracefully if permissions don't allow
    # We primarily use the Python hcloud library directly, not Salt Cloud

    # Collect all enabled Hetzner API keys
    enabled_keys = HetznerApiKey.enabled.reload

    if enabled_keys.empty?
      # No enabled keys, remove the provider configuration
      provider_path = '/etc/salt/cloud.providers.d/hetzner.conf'
      begin
        File.delete(provider_path) if File.exist?(provider_path)
        Rails.logger.info "Removed Hetzner Cloud provider configuration (no enabled keys)"
      rescue StandardError => e
        Rails.logger.warn "Could not remove Salt Cloud provider config (this is OK): #{e.message}"
      end
      return
    end

    # Build provider configuration for all enabled keys
    provider_config = {}
    enabled_keys.each do |key|
      # Use sanitized name as provider identifier
      provider_name = key.name.downcase.gsub(/[^a-z0-9_-]/, '_')

      provider_config[provider_name] = {
        'driver' => 'hetzner',
        'key' => key.api_token
      }

      # Add project_id if specified
      provider_config[provider_name]['project_id'] = key.project_id if key.project_id.present?
    end

    # Write to Salt Cloud provider configuration
    provider_path = '/etc/salt/cloud.providers.d/hetzner.conf'
    begin
      # Ensure directory exists
      FileUtils.mkdir_p(File.dirname(provider_path))

      # Write YAML configuration
      File.write(provider_path, provider_config.to_yaml)

      # Set proper permissions (readable by salt user)
      FileUtils.chmod(0644, provider_path)

      Rails.logger.info "Updated Salt Cloud provider configuration with #{enabled_keys.count} Hetzner API key(s)"
    rescue Errno::EACCES => e
      # Permission denied - this is expected if Rails doesn't run as root
      Rails.logger.warn "Could not update Salt Cloud provider config (permission denied - this is OK)"
      Rails.logger.debug "Salt Cloud config error: #{e.message}"
    rescue StandardError => e
      # Other errors - log but don't fail
      Rails.logger.warn "Could not update Salt Cloud provider config: #{e.message}"
    end
  end
end
