class Settings::ProxmoxApiKeysController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_proxmox_api_key, only: [:edit, :update, :destroy, :test, :toggle, :discover_vms]

  def index
    @proxmox_api_keys = ProxmoxApiKey.all.order(created_at: :desc)
    @proxmox_api_key = ProxmoxApiKey.new
    @available_minions = fetch_available_minions
  end

  def create
    @proxmox_api_key = ProxmoxApiKey.new(proxmox_api_key_params)

    if @proxmox_api_key.save
      redirect_to settings_proxmox_api_keys_path, success: 'Proxmox API key added successfully.'
    else
      @proxmox_api_keys = ProxmoxApiKey.all.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @proxmox_api_key.update(proxmox_api_key_params)
      redirect_to settings_proxmox_api_keys_path, success: 'Proxmox API key updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @proxmox_api_key.destroy
    redirect_to settings_proxmox_api_keys_path, success: 'Proxmox API key deleted successfully.'
  end

  def test
    result = @proxmox_api_key.test_connection

    if result[:success]
      render json: { success: true, message: result[:message], data: result[:data] }
    else
      render json: { success: false, message: result[:message] }, status: :unprocessable_entity
    end
  end

  def toggle
    @proxmox_api_key.update(enabled: !@proxmox_api_key.enabled)
    redirect_to settings_proxmox_api_keys_path, success: "API key #{@proxmox_api_key.enabled? ? 'enabled' : 'disabled'}."
  end

  def discover_vms
    node_name = params[:node]

    if node_name.blank?
      render json: { success: false, message: 'Node name is required' }, status: :unprocessable_entity
      return
    end

    result = ProxmoxService.list_vms(@proxmox_api_key, node_name)

    if result[:success]
      render json: { success: true, vms: result[:data][:vms] }
    else
      render json: { success: false, message: result[:error] }, status: :unprocessable_entity
    end
  end

  private

  def set_proxmox_api_key
    @proxmox_api_key = ProxmoxApiKey.find(params[:id])
  end

  def proxmox_api_key_params
    params.require(:proxmox_api_key).permit(
      :name,
      :proxmox_url,
      :minion_id,
      :api_token,
      :username,
      :token_name,
      :realm,
      :verify_ssl,
      :enabled,
      :notes
    )
  end

  def fetch_available_minions
    # Get list of accepted minions from Salt using list_keys
    result = SaltService.list_keys
    if result && result['return']&.first
      data = result['return'].first['data']
      # Return array of accepted minion IDs for the select dropdown
      data['return']['minions'] || []
    else
      []
    end
  rescue StandardError => e
    Rails.logger.error "Failed to fetch minions: #{e.message}"
    []
  end

  def require_admin!
    redirect_to root_path, alert: 'Access denied. Admin privileges required.' unless current_user.admin?
  end
end
