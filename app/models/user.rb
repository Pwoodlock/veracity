class User < ApplicationRecord
  # Require dependencies
  require 'bcrypt'
  require 'rotp'

  # Include default devise modules including omniauth
  # Note: :registerable removed - users can only be created by admins
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable,
         :trackable, :lockable, :timeoutable,
         :omniauthable, omniauth_providers: [:zitadel]

  # Encrypt OTP secret
  attr_encrypted :otp_secret, key: ENV['SECRET_KEY_BASE'][0..31]

  # Associations
  has_many :commands, dependent: :nullify  # Nullify to keep command history even if user is deleted
  has_many :tasks, dependent: :destroy
  has_many :task_runs, dependent: :nullify

  # Role constants
  ROLES = %w[admin operator viewer].freeze

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :role, presence: true, inclusion: { in: ROLES }

  # Role helper methods
  def admin?
    role == 'admin'
  end

  def operator?
    role == 'operator'
  end

  def viewer?
    role == 'viewer'
  end

  # Check if user can access Avo
  def can_access_avo?
    admin? || operator?
  end

  # OAuth authentication handler with session validation
  def self.from_omniauth(auth)
    user = where(provider: auth.provider, uid: auth.uid).first_or_initialize do |new_user|
      new_user.email = auth.info.email
      new_user.password = Devise.friendly_token[0, 20]
      new_user.name = auth.info.name || auth.info.email
      new_user.role = 'admin' # First Zitadel user gets admin role by default
    end

    # Update session validation data from ID token
    user.update_session_from_auth(auth)
    user.save!
    user
  end

  # Update session data from OAuth auth response
  def update_session_from_auth(auth)
    # Extract data from ID token (JWT claims)
    id_token = auth.extra&.raw_info
    credentials = auth.credentials

    # Store authentication time (when user was verified by Zitadel)
    self.auth_time = Time.at(id_token['auth_time']) if id_token&.dig('auth_time')

    # Store session ID if provided
    self.session_id = id_token['sid'] if id_token&.dig('sid')

    # Store token expiration
    self.token_expires_at = Time.at(credentials.expires_at) if credentials&.expires_at

    # Update last auth check timestamp
    self.last_auth_check = Time.current
  end

  # Check if session is still valid
  def session_valid?
    return false if token_expires_at.blank?
    return false if token_expires_at < Time.current

    # Session is valid if token hasn't expired
    true
  end

  # Check if session needs re-validation (older than 1 hour)
  def needs_revalidation?
    return true if last_auth_check.blank?
    last_auth_check < 1.hour.ago
  end

  # Generate new OTP secret
  def self.generate_otp_secret
    ROTP::Base32.random
  end

  # Generate provisioning URI for QR code
  def otp_provisioning_uri(label, issuer:)
    totp = ROTP::TOTP.new(otp_secret, issuer: issuer)
    totp.provisioning_uri(label)
  end

  # Verify OTP code
  def validate_and_consume_otp!(code)
    return false unless otp_secret

    totp = ROTP::TOTP.new(otp_secret)

    # Verify with drift (allow 30 seconds before/after)
    # verify() returns the timestamp when the code was valid, or nil if invalid
    verified_at = totp.verify(code, drift_behind: 1, drift_ahead: 1)

    if verified_at
      # Calculate current timestep (30-second intervals since Unix epoch)
      current_timestep = Time.current.to_i / 30

      # Prevent replay attacks - only accept if this timestep hasn't been used
      if consumed_timestep.nil? || current_timestep > consumed_timestep
        update_column(:consumed_timestep, current_timestep)
        return true
      else
        Rails.logger.warn "OTP replay attack detected for user #{email}: timestep #{current_timestep} already consumed"
        return false
      end
    end

    false
  end

  # Generate backup codes for 2FA
  def generate_otp_backup_codes!
    codes = 10.times.map { SecureRandom.hex(4) }
    hashed_codes = codes.map { |code| BCrypt::Password.create(code).to_s }
    update!(otp_backup_codes: hashed_codes)
    codes # Return unhashed codes for user to save
  end

  # Verify backup code
  def invalidate_otp_backup_code!(code)
    return false unless otp_backup_codes

    otp_backup_codes.each_with_index do |hashed_code, index|
      if BCrypt::Password.new(hashed_code) == code
        new_codes = otp_backup_codes.dup
        new_codes.delete_at(index)
        update!(otp_backup_codes: new_codes)
        return true
      end
    end
    false
  rescue BCrypt::Errors::InvalidHash
    false
  end

  # Enable 2FA
  def enable_two_factor!
    self.otp_secret = User.generate_otp_secret
    self.otp_required_for_login = true
    codes = generate_otp_backup_codes!
    save!
    codes
  end

  # Disable 2FA
  def disable_two_factor!
    self.otp_secret = nil
    self.otp_required_for_login = false
    self.otp_backup_codes = []
    self.consumed_timestep = nil
    save!
  end
end
