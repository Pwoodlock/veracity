class OnboardingController < ApplicationController
  before_action :authenticate_user!

  # SECURITY: Authorization checks for minion key management
  # Viewers: Can view onboarding page (index, install)
  # Operators & Admins: Can accept/reject minion keys
  before_action :require_operator!, only: [:accept_key, :reject_key, :refresh]

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
        # Try to discover and register the minion
        sleep 2

        begin
          minions_data = SaltService.discover_all_minions
          minion_data = minions_data.find { |m| m[:minion_id] == minion_id }

          if minion_data
            server = Server.find_or_initialize_by(minion_id: minion_id)
            grains = minion_data[:grains]

            # Update server details
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

            if server.save
              flash[:success] = "✓ Minion key accepted and server registered: #{server.hostname}"
            else
              flash[:warning] = "Key accepted but server registration had issues: #{server.errors.full_messages.join(', ')}"
            end
          else
            flash[:warning] = "Key accepted! Minion #{minion_id} is not responding yet. It may take a moment to come online."
          end
        rescue StandardError => e
          Rails.logger.error "Error auto-registering minion #{minion_id}: #{e.message}"
          flash[:warning] = "Key accepted but automatic registration failed: #{e.message}"
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
end
