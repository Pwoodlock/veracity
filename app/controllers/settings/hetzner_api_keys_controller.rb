class Settings::HetznerApiKeysController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_hetzner_api_key, only: [:edit, :update, :destroy, :test, :toggle]

  def index
    @hetzner_api_keys = HetznerApiKey.all.order(created_at: :desc)
    @hetzner_api_key = HetznerApiKey.new
  end

  def create
    @hetzner_api_key = HetznerApiKey.new(hetzner_api_key_params)

    if @hetzner_api_key.save
      redirect_to settings_hetzner_api_keys_path, success: 'Hetzner API key added successfully.'
    else
      @hetzner_api_keys = HetznerApiKey.all.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @hetzner_api_key.update(hetzner_api_key_params)
      redirect_to settings_hetzner_api_keys_path, success: 'Hetzner API key updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @hetzner_api_key.destroy
    redirect_to settings_hetzner_api_keys_path, success: 'Hetzner API key deleted successfully.'
  end

  def test
    result = @hetzner_api_key.test_connection

    if result[:success]
      render json: { success: true, message: result[:message] }
    else
      render json: { success: false, message: result[:message] }, status: :unprocessable_entity
    end
  end

  def toggle
    @hetzner_api_key.update(enabled: !@hetzner_api_key.enabled)
    redirect_to settings_hetzner_api_keys_path, success: "API key #{@hetzner_api_key.enabled? ? 'enabled' : 'disabled'}."
  end

  private

  def set_hetzner_api_key
    @hetzner_api_key = HetznerApiKey.find(params[:id])
  end

  def hetzner_api_key_params
    params.require(:hetzner_api_key).permit(:name, :api_token, :project_id, :enabled, :notes)
  end

  def require_admin!
    redirect_to root_path, alert: 'Access denied. Admin privileges required.' unless current_user.admin?
  end
end
