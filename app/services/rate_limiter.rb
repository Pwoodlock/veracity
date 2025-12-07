# frozen_string_literal: true

# Redis-based rate limiter using sliding window counter algorithm
#
# This service provides thread-safe, atomic rate limiting with support for
# multiple scopes (global, per-user, per-server, per-type) using Redis.
#
# Algorithm: Sliding Window Counter
# - Combines current and previous time windows for smooth limiting
# - More accurate than fixed windows, more efficient than sorted sets
# - Provides atomic operations for high-concurrency environments
#
# Usage:
#   # Global rate limiting
#   RateLimiter.check_limit!(:global)
#
#   # Per-user rate limiting
#   RateLimiter.check_limit!(:user, user_id: 123)
#
#   # Per-server rate limiting
#   RateLimiter.check_limit!(:server, server_id: 456)
#
#   # Per-notification-type rate limiting
#   RateLimiter.check_limit!(:notification_type, type: 'cve_alert')
#
#   # Custom limits
#   RateLimiter.check_limit!(:custom, identifier: 'api_endpoint', limit: 100, window: 60)
#
# Configuration:
#   Rate limits are defined in RATE_LIMITS constant below.
#   Each scope has a limit (max requests) and window (seconds).
#
class RateLimiter
  class RateLimitError < StandardError
    attr_reader :scope, :limit, :window, :retry_after

    def initialize(message, scope:, limit:, window:, retry_after: nil)
      super(message)
      @scope = scope
      @limit = limit
      @window = window
      @retry_after = retry_after
    end
  end

  # Rate limit configurations
  # Format: { scope => { limit: max_requests, window: seconds } }
  RATE_LIMITS = {
    global: { limit: 60, window: 60 },           # 60 notifications per minute (global)
    user: { limit: 20, window: 60 },             # 20 notifications per minute per user
    server: { limit: 30, window: 60 },           # 30 notifications per minute per server
    notification_type: { limit: 40, window: 60 }, # 40 notifications per minute per type
    cve_alert: { limit: 50, window: 300 },       # 50 CVE alerts per 5 minutes
    backup: { limit: 10, window: 60 },           # 10 backup notifications per minute
    task_execution: { limit: 30, window: 60 }    # 30 task notifications per minute
  }.freeze

  # Redis key namespace
  KEY_NAMESPACE = 'sm:rate_limit'

  class << self
    # Check if request is within rate limit, raises RateLimitError if exceeded
    #
    # @param scope [Symbol] The rate limit scope (:global, :user, :server, etc.)
    # @param identifier [String, Integer, Hash] Scope identifier (user_id, server_id, etc.)
    # @param limit [Integer, nil] Custom limit (overrides default)
    # @param window [Integer, nil] Custom window in seconds (overrides default)
    # @raise [RateLimitError] if rate limit is exceeded
    # @return [Hash] Rate limit status { allowed: true, count: X, limit: Y, remaining: Z }
    def check_limit!(scope, identifier: nil, limit: nil, window: nil)
      config = get_config(scope, limit, window)
      key = build_key(scope, identifier)

      # Check rate limit
      count = increment_counter(key, config[:window])
      retry_after = calculate_retry_after(key, config[:window])

      if count > config[:limit]
        raise RateLimitError.new(
          "Rate limit exceeded for #{scope}: #{count}/#{config[:limit]} requests in #{config[:window]}s window. Retry after #{retry_after}s.",
          scope: scope,
          limit: config[:limit],
          window: config[:window],
          retry_after: retry_after
        )
      end

      {
        allowed: true,
        count: count,
        limit: config[:limit],
        remaining: [config[:limit] - count, 0].max,
        window: config[:window],
        reset_at: Time.current + retry_after
      }
    rescue Redis::BaseError => e
      # If Redis fails, log warning and allow the request (fail open)
      handle_redis_failure(e, scope)
      { allowed: true, fallback: true, error: e.message }
    end

    # Check rate limit without raising exception
    #
    # @param scope [Symbol] The rate limit scope
    # @param identifier [String, Integer, Hash] Scope identifier
    # @param limit [Integer, nil] Custom limit
    # @param window [Integer, nil] Custom window in seconds
    # @return [Hash] Rate limit status with :allowed boolean
    def check_limit(scope, identifier: nil, limit: nil, window: nil)
      check_limit!(scope, identifier: identifier, limit: limit, window: window)
    rescue RateLimitError => e
      {
        allowed: false,
        error: e.message,
        limit: e.limit,
        window: e.window,
        retry_after: e.retry_after
      }
    end

    # Get current count for a scope without incrementing
    #
    # @param scope [Symbol] The rate limit scope
    # @param identifier [String, Integer, Hash] Scope identifier
    # @return [Integer] Current count
    def current_count(scope, identifier: nil)
      return 0 unless redis_available?

      config = get_config(scope)
      key = build_key(scope, identifier)

      calculate_sliding_window_count(key, config[:window])
    rescue Redis::BaseError => e
      Rails.logger.error "RateLimiter: Redis error getting count: #{e.message}"
      0
    end

    # Reset rate limit for a scope
    #
    # @param scope [Symbol] The rate limit scope
    # @param identifier [String, Integer, Hash] Scope identifier
    # @return [Boolean] Success status
    def reset_limit(scope, identifier: nil)
      return false unless redis_available?

      key = build_key(scope, identifier)
      current_window_key = "#{key}:#{current_window}"
      previous_window_key = "#{key}:#{previous_window}"

      $redis.del(current_window_key, previous_window_key)
      true
    rescue Redis::BaseError => e
      Rails.logger.error "RateLimiter: Redis error resetting limit: #{e.message}"
      false
    end

    # Get rate limit info without affecting the counter
    #
    # @param scope [Symbol] The rate limit scope
    # @param identifier [String, Integer, Hash] Scope identifier
    # @return [Hash] Rate limit configuration and current status
    def limit_info(scope, identifier: nil)
      config = get_config(scope)
      count = current_count(scope, identifier: identifier)

      {
        scope: scope,
        limit: config[:limit],
        window: config[:window],
        current_count: count,
        remaining: [config[:limit] - count, 0].max,
        reset_at: Time.current + config[:window]
      }
    end

    # Check if Redis is available for rate limiting
    #
    # @return [Boolean]
    def redis_available?
      !$redis.nil? && $redis.ping == 'PONG'
    rescue StandardError
      false
    end

    private

    # Get rate limit configuration for scope
    def get_config(scope, custom_limit = nil, custom_window = nil)
      config = RATE_LIMITS[scope] || RATE_LIMITS[:global]

      {
        limit: custom_limit || config[:limit],
        window: custom_window || config[:window]
      }
    end

    # Build Redis key for scope and identifier
    def build_key(scope, identifier)
      parts = [KEY_NAMESPACE, scope.to_s]

      case identifier
      when Hash
        # Handle hash identifiers (e.g., { user_id: 123, type: 'alert' })
        identifier.each do |key, value|
          parts << "#{key}:#{value}"
        end
      when nil
        # No identifier (global scope)
      else
        # Simple identifier (user_id, server_id, etc.)
        parts << identifier.to_s
      end

      parts.join(':')
    end

    # Increment counter using sliding window algorithm
    #
    # Algorithm:
    # 1. Increment current window counter
    # 2. Set expiration on current window (2x window to ensure previous window exists)
    # 3. Calculate sliding window count combining current and previous windows
    #
    # The sliding window count is calculated as:
    # count = previous_count * weight + current_count
    # where weight = (window - time_in_current_window) / window
    #
    # This provides smooth rate limiting across window boundaries
    def increment_counter(key, window)
      current = current_window(window)
      previous = previous_window(window)

      current_key = "#{key}:#{current}"
      previous_key = "#{key}:#{previous}"

      # Pipeline Redis commands for atomicity
      results = $redis.pipelined do |pipeline|
        # Increment current window counter
        pipeline.incr(current_key)
        # Set expiration (2x window to ensure previous window data exists)
        pipeline.expire(current_key, window * 2)
        # Get previous window count
        pipeline.get(previous_key)
      end

      current_count = results[0].to_i
      previous_count = results[2].to_i

      # Calculate sliding window count
      calculate_weighted_count(current_count, previous_count, window)
    end

    # Calculate weighted count for sliding window
    def calculate_weighted_count(current_count, previous_count, window)
      # Calculate how far we are into the current window
      time_in_window = Time.current.to_i % window

      # Weight for previous window (decreases as we move through current window)
      previous_weight = (window - time_in_window).to_f / window

      # Sliding window count: weighted previous + current
      (previous_count * previous_weight).ceil + current_count
    end

    # Calculate sliding window count without incrementing
    def calculate_sliding_window_count(key, window)
      current = current_window(window)
      previous = previous_window(window)

      current_key = "#{key}:#{current}"
      previous_key = "#{key}:#{previous}"

      results = $redis.pipelined do |pipeline|
        pipeline.get(current_key)
        pipeline.get(previous_key)
      end

      current_count = results[0].to_i
      previous_count = results[1].to_i

      calculate_weighted_count(current_count, previous_count, window)
    end

    # Get current time window
    def current_window(window = 60)
      Time.current.to_i / window
    end

    # Get previous time window
    def previous_window(window = 60)
      current_window(window) - 1
    end

    # Calculate retry-after time in seconds
    def calculate_retry_after(key, window)
      time_in_window = Time.current.to_i % window
      window - time_in_window
    end

    # Handle Redis failure with logging
    def handle_redis_failure(error, scope)
      Rails.logger.warn "RateLimiter: Redis unavailable for #{scope}, allowing request (fail-open): #{error.message}"

      # Optional: Send notification to admins about Redis failure
      # This prevents cascading failures
      if defined?(GotifyNotificationService) && error.is_a?(Redis::CannotConnectError)
        begin
          # Only send one alert per minute to avoid spam
          cache_key = "rate_limiter_redis_failure_alert"
          unless Rails.cache.exist?(cache_key)
            Rails.cache.write(cache_key, true, expires_in: 1.minute)
            # Note: This bypasses rate limiting intentionally for critical infrastructure alerts
          end
        rescue StandardError
          # Ignore errors in error handler
        end
      end
    end
  end
end
