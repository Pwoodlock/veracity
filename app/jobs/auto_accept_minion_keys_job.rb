# frozen_string_literal: true

# Background job to automatically accept minion keys based on fingerprint whitelist
# Runs every 30 seconds via sidekiq-cron when auto-accept mode is enabled
class AutoAcceptMinionKeysJob < ApplicationJob
  queue_as :default

  def perform
    # Early return if auto-accept is disabled
    return unless SystemSetting.get('auto_accept_keys_enabled', false)

    Rails.logger.info "[AUTO-ACCEPT-JOB] Starting auto-accept scan"

    # Load whitelist
    whitelist_json = SystemSetting.get('auto_accept_fingerprint_whitelist', '[]')
    whitelist = JSON.parse(whitelist_json) rescue []

    if whitelist.empty?
      Rails.logger.debug "[AUTO-ACCEPT-JOB] Whitelist is empty, skipping"
      return
    end

    # Get pending keys
    pending_keys = SaltService.list_pending_keys

    if pending_keys.empty?
      Rails.logger.debug "[AUTO-ACCEPT-JOB] No pending keys found"
      return
    end

    Rails.logger.info "[AUTO-ACCEPT-JOB] Found #{pending_keys.size} pending keys, checking against #{whitelist.size} whitelisted fingerprints"

    accepted_keys = []
    failed_keys = []

    pending_keys.each do |key|
      minion_id = key[:minion_id]
      fingerprint = key[:fingerprint]

      # Skip if no fingerprint
      next unless fingerprint

      # Check if fingerprint is whitelisted
      if whitelist.include?(fingerprint)
        begin
          result = SaltService.accept_key_with_verification(minion_id, fingerprint)

          if result[:success]
            accepted_keys << minion_id
            Rails.logger.info "[AUTO-ACCEPT] Accepted key: #{minion_id} (fingerprint: #{fingerprint})"
          else
            failed_keys << { minion_id: minion_id, error: result[:message] }
            Rails.logger.error "[AUTO-ACCEPT] Failed to accept #{minion_id}: #{result[:message]}"
          end
        rescue StandardError => e
          failed_keys << { minion_id: minion_id, error: e.message }
          Rails.logger.error "[AUTO-ACCEPT] Error accepting #{minion_id}: #{e.message}"
        end
      end
    end

    # Register accepted servers
    if accepted_keys.any?
      Rails.logger.info "[AUTO-ACCEPT-JOB] Waiting 2 seconds for minions to connect..."
      sleep 2
      register_accepted_minions(accepted_keys)

      # Send notification if enabled
      if SystemSetting.get('notify_on_auto_accept', true)
        send_auto_accept_notification(accepted_keys)
      end
    end

    Rails.logger.info "[AUTO-ACCEPT-JOB] Completed - Accepted: #{accepted_keys.size}, Failed: #{failed_keys.size}"
  rescue StandardError => e
    Rails.logger.error "[AUTO-ACCEPT-JOB] Job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  # Register multiple accepted minions efficiently
  def register_accepted_minions(minion_ids)
    begin
      minions_data = SaltService.discover_all_minions

      minion_ids.each do |minion_id|
        minion_data = minions_data.find { |m| m[:minion_id] == minion_id }
        next unless minion_data

        server = Server.find_or_initialize_by(minion_id: minion_id)
        grains = minion_data[:grains]

        server.hostname = grains['id'] || grains['nodename'] || minion_id
        server.ip_address = grains['fqdn_ip4']&.first || grains['ipv4']&.first
        server.status = minion_data[:online] ? 'online' : 'offline'
        server.os_family = grains['os_family']
        server.os_name = grains['os']
        server.os_version = grains['osrelease'] || grains['osmajorrelease']&.to_s
        server.cpu_cores = grains['num_cpus']
        server.memory_gb = (grains['mem_total'].to_f / 1024.0).round(2) if grains['mem_total']
        server.grains = grains
        server.last_seen = Time.current if minion_data[:online]
        server.last_heartbeat = Time.current if minion_data[:online]

        server.save
        Rails.logger.info "[AUTO-ACCEPT] Registered server: #{server.hostname} (#{minion_id})"
      end
    rescue StandardError => e
      Rails.logger.error "[AUTO-ACCEPT] Error registering minions: #{e.message}"
    end
  end

  # Send Gotify notification for auto-accepted keys
  def send_auto_accept_notification(accepted_minion_ids)
    return if accepted_minion_ids.empty?

    begin
      minion_list = accepted_minion_ids.join(', ')
      message = "🤖 Auto-accepted #{accepted_minion_ids.size} minion key(s): #{minion_list}"

      GotifyNotificationService.send_notification(
        title: 'Minion Keys Auto-Accepted',
        message: message,
        priority: 5,
        notification_type: 'minion_auto_accepted'
      )

      Rails.logger.info "[AUTO-ACCEPT] Sent notification for #{accepted_minion_ids.size} auto-accepted keys"
    rescue StandardError => e
      Rails.logger.error "[AUTO-ACCEPT] Failed to send notification: #{e.message}"
    end
  end
end
