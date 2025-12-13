class OnboardingController < ApplicationController
  before_action :authenticate_user!

  # SECURITY: Authorization checks for minion key management
  # Viewers: Can view onboarding page (index, install)
  # Operators & Admins: Can accept/reject minion keys
  # Admins only: Can delete accepted keys, cleanup orphaned keys, manage auto-acceptance
  before_action :require_operator!, only: [:accept_key, :reject_key, :bulk_accept_keys, :bulk_reject_keys, :refresh]
  before_action :require_admin!, only: [:delete_key, :bulk_delete_keys, :cleanup_orphaned_keys, :toggle_auto_accept, :add_fingerprint, :remove_fingerprint]

  # Show pending minion keys and accept form
  def index
    load_all_keys
    load_auto_acceptance_settings
  end

  # Show install script page
  def install
    @host = ENV.fetch('APPLICATION_HOST', request.host_with_port)
    @protocol = Rails.env.production? ? 'https' : request.protocol.sub('://', '')
    @install_url = "#{@protocol}://#{@host}/install-minion.sh"
  end

  # Accept a minion key
  def accept_key
    minion_id = params[:minion_id]
    fingerprint = params[:fingerprint]

    if minion_id.blank? || fingerprint.blank?
      flash[:error] = "Minion ID and fingerprint are required"
      redirect_to onboarding_path
      return
    end

    Rails.logger.info "User #{current_user.email} accepting key for minion: #{minion_id}"

    begin
      # Accept key with fingerprint verification
      result = SaltService.accept_key_with_verification(minion_id, fingerprint)

      if result[:success]
        # Key accepted - register minion in background to avoid blocking
        # The minion needs a moment to establish connection after key acceptance
        flash[:success] = "✓ Minion key accepted: #{minion_id}. Server will be registered automatically."

        # Queue background registration (non-blocking)
        Thread.new do
          sleep 1.5  # Reduced from 2 seconds
          register_accepted_minions([minion_id])
        end

        # Send notification if enabled
        if SystemSetting.get('notify_on_manual_minion_add', false)
          send_manual_accept_notification(minion_id)
        end

        # Audit log
        Rails.logger.info "[MANUAL-ACCEPT] User #{current_user.email} accepted key: #{minion_id}"
      else
        flash[:error] = "Failed to accept key: #{result[:message]}"
      end

    rescue SaltService::SaltAPIError => e
      Rails.logger.error "Salt API error accepting key: #{e.message}"

      if e.message.include?('Fingerprint mismatch')
        flash[:error] = "Fingerprint verification failed! The provided fingerprint does not match."
      elsif e.message.include?('Could not retrieve fingerprint')
        flash[:error] = "Cannot retrieve fingerprint for this minion. It may not exist or already be processed."
      else
        flash[:error] = "Failed to accept key: #{e.message}"
      end

    rescue StandardError => e
      Rails.logger.error "Unexpected error accepting key: #{e.message}"
      flash[:error] = "An unexpected error occurred: #{e.message}"
    end

    redirect_to onboarding_path
  end

  # Reject a minion key
  def reject_key
    minion_id = params[:minion_id]

    if minion_id.blank?
      flash[:error] = "Minion ID is required"
      redirect_to onboarding_path
      return
    end

    begin
      SaltService.reject_key(minion_id)
      flash[:success] = "Minion key rejected: #{minion_id}"
    rescue StandardError => e
      flash[:error] = "Failed to reject key: #{e.message}"
    end

    redirect_to onboarding_path
  end

  # Bulk accept multiple minion keys
  def bulk_accept_keys
    minion_keys_param = params[:minion_keys]

    # Handle both array and hash formats from form submission
    # Use permit! because Rails requires explicit permission before .to_h on nested params
    minion_keys = if minion_keys_param.is_a?(ActionController::Parameters)
                    minion_keys_param.permit!.to_h.values
                  elsif minion_keys_param.is_a?(Array)
                    minion_keys_param
                  else
                    []
                  end

    if minion_keys.empty?
      flash[:error] = "No minions selected"
      redirect_to onboarding_path
      return
    end

    Rails.logger.info "User #{current_user.email} bulk accepting #{minion_keys.size} keys"

    accepted = []
    failed = []

    minion_keys.each do |key_data|
      minion_id = key_data['minion_id'] || key_data[:minion_id]
      fingerprint = key_data['fingerprint'] || key_data[:fingerprint]

      begin
        result = SaltService.accept_key_with_verification(minion_id, fingerprint)
        if result[:success]
          accepted << minion_id
        else
          failed << { minion_id: minion_id, error: result[:message] }
        end
      rescue StandardError => e
        failed << { minion_id: minion_id, error: e.message }
      end
    end

    # Wait once for all minions to connect, then discover
    if accepted.any?
      sleep 2
      register_accepted_minions(accepted)
    end

    if failed.empty?
      flash[:success] = "✓ Successfully accepted #{accepted.size} minion key(s)"
    elsif accepted.any?
      flash[:warning] = "Accepted #{accepted.size} key(s), but #{failed.size} failed: #{failed.map { |f| f[:minion_id] }.join(', ')}"
    else
      flash[:error] = "Failed to accept all keys: #{failed.map { |f| "#{f[:minion_id]}: #{f[:error]}" }.join('; ')}"
    end

    redirect_to onboarding_path
  end

  # Bulk reject multiple minion keys
  # NOTE: This actually DELETES the keys permanently, not just rejects them
  # This prevents orphaned keys from accumulating
  def bulk_reject_keys
    minion_ids = params[:minion_ids] || []

    if minion_ids.empty?
      flash[:error] = "No minions selected"
      redirect_to onboarding_path
      return
    end

    Rails.logger.info "User #{current_user.email} bulk deleting #{minion_ids.size} keys"

    deleted = []
    failed = []

    minion_ids.each do |minion_id|
      begin
        result = SaltService.delete_key(minion_id)
        if result && result['return']
          deleted << minion_id
        else
          failed << { minion_id: minion_id, error: "API returned false" }
        end
      rescue StandardError => e
        failed << { minion_id: minion_id, error: e.message }
      end
    end

    if failed.empty?
      flash[:success] = "Deleted #{deleted.size} minion key(s)"
    elsif deleted.any?
      flash[:warning] = "Deleted #{deleted.size} key(s), but #{failed.size} failed"
    else
      flash[:error] = "Failed to delete all keys"
    end

    redirect_to onboarding_path
  end

  # Delete a single key (any type)
  def delete_key
    minion_id = params[:minion_id]
    key_type = params[:key_type]

    if minion_id.blank?
      flash[:error] = "Minion ID is required"
      redirect_to onboarding_path
      return
    end

    Rails.logger.warn "[ADMIN-DELETE] User #{current_user.email} deleting #{key_type} key: #{minion_id}"

    begin
      result = SaltService.delete_key(minion_id)

      if result && result['return']
        # If it's an accepted key, also delete the Server record
        if key_type == 'accepted'
          server = Server.find_by(minion_id: minion_id)
          if server
            server.destroy
            Rails.logger.info "Deleted associated Server record for #{minion_id}"
          end
        end

        flash[:success] = "Deleted key: #{minion_id}"
      else
        flash[:error] = "Failed to delete key: #{minion_id}"
      end
    rescue StandardError => e
      Rails.logger.error "Error deleting key: #{e.message}"
      flash[:error] = "Error deleting key: #{e.message}"
    end

    redirect_to onboarding_path
  end

  # Bulk delete keys
  def bulk_delete_keys
    minion_ids = params[:minion_ids] || []
    key_type = params[:key_type]

    if minion_ids.empty?
      flash[:error] = "No keys selected"
      redirect_to onboarding_path
      return
    end

    Rails.logger.warn "[ADMIN-BULK-DELETE] User #{current_user.email} deleting #{minion_ids.size} #{key_type} keys"

    deleted = []
    failed = []

    minion_ids.each do |minion_id|
      begin
        result = SaltService.delete_key(minion_id)

        if result && result['return']
          deleted << minion_id

          # Delete associated Server record for accepted keys
          if key_type == 'accepted'
            server = Server.find_by(minion_id: minion_id)
            server&.destroy
          end

          Rails.logger.info "[ADMIN-DELETE] Deleted #{key_type} key: #{minion_id}"
        else
          failed << { minion_id: minion_id, error: "API returned false" }
        end
      rescue StandardError => e
        Rails.logger.error "Error deleting #{minion_id}: #{e.message}"
        failed << { minion_id: minion_id, error: e.message }
      end
    end

    if failed.empty?
      flash[:success] = "Deleted #{deleted.size} #{key_type} key(s)"
    elsif deleted.any?
      flash[:warning] = "Deleted #{deleted.size} key(s), but #{failed.size} failed"
    else
      flash[:error] = "Failed to delete all keys"
    end

    redirect_to onboarding_path
  end

  # Clean up orphaned pending keys (keys without associated servers)
  def cleanup_orphaned_keys
    Rails.logger.info "User #{current_user.email} cleaning up orphaned keys"

    begin
      result = SaltService.cleanup_orphaned_pending_keys

      if result[:success]
        if result[:deleted_keys].any?
          flash[:success] = "#{result[:message]}: #{result[:deleted_keys].join(', ')}"
        else
          flash[:notice] = result[:message]
        end
      else
        flash[:warning] = result[:message]
      end
    rescue StandardError => e
      Rails.logger.error "Error during cleanup: #{e.message}"
      flash[:error] = "Cleanup failed: #{e.message}"
    end

    redirect_to onboarding_path
  end

  # Refresh the pending keys list (legacy)
  def refresh
    load_pending_keys
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "pending-keys",
          partial: "onboarding/pending_keys",
          locals: { pending_keys: @pending_keys }
        )
      end
      format.html { redirect_to onboarding_path }
    end
  end

  # Refresh all keys (for auto-refresh)
  def refresh_keys
    load_all_keys
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "all-keys-tabs",
          partial: "onboarding/all_keys_tabs",
          locals: { all_keys: @all_keys }
        )
      end
      format.html { redirect_to onboarding_path }
    end
  end

  # Toggle auto-accept mode
  def toggle_auto_accept
    enabled = params[:enabled] == '1' || params[:enabled] == 'on'
    SystemSetting.set('auto_accept_keys_enabled', enabled)

    if enabled
      flash[:success] = "Auto-accept mode enabled. Whitelisted keys will be accepted automatically."
      Rails.logger.info "[AUTO-ACCEPT] User #{current_user.email} enabled auto-accept mode"
    else
      flash[:notice] = "Auto-accept mode disabled."
      Rails.logger.info "[AUTO-ACCEPT] User #{current_user.email} disabled auto-accept mode"
    end

    redirect_to onboarding_path
  end

  # Add fingerprint to whitelist
  def add_fingerprint
    fingerprint = params[:fingerprint]&.strip

    if fingerprint.blank?
      flash[:error] = "Fingerprint cannot be blank"
      redirect_to onboarding_path
      return
    end

    # Validate fingerprint format (SHA256: XX:XX:XX:... 64 hex chars = 32 pairs)
    unless fingerprint.match?(/^([0-9a-fA-F]{2}:){15,63}[0-9a-fA-F]{2}$/)
      flash[:error] = "Invalid fingerprint format. Expected: a1:b2:c3:d4:..."
      redirect_to onboarding_path
      return
    end

    whitelist_json = SystemSetting.get('auto_accept_fingerprint_whitelist', '[]')
    whitelist = JSON.parse(whitelist_json) rescue []

    if whitelist.include?(fingerprint)
      flash[:warning] = "Fingerprint already in whitelist"
    else
      whitelist << fingerprint
      SystemSetting.set('auto_accept_fingerprint_whitelist', whitelist.to_json)
      flash[:success] = "Fingerprint added to whitelist"
      Rails.logger.info "[AUTO-ACCEPT] User #{current_user.email} added fingerprint to whitelist: #{fingerprint}"
    end

    redirect_to onboarding_path
  end

  # Remove fingerprint from whitelist
  def remove_fingerprint
    fingerprint = params[:fingerprint]

    if fingerprint.blank?
      flash[:error] = "Fingerprint cannot be blank"
      redirect_to onboarding_path
      return
    end

    whitelist_json = SystemSetting.get('auto_accept_fingerprint_whitelist', '[]')
    whitelist = JSON.parse(whitelist_json) rescue []

    if whitelist.delete(fingerprint)
      SystemSetting.set('auto_accept_fingerprint_whitelist', whitelist.to_json)
      flash[:success] = "Fingerprint removed from whitelist"
      Rails.logger.info "[AUTO-ACCEPT] User #{current_user.email} removed fingerprint from whitelist: #{fingerprint}"
    else
      flash[:error] = "Fingerprint not found in whitelist"
    end

    redirect_to onboarding_path
  end

  private

  def load_pending_keys
    begin
      @pending_keys = SaltService.list_pending_keys
    rescue SaltService::ConnectionError => e
      Rails.logger.error "Salt API connection error: #{e.message}"
      flash.now[:error] = "Cannot connect to Salt Master: #{e.message}"
      @pending_keys = []
    rescue StandardError => e
      Rails.logger.error "Failed to fetch pending keys: #{e.message}"
      flash.now[:error] = "Error fetching pending keys: #{e.message}"
      @pending_keys = []
    end
  end

  def load_all_keys
    begin
      @all_keys = SaltService.list_all_keys
    rescue SaltService::ConnectionError => e
      Rails.logger.error "Salt API connection error: #{e.message}"
      flash.now[:error] = "Cannot connect to Salt Master: #{e.message}"
      @all_keys = { pending: [], accepted: [], rejected: [], denied: [] }
    rescue StandardError => e
      Rails.logger.error "Failed to fetch keys: #{e.message}"
      flash.now[:error] = "Error fetching keys: #{e.message}"
      @all_keys = { pending: [], accepted: [], rejected: [], denied: [] }
    end
  end

  def load_auto_acceptance_settings
    @auto_accept_enabled = SystemSetting.get('auto_accept_keys_enabled', false)
    whitelist_json = SystemSetting.get('auto_accept_fingerprint_whitelist', '[]')
    @fingerprint_whitelist = JSON.parse(whitelist_json) rescue []
  end

  # Send Gotify notification for manually accepted key
  def send_manual_accept_notification(minion_id)
    begin
      GotifyNotificationService.send_notification(
        title: 'Minion Key Manually Accepted',
        message: "✅ Minion manually accepted: #{minion_id}",
        priority: 5,
        notification_type: 'minion_manual_added'
      )
    rescue StandardError => e
      Rails.logger.error "[MANUAL-ACCEPT] Failed to send notification: #{e.message}"
    end
  end

  # Register multiple accepted minions efficiently
  def register_accepted_minions(minion_ids)
    begin
      minions_data = SaltService.discover_all_minions

      minion_ids.each do |minion_id|
        minion_data = minions_data.find { |m| m[:minion_id] == minion_id }
        next unless minion_data

        server = Server.find_or_initialize_by(minion_id: minion_id)
        grains = minion_data[:grains]

        server.hostname = grains['id'] || grains['nodename'] || minion_id
        server.ip_address = grains['fqdn_ip4']&.first || grains['ipv4']&.first
        server.status = minion_data[:online] ? 'online' : 'offline'
        server.os_family = grains['os_family']
        server.os_name = grains['os']
        server.os_version = grains['osrelease'] || grains['osmajorrelease']&.to_s
        server.cpu_cores = grains['num_cpus']
        server.memory_gb = (grains['mem_total'].to_f / 1024.0).round(2) if grains['mem_total']
        server.grains = grains
        server.last_seen = Time.current if minion_data[:online]
        server.last_heartbeat = Time.current if minion_data[:online]

        server.save
      end
    rescue StandardError => e
      Rails.logger.error "Error registering minions: #{e.message}"
    end
  end
end
