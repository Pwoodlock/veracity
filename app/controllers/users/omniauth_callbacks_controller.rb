# frozen_string_literal: true

module Users
  # OAuth callback controller for Zitadel authentication
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :verify_authenticity_token, only: [:zitadel, :failure]

    # Zitadel OAuth callback
    def zitadel
      auth_data = request.env['omniauth.auth']

      # Validate the OAuth response
      unless validate_oauth_response(auth_data)
        redirect_to new_user_session_path, alert: 'Invalid authentication response from Zitadel.'
        return
      end

      @user = User.from_omniauth(auth_data)

      if @user.persisted?
        # Additional session validation
        unless @user.session_valid?
          redirect_to new_user_session_path, alert: 'Session has expired. Please sign in again.'
          return
        end

        # Store OAuth token info in Rails session for future API calls
        store_oauth_session(auth_data)

        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: 'Zitadel') if is_navigational_format?
      else
        session['devise.zitadel_data'] = auth_data.except(:extra)
        redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
      end
    end

    private

    # Validate OAuth response data
    def validate_oauth_response(auth)
      return false if auth.blank?
      return false if auth.uid.blank?
      return false if auth.info&.email.blank?

      # Validate token expiration if present
      if auth.credentials&.expires_at
        expires_at = Time.at(auth.credentials.expires_at)
        return false if expires_at < Time.current
      end

      true
    end

    # Store OAuth session data for API calls
    def store_oauth_session(auth)
      session[:zitadel_access_token] = auth.credentials&.token
      session[:zitadel_refresh_token] = auth.credentials&.refresh_token
      session[:zitadel_expires_at] = auth.credentials&.expires_at
    end

    # OAuth failure callback
    def failure
      Rails.logger.error "OAuth authentication failed: #{params[:message]}"
      redirect_to root_path, alert: 'Authentication failed. Please try again.'
    end
  end
end
