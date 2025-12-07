class ApplicationController < ActionController::Base
  include Pagy::Backend

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Devise and authentication
  before_action :authenticate_user!
  after_action :set_user_id_cookie

  # Helper for checking admin role
  def require_admin!
    unless current_user&.admin?
      redirect_to root_path, alert: 'You must be an admin to access this page.'
    end
  end

  # Helper for checking operator or admin role
  def require_operator!
    unless current_user&.admin? || current_user&.operator?
      redirect_to root_path, alert: 'You must be an operator or admin to access this page.'
    end
  end

  private

  # Set user_id in encrypted cookie for Action Cable authentication
  def set_user_id_cookie
    cookies.encrypted[:user_id] = current_user&.id
  end
end
