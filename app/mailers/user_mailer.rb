# frozen_string_literal: true

# Mailer for sending emails to users
class UserMailer < ApplicationMailer
  # Send welcome email to new user
  # @param user [User] The newly created user
  # @param temporary_password [String] Optional temporary password if set
  def welcome_email(user, temporary_password = nil)
    @user = user
    @temporary_password = temporary_password
    @login_url = new_user_session_url
    @two_factor_setup_url = two_factor_url

    mail(
      to: user.email,
      subject: "Welcome to #{company_name}"
    )
  end

  # Notify user that their account role has been changed
  # @param user [User] The user whose role changed
  # @param old_role [String] Previous role
  # @param new_role [String] New role
  def role_changed(user, old_role, new_role)
    @user = user
    @old_role = old_role
    @new_role = new_role

    mail(
      to: user.email,
      subject: "Your account role has been updated"
    )
  end

  # Notify user when 2FA is enabled on their account
  # @param user [User] The user
  def two_factor_enabled(user)
    @user = user

    mail(
      to: user.email,
      subject: "Two-Factor Authentication Enabled"
    )
  end

  # Notify user when 2FA is disabled on their account
  # @param user [User] The user
  def two_factor_disabled(user)
    @user = user

    mail(
      to: user.email,
      subject: "Two-Factor Authentication Disabled"
    )
  end

  private

  # Get company name from system settings or use default
  # @return [String] Company name
  def company_name
    SystemSetting.get('company_name') || 'Server Manager'
  rescue
    'Server Manager'
  end
end
