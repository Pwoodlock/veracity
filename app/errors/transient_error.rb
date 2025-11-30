# frozen_string_literal: true

# Base class for transient errors that should trigger retries
# These are temporary failures that may succeed on retry
class TransientError < ApplicationError
  # Default retry configuration
  def retry_wait
    :exponentially_longer
  end

  def retry_attempts
    5
  end
end

# Network-related transient errors
class NetworkError < TransientError
  def retry_attempts
    3
  end
end

class ConnectionRefusedError < NetworkError; end
class TimeoutError < NetworkError; end
class DNSError < NetworkError; end

# HTTP-specific transient errors
class HTTPTransientError < TransientError
  attr_reader :status_code

  def initialize(message = nil, status_code: nil, context: {})
    @status_code = status_code
    super(message, context: context.merge(status_code: status_code))
  end
end

# Server temporarily unavailable (503)
class ServiceUnavailableError < HTTPTransientError
  def initialize(message = 'Service temporarily unavailable', **kwargs)
    super(message, status_code: 503, **kwargs)
  end
end

# Rate limiting (429)
class RateLimitError < HTTPTransientError
  def initialize(message = 'Rate limit exceeded', **kwargs)
    super(message, status_code: 429, **kwargs)
  end

  def retry_wait
    # For rate limiting, use longer backoff
    30.seconds
  end

  def retry_attempts
    3
  end
end

# Gateway timeout (504)
class GatewayTimeoutError < HTTPTransientError
  def initialize(message = 'Gateway timeout', **kwargs)
    super(message, status_code: 504, **kwargs)
  end
end

# Too many requests from external API
class APIThrottleError < RateLimitError
  def initialize(message = 'API request throttled', **kwargs)
    super(message, **kwargs)
  end
end
