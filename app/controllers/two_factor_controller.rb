class TwoFactorController < ApplicationController
  before_action :authenticate_user!

  def show
    # Show current 2FA status
  end

  def new
    # Generate new OTP secret if not already set
    if current_user.otp_secret.blank?
      current_user.otp_secret = User.generate_otp_secret
      current_user.save!
    end

    # Generate QR code
    issuer = "Server Manager"
    label = "#{issuer}:#{current_user.email}"

    provisioning_uri = current_user.otp_provisioning_uri(label, issuer: issuer)
    @qr_code = RQRCode::QRCode.new(provisioning_uri)
  end

  def create
    # Verify OTP code and enable 2FA
    if current_user.validate_and_consume_otp!(params[:otp_code])
      # Generate backup codes
      @backup_codes = current_user.generate_otp_backup_codes!
      current_user.update!(otp_required_for_login: true)

      flash.now[:notice] = "Two-factor authentication enabled successfully!"
      render :backup_codes
    else
      flash.now[:alert] = "Invalid verification code. Please try again."

      # Regenerate QR code for display
      issuer = "Server Manager"
      label = "#{issuer}:#{current_user.email}"
      provisioning_uri = current_user.otp_provisioning_uri(label, issuer: issuer)
      @qr_code = RQRCode::QRCode.new(provisioning_uri)

      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    current_user.disable_two_factor!
    redirect_to two_factor_path, notice: "Two-factor authentication has been disabled"
  end
end
