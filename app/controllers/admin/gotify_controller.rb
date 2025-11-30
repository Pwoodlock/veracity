# frozen_string_literal: true

module Admin
  #
  # Admin::GotifyController - Complete Gotify Administration Interface
  #
  # Provides full administrative UI for managing Gotify server:
  # - Dashboard overview with statistics
  # - Application CRUD operations
  # - User management
  # - Message viewing and management
  # - Client token management
  # - Connection settings and testing
  #
  class GotifyController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :init_gotify_service

    # ============================================================================
    # DASHBOARD & OVERVIEW
    # ============================================================================

    def index
      @connection_test = test_connection_internal
      @connected = @connection_test[:success]

      if @connected
        stats = @gotify.statistics
        @total_applications = stats[:total_applications]
        @total_users = stats[:total_users]
        @total_clients = stats[:total_clients]
        @total_messages = stats[:total_messages]

        # Get recent messages
        messages_result = @gotify.list_all_messages(limit: 10)
        @recent_messages = messages_result[:messages] || []

        # Get applications for quick reference
        @applications = @gotify.list_applications
      else
        @total_applications = 0
        @total_users = 0
        @total_clients = 0
        @total_messages = 0
        @recent_messages = []
        @applications = []
      end

      @gotify_url = SystemSetting.get("gotify_admin_url", "http://localhost:8080")
      @gotify_enabled = SystemSetting.get("gotify_enabled", false)
    end

    # ============================================================================
    # APPLICATION MANAGEMENT
    # ============================================================================

    def applications
      @applications = @gotify.list_applications
      @message_counts = @gotify.application_message_counts
    end

    def create_application
      result = @gotify.create_application(
        name: params[:name],
        description: params[:description] || "",
        default_priority: params[:default_priority]&.to_i || 5
      )

      if result[:success]
        flash[:success] = result[:message]
        redirect_to admin_gotify_applications_path
      else
        flash[:error] = result[:message]
        redirect_to admin_gotify_applications_path
      end
    end

    def update_application
      result = @gotify.update_application(
        app_id: params[:id],
        name: params[:name],
        description: params[:description],
        default_priority: params[:default_priority]&.to_i
      )

      if result[:success]
        flash[:success] = result[:message]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_applications_path
    end

    def delete_application
      result = @gotify.delete_application(params[:id])

      if result[:success]
        flash[:success] = result[:message]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_applications_path
    end

    # ============================================================================
    # USER MANAGEMENT
    # ============================================================================

    def users
      @users = @gotify.list_users
    end

    def create_user
      result = @gotify.create_user(
        name: params[:name],
        password: params[:password],
        admin: params[:admin] == "1" || params[:admin] == "true"
      )

      if result[:success]
        flash[:success] = result[:message]
        redirect_to admin_gotify_users_path
      else
        flash[:error] = result[:message]
        redirect_to admin_gotify_users_path
      end
    end

    def update_user
      update_params = {
        user_id: params[:id]
      }
      update_params[:name] = params[:name] if params[:name].present?
      update_params[:password] = params[:password] if params[:password].present?
      update_params[:admin] = params[:admin] == '1' || params[:admin] == 'true' unless params[:admin].nil?

      result = @gotify.update_user(**update_params)

      if result[:success]
        flash[:success] = result[:message]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_users_path
    end

    def delete_user
      result = @gotify.delete_user(params[:id])

      if result[:success]
        flash[:success] = result[:message]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_users_path
    end

    # ============================================================================
    # MESSAGE MANAGEMENT
    # ============================================================================

    def messages
      @limit = (params[:limit] || 50).to_i.clamp(1, 200)
      @app_filter = params[:app_id]

      if @app_filter.present?
        result = @gotify.list_app_messages(@app_filter, limit: @limit)
        @application = @gotify.get_application(@app_filter)
      else
        result = @gotify.list_all_messages(limit: @limit)
        @application = nil
      end

      @messages = result[:messages] || []
      @applications = @gotify.list_applications
    end

    def send_message
      # Get application token (not admin credentials)
      app = @gotify.get_application(params[:app_id])

      unless app
        flash[:error] = "Application not found"
        redirect_to admin_gotify_messages_path
        return
      end

      result = @gotify.send_message(
        app_token: app["token"],
        title: params[:title],
        message: params[:message],
        priority: params[:priority]&.to_i || 5
      )

      if result[:success]
        flash[:success] = result[:message]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_messages_path
    end

    def delete_message
      result = @gotify.delete_message(params[:id])

      if result[:success]
        flash[:success] = result[:message]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_messages_path
    end

    def delete_app_messages
      result = @gotify.delete_app_messages(params[:id])

      if result[:success]
        flash[:success] = result[:message]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_messages_path
    end

    # ============================================================================
    # CLIENT TOKEN MANAGEMENT
    # ============================================================================

    def clients
      @clients = @gotify.list_clients
    end

    def create_client
      result = @gotify.create_client(name: params[:name])

      if result[:success]
        flash[:success] = result[:message]
        # Store the token temporarily in flash for user to copy
        flash[:client_token] = result[:client][:token]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_clients_path
    end

    def revoke_client
      result = @gotify.delete_client(params[:id])

      if result[:success]
        flash[:success] = result[:message]
      else
        flash[:error] = result[:message]
      end

      redirect_to admin_gotify_clients_path
    end

    # ============================================================================
    # SETTINGS & CONFIGURATION
    # ============================================================================

    def settings
      # Get settings with source tracking (ENV vs DB)
      @gotify_url = SystemSetting.get_with_source("gotify_admin_url", "http://localhost:8080")
      @gotify_username = SystemSetting.get_with_source("gotify_admin_username", "admin")
      @gotify_password = SystemSetting.get_with_source("gotify_admin_password", "admin")
      @gotify_enabled = SystemSetting.get_with_source("gotify_enabled", false)
      @gotify_ssl_verify = SystemSetting.get_with_source("gotify_ssl_verify", true)

      # Test current connection
      @connection_test = test_connection_internal
    end

    def update_settings
      begin
        # Check if any ENV overrides are active
        env_overrides = []
        env_overrides << "URL" if SystemSetting.env_override?("gotify_admin_url")
        env_overrides << "Username" if SystemSetting.env_override?("gotify_admin_username")
        env_overrides << "Password" if SystemSetting.env_override?("gotify_admin_password")
        env_overrides << "Enabled" if SystemSetting.env_override?("gotify_enabled")
        env_overrides << "SSL Verification" if SystemSetting.env_override?("gotify_ssl_verify")

        if env_overrides.any?
          flash[:warning] = "Some settings (#{env_overrides.join(', ')}) are controlled by environment variables and cannot be changed via UI."
          redirect_to admin_gotify_settings_path
          return
        end

        # Update URL
        if params[:gotify_url].present?
          url = sanitize_url(params[:gotify_url])
          SystemSetting.set('gotify_admin_url', url, 'string')
        end

        # Update credentials
        if params[:gotify_username].present?
          SystemSetting.set('gotify_admin_username', params[:gotify_username], 'string')
        end

        if params[:gotify_password].present?
          SystemSetting.set('gotify_admin_password', params[:gotify_password], 'string')
        end

        # Update enabled status
        enabled = params[:gotify_enabled] == '1' || params[:gotify_enabled] == 'true'
        SystemSetting.set('gotify_enabled', enabled, 'boolean')

        # Update SSL verification
        ssl_verify = params[:gotify_ssl_verify] == '1' || params[:gotify_ssl_verify] == 'true'
        SystemSetting.set('gotify_ssl_verify', ssl_verify, 'boolean')

        # Test connection with new settings
        @gotify = GotifyApiService.new
        test_result = test_connection_internal

        unless test_result[:success]
          flash[:warning] = "Settings saved, but connection test failed: #{test_result[:message]}"
          redirect_to admin_gotify_settings_path
          return
        end

        flash[:success] = 'Gotify settings updated successfully and connection verified'
        redirect_to admin_gotify_settings_path
      rescue StandardError => e
        Rails.logger.error "Failed to update Gotify settings: #{e.message}"
        flash[:error] = "Failed to update settings: #{e.message}"
        redirect_to admin_gotify_settings_path
      end
    end

    def test_connection
      result = test_connection_internal

      respond_to do |format|
        format.json do
          if result[:success]
            render json: {
              success: true,
              message: result[:message],
              details: result
            }
          else
            render json: {
              success: false,
              message: result[:message]
            }, status: :unprocessable_entity
          end
        end
      end
    end

    private

    def init_gotify_service
      @gotify = GotifyApiService.new
    end

    def authorize_admin!
      unless current_user.admin?
        flash[:error] = 'You are not authorized to access this page'
        redirect_to root_path
      end
    end

    def test_connection_internal
      health = @gotify.health_check

      if health[:success]
        # Also get version info and current user to verify full access
        version = @gotify.version_info
        current_user = @gotify.get_current_user

        if current_user && current_user['admin']
          {
            success: true,
            message: 'Connected successfully with admin privileges',
            version: version&.dig('version'),
            build_date: version&.dig('buildDate'),
            health: health
          }
        elsif current_user
          {
            success: false,
            message: 'Connected but user does not have admin privileges'
          }
        else
          {
            success: false,
            message: 'Health check passed but authentication failed'
          }
        end
      else
        health
      end
    rescue StandardError => e
      {
        success: false,
        message: "Connection test failed: #{e.message}"
      }
    end

    def sanitize_url(url)
      # Remove trailing slash
      url = url.strip.chomp('/')

      # Add http:// if no protocol specified
      url = "http://#{url}" unless url.start_with?('http://', 'https://')

      # Validate URL format
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        raise ArgumentError, 'Invalid URL format'
      end

      url
    rescue URI::InvalidURIError
      raise ArgumentError, 'Invalid URL format'
    end
  end
end
