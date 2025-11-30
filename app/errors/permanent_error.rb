# frozen_string_literal: true

# Base class for permanent errors that should NOT trigger retries
# These are failures that will not succeed even if retried
class PermanentError < ApplicationError
  # These errors should be discarded, not retried
  def should_discard?
    true
  end
end

# Configuration errors
class ConfigurationError < PermanentError; end
class MissingConfigurationError < ConfigurationError; end
class InvalidConfigurationError < ConfigurationError; end

# Authentication and authorization errors
class AuthenticationError < PermanentError
  attr_reader :status_code

  def initialize(message = 'Authentication failed', status_code: 401, context: {})
    @status_code = status_code
    super(message, context: context.merge(status_code: status_code))
  end
end

class AuthorizationError < PermanentError
  attr_reader :status_code

  def initialize(message = 'Authorization failed', status_code: 403, context: {})
    @status_code = status_code
    super(message, context: context.merge(status_code: status_code))
  end
end

# Resource errors
class ResourceNotFoundError < PermanentError
  attr_reader :status_code

  def initialize(message = 'Resource not found', status_code: 404, context: {})
    @status_code = status_code
    super(message, context: context.merge(status_code: status_code))
  end
end

class BadRequestError < PermanentError
  attr_reader :status_code

  def initialize(message = 'Bad request', status_code: 400, context: {})
    @status_code = status_code
    super(message, context: context.merge(status_code: status_code))
  end
end

# Validation errors
class ValidationError < PermanentError; end
class InvalidInputError < ValidationError; end
class SchemaError < ValidationError; end

# Business logic errors
class BusinessLogicError < PermanentError; end
class StateError < BusinessLogicError; end
class DuplicateError < BusinessLogicError; end
