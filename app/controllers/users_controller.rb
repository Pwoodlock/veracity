class UsersController < ApplicationController
  before_action :authenticate_user!
  before_action :require_admin!
  before_action :set_user, only: [:show, :edit, :update, :destroy, :toggle_otp]

  def index
    @users = User.order(created_at: :desc)

    # Filter by role if specified
    if params[:role].present? && User::ROLES.include?(params[:role])
      @users = @users.where(role: params[:role])
    end

    # Search by email or name
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @users = @users.where("email LIKE ? OR name LIKE ?", search_term, search_term)
    end
  end

  def show
    # TODO: Once user_id is added to commands table, show user's command history here
    @commands = []
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    # Generate a random password if not provided
    temp_password = nil
    if @user.password.blank?
      temp_password = SecureRandom.hex(8)
      @user.password = temp_password
      @user.password_confirmation = temp_password
    end

    if @user.save
      # Send Gotify notification for new user creation
      GotifyNotificationService.notify_user_event(@user, 'created', "New user created by #{current_user.email}")

      # Show temporary password to admin (since email is not configured)
      if temp_password
        flash[:notice] = "✅ User created: #{@user.email}<br><strong>Temporary Password:</strong> <code>#{temp_password}</code><br><small>⚠️ Save this password and send it to the user - it will only be shown once!</small>".html_safe
      else
        flash[:notice] = "User #{@user.email} created successfully."
      end
      redirect_to users_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    # Don't allow users to change their own role
    if @user == current_user && user_params[:role] != @user.role
      redirect_to users_path, alert: "You cannot change your own role"
      return
    end

    # Track role changes for notifications
    old_role = @user.role
    role_changed = false

    # Update without password if not provided
    if user_params[:password].blank?
      params_to_update = user_params.except(:password, :password_confirmation)
      success = @user.update(params_to_update)
    else
      success = @user.update(user_params)
    end

    if success
      # Send notification if role changed
      if old_role != @user.role
        GotifyNotificationService.notify_user_event(@user, 'role_changed', "Role changed from #{old_role} to #{@user.role} by #{current_user.email}")
      end

      redirect_to users_path, notice: "User updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @user == current_user
      redirect_to users_path, alert: "You cannot delete your own account"
      return
    end

    @user.destroy
    redirect_to users_path, notice: "User deleted successfully"
  end

  def toggle_otp
    if @user.otp_required_for_login
      @user.update(otp_required_for_login: false, otp_secret: nil)
      GotifyNotificationService.notify_user_event(@user, '2fa_disabled', "2FA disabled by #{current_user.email}")
      message = "2FA disabled for #{@user.email}"
    else
      message = "User must enable 2FA from their account settings"
    end

    redirect_to users_path, notice: message
  end

  private

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :name, :role, :password, :password_confirmation)
  end

  def require_admin!
    unless current_user.admin?
      redirect_to dashboard_path, alert: "Only administrators can access user management"
    end
  end
end
