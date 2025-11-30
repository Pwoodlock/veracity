# frozen_string_literal: true

# OmniAuth configuration for Zitadel OAuth2/OIDC with PKCE
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :oauth2, 'zitadel',
    client_id: ENV['ZITADEL_CLIENT_ID'],
    client_secret: nil,
    name: 'zitadel',
    scope: 'openid profile email',
    client_options: {
      site: ENV['ZITADEL_ISSUER'],
      authorize_url: "#{ENV['ZITADEL_ISSUER']}/oauth/v2/authorize",
      token_url: "#{ENV['ZITADEL_ISSUER']}/oauth/v2/token",
      user_info_url: "#{ENV['ZITADEL_ISSUER']}/oidc/v1/userinfo"
    },
    authorize_params: {
      response_type: 'code',
      code_challenge_method: 'S256'
    },
    token_params: {
      grant_type: 'authorization_code'
    },
    pkce: true
end

# Configure OmniAuth to use Rails CSRF protection
OmniAuth.config.allowed_request_methods = [:get, :post]
OmniAuth.config.silence_get_warning = true
