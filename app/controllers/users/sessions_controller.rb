class Users::SessionsController < Devise::SessionsController
  prepend_before_action :authenticate_with_two_factor, only: [:create]

  # Public action for OTP verification
  def verify_otp
    Rails.logger.info "Verify OTP: Starting verification for session: #{session[:otp_user_id]}"

    user = User.find_by(id: session[:otp_user_id])

    if user && user.otp_required_for_login
      # Check if it's an OTP code or backup code
      if params[:otp_code].present?
        Rails.logger.info "Verify OTP: Code provided for user #{user.email}"

        if user.validate_and_consume_otp!(params[:otp_code])
          # Valid OTP
          Rails.logger.info "Verify OTP: Valid OTP code for user #{user.email}"
          sign_in_and_clear_session(user)
          redirect_to root_path, notice: "Signed in successfully", status: :see_other and return
        elsif user.invalidate_otp_backup_code!(params[:otp_code])
          # Valid backup code
          Rails.logger.info "Verify OTP: Valid backup code for user #{user.email}"
          sign_in_and_clear_session(user)
          flash[:notice] = "Signed in with backup code. You have #{user.otp_backup_codes.length} backup codes remaining."
          redirect_to root_path, status: :see_other and return
        else
          # Invalid code
          Rails.logger.warn "Verify OTP: Invalid code for user #{user.email}"
          flash.now[:alert] = "Invalid verification code. Please try again."
          render 'users/sessions/two_factor', status: :unprocessable_entity
        end
      else
        flash.now[:alert] = "Please enter a verification code"
        render 'users/sessions/two_factor', status: :unprocessable_entity
      end
    else
      Rails.logger.warn "Verify OTP: No user found or 2FA not required for session"
      redirect_to new_user_session_path, alert: "Session expired. Please sign in again.", status: :see_other and return
    end
  rescue => e
    Rails.logger.error "Verify OTP Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to new_user_session_path, alert: "An error occurred during verification. Please try again.", status: :see_other
  end

  protected

  def authenticate_with_two_factor
    # Find user by email
    self.resource = resource_class.find_by(email: params[resource_name][:email])

    if resource
      if resource.valid_password?(params[resource_name][:password])
        # Password is valid - check if 2FA is required
        if resource.otp_required_for_login
          # Store user ID in session for OTP verification
          session[:otp_user_id] = resource.id
          # Redirect to OTP verification page
          render 'users/sessions/two_factor' and return
        else
          # No 2FA required, continue with normal authentication
          return
        end
      end
    end

    # Invalid credentials - let Devise handle it normally
  end

  private

  # SECURITY: Reset entire session to prevent session fixation attacks
  # Completely invalidates the old session ID and creates a new one
  # This prevents an attacker who stole a pre-auth session from gaining access
  def sign_in_and_clear_session(user)
    # Store user ID temporarily since reset_session clears everything
    user_id_to_sign_in = user.id

    # CRITICAL: Reset session completely (generates new session ID)
    reset_session

    # Sign in user with fresh session
    sign_in(:user, user)

    Rails.logger.info "Session reset and user signed in: #{user.email}"
  end
end
