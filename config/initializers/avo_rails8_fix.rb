# Fix for Avo compatibility with Rails 8
# Rails 8 uses Propshaft by default, but we're using Sprockets for Avo compatibility

if Rails.version.to_f >= 8.0 && !Rails.application.config.respond_to?(:assets)
  # Initialize assets configuration for Sprockets compatibility
  Rails.application.config.assets = ActiveSupport::OrderedOptions.new
  Rails.application.config.assets.version = '1.0'
  Rails.application.config.assets.paths = []
  Rails.application.config.assets.precompile = []
  Rails.application.config.assets.prefix = '/assets'
  Rails.application.config.assets.debug = true
  Rails.application.config.assets.compile = true
  Rails.application.config.assets.digest = true
  Rails.application.config.assets.cache_store = :null_store
  Rails.application.config.assets.check_precompiled_asset = true
end