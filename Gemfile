source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.1"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

# Background Processing
gem "sidekiq", "~> 7.1"
gem "sidekiq-cron", "~> 1.10"
gem "redis", "~> 5.0"
gem "fugit", "~> 1.8"  # Cron expression parsing

# Real-time Features
gem "turbo-rails"
gem "stimulus-rails"

# UI Components & Pagination
gem "view_component", "~> 4.0"
gem "pagy", "~> 6.0"  # Fast pagination

# Notifications (commented out for now - can add later if needed)
# gem "noticed", "~> 2.0"  # In-app notifications

# Salt Integration
gem "httparty", "~> 0.21"  # For Salt API calls
gem "eventmachine", "~> 1.2"  # For Salt event stream
gem "websocket-eventmachine-client"  # WebSocket support

# Monitoring & Metrics
gem "chartkick", "~> 5.0"
gem "groupdate", "~> 6.4"

# Authentication & Authorization
gem "devise", "~> 4.9"
gem "rotp", "~> 6.3"  # TOTP for 2FA
gem "rqrcode", "~> 2.0"  # QR code generation for 2FA
gem "attr_encrypted", "~> 4.0"  # Encrypt sensitive data
gem "pundit", "~> 2.3"
gem "omniauth-oauth2", "~> 1.8"
gem "omniauth-rails_csrf_protection", "~> 1.0"
gem "rack-attack", "~> 6.7"  # Rate limiting and throttling

# Utilities
gem "dotenv-rails"
gem "redcarpet", "~> 3.6"  # Markdown rendering for documentation

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # Testing enhancements
  gem "factory_bot_rails", "~> 6.4"  # Better test data creation
  gem "faker", "~> 3.2"               # Realistic fake data
  gem "webmock", "~> 3.19"            # HTTP request stubbing
  gem "mocha", "~> 2.1"               # Mocking/stubbing
  gem "simplecov", "~> 0.22", require: false  # Code coverage reporting
  gem "shoulda-matchers", "~> 6.0"    # RSpec-style matchers for Minitest
end
