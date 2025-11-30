# frozen_string_literal: true

module Settings
  # Controller for managing email/SMTP configuration
  class EmailController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    # GET /settings/email
    def index
      @smtp_config = current_smtp_config
      @mailer_config = current_mailer_config
    end

    # POST /settings/email/update
    def update
      smtp_params = email_params[:smtp] || {}
      mailer_params = email_params[:mailer] || {}

      # Save SMTP settings
      SystemSetting.set('smtp_address', smtp_params[:address])
      SystemSetting.set('smtp_port', smtp_params[:port])
      SystemSetting.set('smtp_username', smtp_params[:username])
      SystemSetting.set('smtp_password', smtp_params[:password]) if smtp_params[:password].present?
      SystemSetting.set('smtp_authentication', smtp_params[:authentication])
      SystemSetting.set('smtp_enable_ssl', smtp_params[:enable_ssl])
      SystemSetting.set('smtp_domain', smtp_params[:domain])

      # Save mailer settings
      SystemSetting.set('mailer_from', mailer_params[:from])
      SystemSetting.set('mailer_host', mailer_params[:host])

      # Reload ActionMailer configuration
      reload_mailer_config!

      redirect_to settings_email_path, notice: 'Email settings updated successfully'
    rescue StandardError => e
      redirect_to settings_email_path, alert: "Failed to update email settings: #{e.message}"
    end

    # POST /settings/email/test
    def test_connection
      begin
        # Reload configuration from database before testing
        reload_mailer_config!

        # Try to send a test email
        test_email = params[:test_email] || current_user.email

        UserMailer.with(test: true).welcome_email(
          current_user,
          nil
        ).deliver_now

        render json: {
          success: true,
          message: "Test email sent successfully to #{test_email}"
        }
      rescue StandardError => e
        Rails.logger.error "Email test failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        render json: {
          success: false,
          message: "Email test failed: #{e.message}",
          error: e.class.name
        }, status: :unprocessable_entity
      end
    end

    # POST /settings/email/send_test
    def send_test
      # Reload configuration from database before testing
      reload_mailer_config!

      recipient = params[:recipient] || current_user.email

      UserMailer.welcome_email(current_user, nil).deliver_now

      render json: {
        success: true,
        message: "Test email sent to #{recipient}"
      }
    rescue StandardError => e
      render json: {
        success: false,
        message: "Failed to send test email: #{e.message}"
      }, status: :unprocessable_entity
    end

    # POST /settings/email/reset
    def reset
      # Clear all email settings (will fall back to ENV variables)
      SystemSetting.where(key: %w[
        smtp_address smtp_port smtp_username smtp_password
        smtp_authentication smtp_enable_ssl smtp_domain
        mailer_from mailer_host
      ]).delete_all

      reload_mailer_config!

      redirect_to settings_email_path, notice: 'Email settings reset to environment defaults'
    end

    private

    def require_admin!
      redirect_to root_path, alert: 'Access denied. Admin privileges required.' unless current_user.admin?
    end

    def email_params
      params.permit(
        smtp: [:address, :port, :username, :password, :authentication, :enable_ssl, :domain],
        mailer: [:from, :host]
      )
    end

    def current_smtp_config
      {
        address: SystemSetting.get('smtp_address') || ENV['SMTP2GO_USERNAME'] ? 'mail.smtp2go.com' : '',
        port: SystemSetting.get('smtp_port') || '587',
        username: SystemSetting.get('smtp_username') || ENV['SMTP2GO_USERNAME'] || '',
        password: SystemSetting.get('smtp_password') || ENV['SMTP2GO_PASSWORD'] || '',
        authentication: SystemSetting.get('smtp_authentication') || 'plain',
        enable_ssl: SystemSetting.get('smtp_enable_ssl') || 'false',
        domain: SystemSetting.get('smtp_domain') || ENV.fetch('MAILER_HOST', 'example.com')
      }
    end

    def current_mailer_config
      {
        from: SystemSetting.get('mailer_from') || ENV.fetch('MAILER_FROM', 'noreply@example.com'),
        host: SystemSetting.get('mailer_host') || ENV.fetch('MAILER_HOST', 'example.com')
      }
    end

    def reload_mailer_config!
      # Dynamically update ActionMailer settings
      port = (SystemSetting.get('smtp_port') || '587').to_i
      enable_ssl = SystemSetting.get('smtp_enable_ssl') == 'true'

      smtp_config = {
        address: SystemSetting.get('smtp_address') || 'mail.smtp2go.com',
        port: port,
        user_name: SystemSetting.get('smtp_username') || ENV['SMTP2GO_USERNAME'],
        password: SystemSetting.get('smtp_password') || ENV['SMTP2GO_PASSWORD'],
        authentication: (SystemSetting.get('smtp_authentication') || 'plain').to_sym,
        domain: SystemSetting.get('smtp_domain') || ENV.fetch('MAILER_HOST', 'example.com')
      }

      # Use SSL for port 465, STARTTLS for other ports (587, 2525, etc)
      if port == 465 && enable_ssl
        smtp_config[:ssl] = true
        smtp_config[:tls] = true
      else
        smtp_config[:enable_starttls_auto] = true
      end

      ActionMailer::Base.smtp_settings = smtp_config

      # Update default URL options
      ActionMailer::Base.default_url_options[:host] = SystemSetting.get('mailer_host') || ENV.fetch('MAILER_HOST', 'example.com')

      # Update Devise mailer sender
      Devise.mailer_sender = SystemSetting.get('mailer_from') || ENV.fetch('MAILER_FROM', 'noreply@example.com')
    end
  end
end
