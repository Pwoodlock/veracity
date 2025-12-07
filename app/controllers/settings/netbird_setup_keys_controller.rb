# frozen_string_literal: true

class Settings::NetbirdSetupKeysController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_netbird_setup_key, only: [:edit, :update, :destroy, :toggle, :deploy]

  def index
    @netbird_setup_keys = NetbirdSetupKey.all.order(created_at: :desc)
    @netbird_setup_key = NetbirdSetupKey.new(
      management_url: '',
      port: 443
    )
    @servers = Server.includes(:group).order(:hostname)
    @groups = Group.order(:name)
  end

  def create
    @netbird_setup_key = NetbirdSetupKey.new(netbird_setup_key_params)

    if @netbird_setup_key.save
      redirect_to settings_netbird_setup_keys_path, notice: 'NetBird setup key added successfully.'
    else
      @netbird_setup_keys = NetbirdSetupKey.all.order(created_at: :desc)
      @servers = Server.includes(:group).order(:hostname)
      @groups = Group.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @netbird_setup_key.update(netbird_setup_key_params)
      redirect_to settings_netbird_setup_keys_path, notice: 'NetBird setup key updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @netbird_setup_key.destroy
    redirect_to settings_netbird_setup_keys_path, notice: 'NetBird setup key deleted successfully.'
  end

  def toggle
    @netbird_setup_key.update(enabled: !@netbird_setup_key.enabled)
    redirect_to settings_netbird_setup_keys_path, notice: "Setup key #{@netbird_setup_key.enabled? ? 'enabled' : 'disabled'}."
  end

  def deploy
    # Get target minions from params
    target_type = params[:target_type] # 'minion', 'group', or 'all'
    target_ids = params[:target_ids] || []

    # Build target list based on selection
    minion_ids = case target_type
                 when 'all'
                   Server.online.pluck(:minion_id).compact
                 when 'group'
                   Server.where(group_id: target_ids).online.pluck(:minion_id).compact
                 when 'minion'
                   Server.where(id: target_ids).online.pluck(:minion_id).compact
                 else
                   []
                 end

    if minion_ids.empty?
      render json: { success: false, message: 'No valid targets selected' }, status: :unprocessable_entity
      return
    end

    # Execute the NetBird deployment via Salt using SECURE pillar method
    # The setup key is passed via encrypted pillar data, never appearing in:
    # - Command-line arguments (ps aux won't show it)
    # - Salt job cache
    # - Shell history
    begin
      results = {}
      errors = []

      minion_ids.each do |minion_id|
        # Use secure pillar-based deployment
        result = @netbird_setup_key.deploy_to_minion_secure(minion_id)

        if result[:success]
          results[minion_id] = { success: true, output: result[:output] }
        else
          errors << {
            minion_id: minion_id,
            error: result[:error] || result[:output] || 'Unknown error'
          }
        end
      end

      @netbird_setup_key.mark_as_used!

      if errors.empty?
        render json: {
          success: true,
          message: "NetBird deployed securely to #{minion_ids.size} server(s)",
          results: results
        }
      else
        render json: {
          success: true,
          message: "NetBird deployed with some errors",
          results: results,
          errors: errors
        }
      end
    rescue StandardError => e
      Rails.logger.error "NetBird deployment error: #{e.message}"
      render json: { success: false, message: e.message }, status: :unprocessable_entity
    end
  end

  private

  def set_netbird_setup_key
    @netbird_setup_key = NetbirdSetupKey.find(params[:id])
  end

  def netbird_setup_key_params
    params.require(:netbird_setup_key).permit(
      :name, :management_url, :port, :setup_key,
      :netbird_group, :enabled, :notes
    )
  end

  def require_admin!
    redirect_to root_path, alert: 'Access denied. Admin privileges required.' unless current_user.admin?
  end
end
