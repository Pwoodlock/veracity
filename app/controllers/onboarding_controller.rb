class OnboardingController < ApplicationController
  before_action :authenticate_user!

  # SECURITY: Authorization checks for minion key management
  # Viewers: Can view onboarding page (index, install)
  # Operators & Admins: Can accept/reject minion keys
  # Admins only: Can cleanup orphaned keys
  before_action :require_operator!, only: [:accept_key, :reject_key, :bulk_accept_keys, :bulk_reject_keys, :refresh]
  before_action :require_admin!, only: [:cleanup_orphaned_keys]

  # Show pending minion keys and accept form
  def index
    load_pending_keys
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

  # Refresh the pending keys list
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
