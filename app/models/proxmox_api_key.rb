class ProxmoxApiKey < ApplicationRecord
  # Encrypt API token
  # Use ENV-based secret key for encryption (fallback if credentials not available)
  ENCRYPTION_KEY = (Rails.application.credentials.secret_key_base rescue nil) || ENV['SECRET_KEY_BASE']

  attr_encrypted :api_token, key: ENCRYPTION_KEY[0..31]

  # Associations
  has_many :servers, foreign_key: 'proxmox_api_key_id', dependent: :nullify

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :proxmox_url, presence: true, format: { with: /\Ahttps?:\/\/.+\z/, message: "must be a valid URL" }
  validates :minion_id, presence: true
  validates :username, presence: true
  validates :token_name, presence: true
  validates :api_token, presence: true
  validates :realm, inclusion: { in: %w[pam pve ldap ad], allow_blank: true }

  # Scopes
  scope :enabled, -> { where(enabled: true) }

  # Build the full token ID (user@realm!tokenname)
  def token_id
    "#{username}@#{realm}!#{token_name}"
  end

  # Build the full API authorization header value
  def authorization_header
    "PVEAPIToken=#{token_id}=#{api_token}"
  end

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
    "#{((Time.current - last_used_at) / 1.day).round} days ago"
  end

  def mark_as_used!
    update_column(:last_used_at, Time.current)
  end

  def test_connection
    # Test Proxmox API connection via Python script through Salt
    return { success: false, message: 'API key is disabled' } unless enabled?

    begin
      # Construct base API URL without port if port is already in proxmox_url
      api_url = proxmox_url

      # Use ProxmoxService to test connection
      # This will execute a simple API call (like get version or cluster status)
      result = ProxmoxService.test_connection(self)

      if result[:success]
        mark_as_used!
        { success: true, message: 'Connection successful', data: result[:data] }
      else
        { success: false, message: result[:error] || 'Connection failed' }
      end
    rescue StandardError => e
      Rails.logger.error "ProxmoxApiKey test_connection error: #{e.message}"
      { success: false, message: e.message }
    end
  end

  # Helper to construct full API URL
  def full_api_url
    # Ensure URL has proper format
    url = proxmox_url
    url = "https://#{url}" unless url.start_with?('http')
    url += ':8006' unless url.include?(':') && url.split(':').last.to_i > 0
    url
  end

  # Server count using this API key
  def server_count
    servers.count
  end
end
