# frozen_string_literal: true

# Base application error class
# All custom errors should inherit from this class
class ApplicationError < StandardError
  attr_reader :context

  def initialize(message = nil, context: {})
    @context = context
    super(message)
  end

  # Log error with context
  def log_error(logger = Rails.logger)
    logger.error("#{self.class.name}: #{message}")
    logger.error("Context: #{context.inspect}") if context.present?
  end
end
