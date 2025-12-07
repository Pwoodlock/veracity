# frozen_string_literal: true

# Redis configuration for caching and background jobs
#
# REDIS_URL can be set via environment variable, defaults to localhost
REDIS_URL = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')

# Configure Redis instance for application caching
begin
  $redis = Redis.new(url: REDIS_URL, timeout: 5, reconnect_attempts: 3)

  # Test connection on startup
  $redis.ping
  Rails.logger.info "Redis connected successfully at #{REDIS_URL}"
rescue Redis::CannotConnectError => e
  Rails.logger.warn "Redis connection failed: #{e.message}. Caching will be disabled."
  $redis = nil
rescue StandardError => e
  Rails.logger.error "Redis initialization error: #{e.message}"
  $redis = nil
end

# Redis namespace helper for organized cache keys
module RedisCache
  class << self
    # Cache key prefix for this application
    PREFIX = 'server_manager'

    # Build namespaced cache key
    def key(namespace, identifier)
      "#{PREFIX}:#{namespace}:#{identifier}"
    end

    # Get cached value
    def get(namespace, identifier)
      return nil unless $redis

      key_name = key(namespace, identifier)
      value = $redis.get(key_name)
      value ? JSON.parse(value) : nil
    rescue StandardError => e
      Rails.logger.error "Redis GET error: #{e.message}"
      nil
    end

    # Set cached value with optional TTL (time to live in seconds)
    def set(namespace, identifier, value, ttl: 300)
      return false unless $redis

      key_name = key(namespace, identifier)
      $redis.setex(key_name, ttl, value.to_json)
      true
    rescue StandardError => e
      Rails.logger.error "Redis SET error: #{e.message}"
      false
    end

    # Delete cached value
    def del(namespace, identifier)
      return false unless $redis

      key_name = key(namespace, identifier)
      $redis.del(key_name)
      true
    rescue StandardError => e
      Rails.logger.error "Redis DEL error: #{e.message}"
      false
    end

    # Check if Redis is available
    def available?
      !$redis.nil?
    end

    # Clear all cached values for a namespace
    def clear_namespace(namespace)
      return false unless $redis

      pattern = "#{PREFIX}:#{namespace}:*"
      keys = $redis.keys(pattern)
      $redis.del(*keys) if keys.any?
      true
    rescue StandardError => e
      Rails.logger.error "Redis CLEAR error: #{e.message}"
      false
    end
  end
end
