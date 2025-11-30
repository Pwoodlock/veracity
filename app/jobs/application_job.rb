class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: :exponentially_longer, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Retry on transient errors with exponential backoff
  retry_on TransientError, wait: :exponentially_longer, attempts: 5
  retry_on NetworkError, wait: :exponentially_longer, attempts: 3
  retry_on RateLimitError, wait: 30.seconds, attempts: 3
  retry_on ServiceUnavailableError, wait: :exponentially_longer, attempts: 5
  retry_on GatewayTimeoutError, wait: :exponentially_longer, attempts: 4

  # Discard jobs that have permanent errors (don't retry)
  discard_on PermanentError
  discard_on AuthenticationError
  discard_on AuthorizationError
  discard_on ConfigurationError
  discard_on ResourceNotFoundError
  discard_on BadRequestError
  discard_on ValidationError

  # Log job failures with context
  rescue_from StandardError do |exception|
    log_job_failure(exception)
    raise exception
  end

  private

  def log_job_failure(exception)
    Rails.logger.error "Job #{self.class.name} failed: #{exception.class.name}"
    Rails.logger.error "Message: #{exception.message}"
    Rails.logger.error "Job ID: #{job_id}"
    Rails.logger.error "Arguments: #{arguments.inspect}" if arguments.present?
    Rails.logger.error "Executions: #{executions}" if respond_to?(:executions)
    Rails.logger.error "Backtrace: #{exception.backtrace.first(5).join("\n")}" if exception.backtrace.present?
  end
end
