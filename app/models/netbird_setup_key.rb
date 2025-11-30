# frozen_string_literal: true

class NetbirdSetupKey < ApplicationRecord
  # Encrypt setup key
  ENCRYPTION_KEY = (Rails.application.credentials.secret_key_base rescue nil) || ENV['SECRET_KEY_BASE']

  attr_encrypted :setup_key, key: ENCRYPTION_KEY[0..31]

  # Validations
  validates :name, presence: true, uniqueness: true
  validates :management_url, presence: true, format: { with: /\Ahttps?:\/\/.+\z/, message: "must be a valid URL" }
  validates :setup_key, presence: true
  validates :setup_key, format: {
    with: /\A[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\z/,
    message: "must be a valid UUID format (e.g., 4F0F9A28-C7F6-4E87-B855-015FC929FC63)"
  }, if: -> { setup_key.present? }

  # Scopes
  scope :enabled, -> { where(enabled: true) }

  # Instance methods
  def formatted_setup_key
    return 'Not set' if setup_key.blank?
    # Show first 8 and last 4 characters of UUID
    key = setup_key.to_s
    if key.length > 12
      "#{key[0..7]}...#{key[-4..-1]}"
    else
      '***hidden***'
    end
  end

  def last_used_display
    return 'Never' unless last_used_at
    "#{((Time.current - last_used_at) / 1.day).round} days ago"
  end

  def mark_as_used!
    update_columns(last_used_at: Time.current, usage_count: usage_count + 1)
  end

  # Build full management URL with port
  def full_management_url
    url = management_url.to_s
    url = "https://#{url}" unless url.start_with?('http')

    # Add port if not 443 and not already in URL
    if port.present? && port != 443 && !url.match?(/:\d+\z/)
      url += ":#{port}"
    end

    url
  end

  # Generate the netbird up command (for display only - NOT for execution)
  def netbird_command
    "netbird up --management-url #{full_management_url} --setup-key #{setup_key}"
  end

  # Generate full installation + connection script (for display only)
  def full_install_script
    <<~SCRIPT
      # Install NetBird agent
      curl -fsSL https://pkgs.netbird.io/install.sh | sh

      # Connect to NetBird network
      #{netbird_command}
    SCRIPT
  end

  # DEPRECATED: Insecure method - setup key appears in command line
  # Use deploy_to_minion_secure instead
  def salt_install_command
    Rails.logger.warn "SECURITY WARNING: salt_install_command exposes setup key in command line. Use deploy_to_minion_secure instead."
    "curl -fsSL https://pkgs.netbird.io/install.sh | sh && netbird up --management-url #{full_management_url} --setup-key #{setup_key}"
  end

  # SECURE: Deploy NetBird to a minion using Salt pillar
  # The setup key is passed via encrypted pillar data, never appearing in:
  # - Command-line arguments (ps aux won't show it)
  # - Salt job cache
  # - Shell history
  #
  # @param minion_id [String] Target minion ID
  # @return [Hash] Result with :success, :output, :error keys
  def deploy_to_minion_secure(minion_id)
    Rails.logger.info "Deploying NetBird to #{minion_id} using secure pillar method"

    begin
      # Step 1: Write pillar data with the secret
      pillar_data = {
        'netbird' => {
          'management_url' => full_management_url,
          'setup_key' => setup_key
        }
      }

      pillar_result = SaltService.write_minion_pillar(minion_id, 'netbird', pillar_data)
      unless pillar_result[:success]
        return {
          success: false,
          error: "Failed to write pillar: #{pillar_result[:error]}",
          output: nil
        }
      end

      # Step 2: Refresh pillar on the minion so it can see the new data
      refresh_result = SaltService.refresh_pillar(minion_id)
      unless refresh_result[:success]
        # Clean up pillar file before returning
        SaltService.delete_minion_pillar(minion_id, 'netbird')
        return {
          success: false,
          error: "Failed to refresh pillar: #{refresh_result[:output]}",
          output: nil
        }
      end

      # Step 3: Apply the NetBird state (reads setup key from pillar)
      state_result = SaltService.apply_state_with_pillar(minion_id, 'netbird', timeout: 300)

      # Step 4: ALWAYS clean up pillar file (even if state failed)
      # The setup key should not persist on disk
      SaltService.delete_minion_pillar(minion_id, 'netbird')

      if state_result[:success]
        Rails.logger.info "NetBird deployed successfully to #{minion_id}"
        {
          success: true,
          output: state_result[:output],
          error: nil
        }
      else
        Rails.logger.error "NetBird deployment failed on #{minion_id}: #{state_result[:output]}"
        {
          success: false,
          output: state_result[:output],
          error: state_result[:error] || "State apply failed"
        }
      end
    rescue StandardError => e
      Rails.logger.error "NetBird deployment error for #{minion_id}: #{e.message}"
      # Attempt cleanup even on exception
      SaltService.delete_minion_pillar(minion_id, 'netbird') rescue nil
      {
        success: false,
        error: e.message,
        output: nil
      }
    end
  end

  # Check if NetBird is connected on a minion
  # @param minion_id [String] Target minion ID
  # @return [Hash] Result with :connected and :status keys
  def check_connection_status(minion_id)
    result = SaltService.run_command(minion_id, 'cmd.run', ['netbird status'], timeout: 30)

    if result[:success]
      output = result[:output].to_s
      connected = output.include?('Connected') || output.include?('connected')
      {
        connected: connected,
        status: output
      }
    else
      {
        connected: false,
        status: "Unable to check: #{result[:output]}"
      }
    end
  rescue StandardError => e
    {
      connected: false,
      status: "Error: #{e.message}"
    }
  end
end
