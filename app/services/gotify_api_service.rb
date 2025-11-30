# frozen_string_literal: true

#
# GotifyApiService - Complete Gotify REST API Integration
#
# Provides full administrative access to Gotify server for:
# - Application management (create, list, update, delete)
# - User management (create, list, update, delete, password changes)
# - Client token management (list, delete)
# - Message management (send, list, delete)
# - Statistics and health checks
#
# Usage:
#   service = GotifyApiService.new
#   service.list_applications
#   service.create_application(name: "MyApp", description: "My Application")
#   service.send_message(app_token: "xyz", title: "Test", message: "Hello", priority: 5)
#

class GotifyApiService
  require 'net/http'
  require 'json'
  require 'uri'

  class GotifyApiError < StandardError; end
  class AuthenticationError < GotifyApiError; end
  class NotFoundError < GotifyApiError; end
  class ValidationError < GotifyApiError; end

  attr_reader :base_url, :username, :password, :ssl_verify

  def initialize
    # ENV variables take precedence over database settings
    @base_url = ENV['GOTIFY_ADMIN_URL'] || ENV['GOTIFY_URL'] || SystemSetting.get('gotify_admin_url', 'http://localhost:8080')
    @username = ENV['GOTIFY_ADMIN_USERNAME'] || SystemSetting.get('gotify_admin_username', 'admin')
    @password = ENV['GOTIFY_ADMIN_PASSWORD'] || SystemSetting.get('gotify_admin_password', 'admin')
    @ssl_verify = ENV['GOTIFY_SSL_VERIFY'] ? ENV['GOTIFY_SSL_VERIFY'] == 'true' : SystemSetting.get('gotify_ssl_verify', true)

    # Remove trailing slash from URL
    @base_url = @base_url.chomp('/')

    # Log warning if using insecure defaults
    if Rails.env.production? && @password == 'admin'
      Rails.logger.warn "[SECURITY] GotifyApiService using default password!"
    end
  end

  # ============================================================================
  # HEALTH CHECK
  # ============================================================================

  # Check if Gotify server is accessible and responding
  # Returns: { success: true/false, message: String, version: String }
  def health_check
    response = get_request('/health')

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      {
        success: true,
        message: 'Gotify server is healthy',
        health: data['health'],
        database: data['database']
      }
    else
      { success: false, message: "Health check failed: #{response.code} #{response.message}" }
    end
  rescue StandardError => e
    { success: false, message: "Connection failed: #{e.message}" }
  end

  # Get server version information
  def version_info
    response = get_request('/version')
    JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
  rescue StandardError => e
    Rails.logger.error("Failed to get version info: #{e.message}")
    nil
  end

  # ============================================================================
  # APPLICATION MANAGEMENT
  # ============================================================================

  # List all applications
  # Returns: Array of application hashes
  def list_applications
    response = get_request('/application')
    return [] unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Failed to list applications: #{e.message}")
    []
  end

  # Get single application by ID
  def get_application(app_id)
    applications = list_applications
    applications.find { |app| app['id'] == app_id.to_i }
  end

  # Create new application
  # Parameters:
  #   name: String (required) - Application name
  #   description: String (optional) - Application description
  #   default_priority: Integer (optional, default: 0) - Default message priority (0-10)
  # Returns: Hash with application details including token
  def create_application(name:, description: '', default_priority: 0)
    payload = {
      name: name,
      description: description,
      defaultPriority: default_priority
    }

    response = post_request('/application', payload)

    if response.is_a?(Net::HTTPSuccess)
      app = JSON.parse(response.body)
      {
        success: true,
        application: app,
        message: "Application '#{name}' created successfully"
      }
    else
      error_message = parse_error_message(response)
      {
        success: false,
        message: "Failed to create application: #{error_message}"
      }
    end
  rescue StandardError => e
    Rails.logger.error("Error creating application: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Update existing application
  def update_application(app_id:, name: nil, description: nil, default_priority: nil)
    # Get current application data
    current_app = get_application(app_id)
    return { success: false, message: 'Application not found' } unless current_app

    # Build update payload (only include changed fields)
    payload = {
      name: name || current_app['name'],
      description: description || current_app['description'],
      defaultPriority: default_priority || current_app['defaultPriority']
    }

    response = put_request("/application/#{app_id}", payload)

    if response.is_a?(Net::HTTPSuccess)
      {
        success: true,
        application: JSON.parse(response.body),
        message: 'Application updated successfully'
      }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Update failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error updating application: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Delete application
  def delete_application(app_id)
    response = delete_request("/application/#{app_id}")

    if response.is_a?(Net::HTTPSuccess)
      { success: true, message: 'Application deleted successfully' }
    elsif response.code == '404'
      { success: false, message: 'Application not found' }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Delete failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error deleting application: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Upload application image
  def upload_application_image(app_id, image_path)
    # This would require multipart/form-data upload
    # Implementation depends on requirements
    raise NotImplementedError, 'Image upload not yet implemented'
  end

  # ============================================================================
  # MESSAGE MANAGEMENT
  # ============================================================================

  # Send message to application
  # Parameters:
  #   app_token: String (required) - Application token (not client token!)
  #   title: String (optional)
  #   message: String (required)
  #   priority: Integer (optional, 0-10, default: 5)
  #   extras: Hash (optional) - Additional data for clients
  def send_message(app_token:, message:, title: nil, priority: 5, extras: nil)
    payload = {
      message: message,
      priority: priority.to_i.clamp(0, 10)
    }
    payload[:title] = title if title.present?
    payload[:extras] = extras if extras.present?

    # Use app token for authentication (not admin credentials)
    response = post_request('/message', payload, token: app_token)

    if response.is_a?(Net::HTTPSuccess)
      {
        success: true,
        message_data: JSON.parse(response.body),
        message: 'Message sent successfully'
      }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Failed to send message: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error sending message: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # List all messages across all applications
  # Parameters:
  #   limit: Integer (optional) - Max number of messages to retrieve
  #   since: Integer (optional) - Message ID to start from
  def list_all_messages(limit: 100, since: nil)
    url = '/message'
    params = []
    params << "limit=#{limit}" if limit
    params << "since=#{since}" if since
    url += "?#{params.join('&')}" if params.any?

    response = get_request(url)
    return { success: false, messages: [] } unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    {
      success: true,
      messages: data['messages'] || [],
      paging: data['paging']
    }
  rescue StandardError => e
    Rails.logger.error("Failed to list messages: #{e.message}")
    { success: false, messages: [] }
  end

  # List messages for specific application
  def list_app_messages(app_id, limit: 100, since: nil)
    url = "/application/#{app_id}/message"
    params = []
    params << "limit=#{limit}" if limit
    params << "since=#{since}" if since
    url += "?#{params.join('&')}" if params.any?

    response = get_request(url)
    return { success: false, messages: [] } unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    {
      success: true,
      messages: data['messages'] || [],
      paging: data['paging']
    }
  rescue StandardError => e
    Rails.logger.error("Failed to list app messages: #{e.message}")
    { success: false, messages: [] }
  end

  # Delete single message
  def delete_message(message_id)
    response = delete_request("/message/#{message_id}")

    if response.is_a?(Net::HTTPSuccess)
      { success: true, message: 'Message deleted successfully' }
    elsif response.code == '404'
      { success: false, message: 'Message not found' }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Delete failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error deleting message: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Delete all messages for application
  def delete_app_messages(app_id)
    response = delete_request("/application/#{app_id}/message")

    if response.is_a?(Net::HTTPSuccess)
      { success: true, message: 'All messages deleted successfully' }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Bulk delete failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error deleting app messages: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # ============================================================================
  # USER MANAGEMENT
  # ============================================================================

  # List all users
  def list_users
    response = get_request('/user')
    return [] unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Failed to list users: #{e.message}")
    []
  end

  # Get single user by ID
  def get_user(user_id)
    users = list_users
    users.find { |user| user['id'] == user_id.to_i }
  end

  # Get current authenticated user
  def get_current_user
    response = get_request('/current/user')
    return nil unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Failed to get current user: #{e.message}")
    nil
  end

  # Create new user
  # Parameters:
  #   name: String (required) - Username
  #   password: String (required) - Password
  #   admin: Boolean (optional, default: false) - Admin privileges
  def create_user(name:, password:, admin: false)
    payload = {
      name: name,
      pass: password,
      admin: admin
    }

    response = post_request('/user', payload)

    if response.is_a?(Net::HTTPSuccess)
      user = JSON.parse(response.body)
      {
        success: true,
        user: user,
        message: "User '#{name}' created successfully"
      }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Failed to create user: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error creating user: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Update existing user
  def update_user(user_id:, name: nil, password: nil, admin: nil)
    # Get current user data
    current_user = get_user(user_id)
    return { success: false, message: 'User not found' } unless current_user

    # Build update payload
    payload = {
      name: name || current_user['name'],
      admin: admin.nil? ? current_user['admin'] : admin
    }
    payload[:pass] = password if password.present?

    response = put_request("/user/#{user_id}", payload)

    if response.is_a?(Net::HTTPSuccess)
      {
        success: true,
        user: JSON.parse(response.body),
        message: 'User updated successfully'
      }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Update failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error updating user: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Delete user
  def delete_user(user_id)
    response = delete_request("/user/#{user_id}")

    if response.is_a?(Net::HTTPSuccess)
      { success: true, message: 'User deleted successfully' }
    elsif response.code == '404'
      { success: false, message: 'User not found' }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Delete failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error deleting user: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Change user password (current user)
  def change_current_user_password(old_password:, new_password:)
    payload = {
      pass: new_password
    }

    response = post_request('/current/user/password', payload)

    if response.is_a?(Net::HTTPSuccess)
      { success: true, message: 'Password changed successfully' }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Password change failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error changing password: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # ============================================================================
  # CLIENT TOKEN MANAGEMENT
  # ============================================================================

  # List all client tokens
  def list_clients
    response = get_request('/client')
    return [] unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.error("Failed to list clients: #{e.message}")
    []
  end

  # Create new client token
  def create_client(name:)
    payload = { name: name }

    response = post_request('/client', payload)

    if response.is_a?(Net::HTTPSuccess)
      client = JSON.parse(response.body)
      {
        success: true,
        client: client,
        message: "Client '#{name}' created successfully"
      }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Failed to create client: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error creating client: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Update client
  def update_client(client_id:, name:)
    payload = { name: name }

    response = put_request("/client/#{client_id}", payload)

    if response.is_a?(Net::HTTPSuccess)
      {
        success: true,
        client: JSON.parse(response.body),
        message: 'Client updated successfully'
      }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Update failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error updating client: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # Delete (revoke) client token
  def delete_client(client_id)
    response = delete_request("/client/#{client_id}")

    if response.is_a?(Net::HTTPSuccess)
      { success: true, message: 'Client token revoked successfully' }
    elsif response.code == '404'
      { success: false, message: 'Client not found' }
    else
      error_message = parse_error_message(response)
      { success: false, message: "Revoke failed: #{error_message}" }
    end
  rescue StandardError => e
    Rails.logger.error("Error revoking client: #{e.message}")
    { success: false, message: "Error: #{e.message}" }
  end

  # ============================================================================
  # STATISTICS
  # ============================================================================

  # Get statistics summary
  def statistics
    apps = list_applications
    users = list_users
    clients = list_clients
    messages_result = list_all_messages(limit: 1)

    {
      total_applications: apps.length,
      total_users: users.length,
      total_clients: clients.length,
      total_messages: messages_result[:paging]&.dig('size') || 0,
      applications: apps,
      users: users,
      clients: clients
    }
  rescue StandardError => e
    Rails.logger.error("Failed to get statistics: #{e.message}")
    {
      total_applications: 0,
      total_users: 0,
      total_clients: 0,
      total_messages: 0,
      error: e.message
    }
  end

  # Get per-application message counts
  def application_message_counts
    apps = list_applications
    counts = {}

    apps.each do |app|
      result = list_app_messages(app['id'], limit: 1)
      counts[app['id']] = {
        name: app['name'],
        count: result[:paging]&.dig('size') || 0
      }
    end

    counts
  rescue StandardError => e
    Rails.logger.error("Failed to get message counts: #{e.message}")
    {}
  end

  private

  # ============================================================================
  # HTTP REQUEST METHODS
  # ============================================================================

  def get_request(path, token: nil)
    uri = URI("#{@base_url}#{path}")
    http = build_http(uri)
    request = Net::HTTP::Get.new(uri)
    add_auth_headers(request, token)
    http.request(request)
  end

  def post_request(path, payload, token: nil)
    uri = URI("#{@base_url}#{path}")
    http = build_http(uri)
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    add_auth_headers(request, token)
    request.body = payload.to_json
    http.request(request)
  end

  def put_request(path, payload, token: nil)
    uri = URI("#{@base_url}#{path}")
    http = build_http(uri)
    request = Net::HTTP::Put.new(uri)
    request['Content-Type'] = 'application/json'
    add_auth_headers(request, token)
    request.body = payload.to_json
    http.request(request)
  end

  def delete_request(path, token: nil)
    uri = URI("#{@base_url}#{path}")
    http = build_http(uri)
    request = Net::HTTP::Delete.new(uri)
    add_auth_headers(request, token)
    http.request(request)
  end

  def build_http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')

    if http.use_ssl?
      # Respect SSL verification setting
      if @ssl_verify
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        Rails.logger.debug "[Gotify] SSL verification enabled"
      else
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        Rails.logger.warn "[Gotify] SSL verification DISABLED - self-signed cert mode"
      end
    end

    http.open_timeout = 5
    http.read_timeout = 10
    http
  end

  def add_auth_headers(request, token = nil)
    if token.present?
      # Use provided token (for app-specific operations)
      request['X-Gotify-Key'] = token
    else
      # Use basic auth with admin credentials
      request.basic_auth(@username, @password)
    end
  end

  def parse_error_message(response)
    return response.message unless response.body

    begin
      error_data = JSON.parse(response.body)
      error_data['error'] || error_data['errorDescription'] || response.message
    rescue JSON::ParserError
      response.body
    end
  end
end
