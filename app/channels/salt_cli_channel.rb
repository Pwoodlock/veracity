# frozen_string_literal: true

# Action Cable channel for streaming Salt CLI command output
# Each user gets their own stream based on user_id
class SaltCliChannel < ApplicationCable::Channel
  def subscribed
    # Only allow admin users
    unless current_user.admin?
      reject
      return
    end

    # Stream to user-specific channel
    stream_from "salt_cli_#{current_user.id}"
    Rails.logger.info "SaltCliChannel: Admin #{current_user.email} subscribed"
  end

  def unsubscribed
    Rails.logger.info "SaltCliChannel: Admin #{current_user.email} unsubscribed"
  end

  # Receive command from client (alternative to HTTP POST)
  def execute(data)
    command = data['command'].to_s.strip
    return if command.blank?

    # Create command record
    cli_command = SaltCliCommand.create!(
      user: current_user,
      command: command,
      status: 'pending'
    )

    # Execute in background
    SaltCliExecutionJob.perform_later(cli_command.id)

    # Send acknowledgment
    transmit({
      type: 'command_received',
      command_id: cli_command.id,
      command: command
    })
  end
end
