# frozen_string_literal: true

# Rack::Attack Configuration
# Protects against brute force attacks and abuse
class Rack::Attack
  ### Configure Cache ###
  # Use Rails.cache (Redis in production) for storing throttle data
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Throttle Configuration ###

  # CRITICAL: Throttle 2FA verification attempts
  # Limit: 5 attempts per IP per minute
  # Prevents brute force attacks on 6-digit OTP codes
  throttle('2fa_verification/ip', limit: 5, period: 60.seconds) do |req|
    if req.path == '/users/verify_otp' && req.post?
      req.ip
    end
  end

  # CRITICAL: Throttle login attempts by IP
  # Limit: 5 attempts per IP per 5 minutes
  throttle('login/ip', limit: 5, period: 5.minutes) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.ip
    end
  end

  # CRITICAL: Throttle login attempts by email (distributed attacks)
  # Limit: 5 attempts per email per 5 minutes
  # Protects against attackers using multiple IPs to target one account
  throttle('login/email', limit: 5, period: 5.minutes) do |req|
    if req.path == '/users/sign_in' && req.post?
      # Safely extract email from params
      req.params.dig('user', 'email').to_s.downcase.presence
    end
  end

  # HIGH: Throttle password reset requests
  # Limit: 3 attempts per IP per 5 minutes
  throttle('password_reset/ip', limit: 3, period: 5.minutes) do |req|
    if req.path == '/users/password' && req.post?
      req.ip
    end
  end

  # MEDIUM: Throttle Salt CLI command execution
  # Limit: 30 commands per user per minute
  # Prevents abuse of command execution interface
  throttle('salt_cli/user', limit: 30, period: 1.minute) do |req|
    if req.path == '/salt_cli/execute' && req.post?
      # Use user_id from session cookie
      req.env['rack.session']&.dig('warden.user.user.key')&.first&.first
    end
  end

  # MEDIUM: Throttle onboarding key acceptance
  # Limit: 10 key operations per IP per minute
  throttle('onboarding/ip', limit: 10, period: 1.minute) do |req|
    if req.path =~ %r{^/onboarding/(accept_key|reject_key)} && req.post?
      req.ip
    end
  end

  # LOW: General API rate limiting for authenticated users
  # Limit: 300 requests per user per 5 minutes (1 req/second average)
  throttle('api/user', limit: 300, period: 5.minutes) do |req|
    # Skip static assets and health checks
    unless req.path.start_with?('/assets', '/up')
      req.env['rack.session']&.dig('warden.user.user.key')&.first&.first
    end
  end

  ### Custom Throttle Response ###
  self.throttled_responder = lambda do |env|
    match_data = env['rack.attack.match_data']
    now = match_data[:epoch_time]

    headers = {
      'Content-Type' => 'text/html',
      'Retry-After' => (match_data[:period] - (now % match_data[:period])).to_s,
      'X-RateLimit-Limit' => match_data[:limit].to_s,
      'X-RateLimit-Remaining' => '0',
      'X-RateLimit-Reset' => (now + (match_data[:period] - (now % match_data[:period]))).to_s
    }

    # Return user-friendly HTML error page
    html_body = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Too Many Requests</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                 padding: 50px; text-align: center; background: #f5f5f5; }
          .container { max-width: 600px; margin: 0 auto; background: white;
                       padding: 40px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
          h1 { color: #d32f2f; margin-bottom: 20px; }
          p { color: #666; line-height: 1.6; }
          .retry { color: #1976d2; font-weight: bold; }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>⚠️ Too Many Requests</h1>
          <p>You have exceeded the rate limit for this action.</p>
          <p>Please wait <span class="retry">#{(match_data[:period] - (now % match_data[:period])).to_i} seconds</span> before trying again.</p>
          <p><small>If you believe this is an error, please contact your administrator.</small></p>
        </div>
      </body>
      </html>
    HTML

    [429, headers, [html_body]]
  end

  ### Blocklist & Safelist ###

  # Always allow requests from localhost (for development and health checks)
  safelist('allow-localhost') do |req|
    req.ip == '127.0.0.1' || req.ip == '::1'
  end

  # Safelist specific IPs if needed (add your office/VPN IPs here)
  # safelist('allow-trusted-ips') do |req|
  #   %w[1.2.3.4 5.6.7.8].include?(req.ip)
  # end

  ### Logging ###
  ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
    req = payload[:request]

    if req.env['rack.attack.matched']
      Rails.logger.warn "[Rack::Attack] Throttled: #{req.env['rack.attack.matched']} - IP: #{req.ip} - Path: #{req.path}"
    end
  end
end

# Enable Rack::Attack middleware
Rails.application.config.middleware.use Rack::Attack
