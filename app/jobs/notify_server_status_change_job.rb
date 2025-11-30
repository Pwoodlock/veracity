# frozen_string_literal: true

# Background job for sending Gotify notifications when server status changes
# This job is triggered after a server status update is committed to the database
# and handles the external API call asynchronously to avoid blocking database transactions.
#
# @example
#   NotifyServerStatusChangeJob.perform_later(server_id: 123, old_status: 'online', new_status: 'offline')
#
class NotifyServerStatusChangeJob < ApplicationJob
  queue_as :notifications

  # Retry configuration for transient failures
  # Uses exponential backoff: wait 3s, 18s, 83s, 258s between attempts
  retry_on GotifyNotificationService::ConnectionError,
           wait: :exponentially_longer,
           attempts: 5

  # Retry on standard network/timeout errors
  retry_on Net::OpenTimeout,
           Net::ReadTimeout,
           Errno::ECONNREFUSED,
           Errno::EHOSTUNREACH,
           SocketError,
           wait: :exponentially_longer,
           attempts: 5

  # Discard job on permanent failures (configuration/authentication errors)
  discard_on GotifyNotificationService::ConfigurationError
  discard_on ActiveJob::DeserializationError

  # Perform the notification job
  # @param server_id [Integer] The ID of the server
  # @param old_status [String] The previous status (e.g., 'online', 'offline')
  # @param new_status [String] The new status (e.g., 'online', 'offline')
  def perform(server_id:, old_status:, new_status:)
    Rails.logger.info "NotifyServerStatusChangeJob: Processing status change for server_id=#{server_id} (#{old_status} -> #{new_status})"

    # Fetch the server record
    server = Server.find_by(id: server_id)
    unless server
      Rails.logger.warn "NotifyServerStatusChangeJob: Server #{server_id} not found, skipping notification"
      return
    end

    # Validate status change is still significant
    unless significant_status_change?(old_status, new_status)
      Rails.logger.info "NotifyServerStatusChangeJob: Status change not significant, skipping notification"
      return
    end

    # Map status to event type
    event = determine_event_type(new_status)

    # Build notification message
    message = "Status changed from #{old_status} to #{new_status}"

    # Send notification via GotifyNotificationService
    Rails.logger.info "NotifyServerStatusChangeJob: Sending notification for #{server.hostname} (event: #{event})"

    notification_history = GotifyNotificationService.notify_server_event(server, event, message)

    if notification_history
      Rails.logger.info "NotifyServerStatusChangeJob: Successfully sent notification for #{server.hostname} (notification_id: #{notification_history.id})"
    else
      # Service already logs the error, but we'll log job completion
      Rails.logger.warn "NotifyServerStatusChangeJob: Notification was not sent for #{server.hostname}"
    end
  rescue ActiveRecord::RecordNotFound => e
    # Server was deleted between job enqueue and execution
    Rails.logger.warn "NotifyServerStatusChangeJob: Server #{server_id} was deleted, discarding job: #{e.message}"
  rescue GotifyNotificationService::GotifyError => e
    # Gotify-specific errors (will retry or discard based on retry_on/discard_on)
    Rails.logger.error "NotifyServerStatusChangeJob: Gotify error for server_id=#{server_id}: #{e.message}"
    raise # Re-raise to trigger retry logic
  rescue StandardError => e
    # Unexpected errors
    Rails.logger.error "NotifyServerStatusChangeJob: Unexpected error for server_id=#{server_id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise to trigger retry logic
  end

  private

  # Check if the status change is significant enough to warrant a notification
  # Only notify for transitions between online and offline/unreachable states
  #
  # @param old_status [String] The previous status
  # @param new_status [String] The new status
  # @return [Boolean] true if notification should be sent
  def significant_status_change?(old_status, new_status)
    return false if old_status == new_status

    # Define significant statuses
    online_statuses = ['online']
    offline_statuses = ['offline', 'unreachable']

    # Significant if transitioning between online and offline states
    (online_statuses.include?(old_status) && offline_statuses.include?(new_status)) ||
      (offline_statuses.include?(old_status) && online_statuses.include?(new_status))
  end

  # Map server status to notification event type
  #
  # @param status [String] The server status
  # @return [String] The event type for the notification
  def determine_event_type(status)
    case status
    when 'offline', 'unreachable'
      'offline'
    when 'online'
      'online'
    else
      'status_change'
    end
  end
end
