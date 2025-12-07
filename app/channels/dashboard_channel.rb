# frozen_string_literal: true

# Action Cable channel for broadcasting dashboard updates to all users
# Uses global stream - all authenticated users receive same updates
class DashboardChannel < ApplicationCable::Channel
  def subscribed
    stream_from "dashboard"
    Rails.logger.info "DashboardChannel: User #{current_user.email} subscribed"
  end

  def unsubscribed
    Rails.logger.info "DashboardChannel: User #{current_user.email} unsubscribed"
  end
end
