# frozen_string_literal: true

# Background job for refreshing server grains (facts) from Salt
class RefreshGrainsJob < ApplicationJob
  queue_as :default

  def perform(minion_id)
    Rails.logger.info "RefreshGrainsJob: Refreshing grains for #{minion_id}"

    # Get grains from Salt
    result = SaltService.get_grains(minion_id)

    if result && result['return']
      grains_data = result['return'].first[minion_id]

      if grains_data
        update_server_from_grains(minion_id, grains_data)
        Rails.logger.info "RefreshGrainsJob: Successfully updated grains for #{minion_id}"
      else
        Rails.logger.warn "RefreshGrainsJob: No grains data returned for #{minion_id}"
      end
    else
      Rails.logger.error "RefreshGrainsJob: Failed to get grains for #{minion_id}"
    end
  rescue StandardError => e
    Rails.logger.error "RefreshGrainsJob: Error for #{minion_id}: #{e.message}"
    raise # Re-raise to trigger retry
  end

  private

  def update_server_from_grains(minion_id, grains)
    server = Server.find_or_initialize_by(minion_id: minion_id)

    # Extract relevant information from grains
    server.assign_attributes(
      hostname: grains['host'] || grains['nodename'] || minion_id,
      ip_address: extract_ip_address(grains),
      os_family: grains['os_family'] || grains['os'],
      os_name: grains['os'] || grains['osfullname'],
      os_version: grains['osrelease'] || grains['osversion'],
      cpu_cores: grains['num_cpus'] || grains['cpuarch'],
      memory_gb: extract_memory_gb(grains),
      grains: grains,
      environment: grains['environment'] || 'production',
      location: grains['location'] || grains['datacenter'],
      provider: grains['provider'] || detect_provider(grains),
      status: 'online',
      last_seen: Time.current
    )

    server.save!
    server
  end

  def extract_ip_address(grains)
    # Try various grain keys for IP address
    grains['ipv4']&.first ||
      grains['ip4_interfaces']&.dig('eth0', 0) ||
      grains['ip_interfaces']&.dig('eth0', 0) ||
      grains['fqdn_ip4']&.first ||
      '0.0.0.0'
  end

  def extract_memory_gb(grains)
    mem_total = grains['mem_total'] || grains['memory_total'] || 0
    # Convert MB to GB
    (mem_total.to_f / 1024).round(2)
  end

  def detect_provider(grains)
    # Detect cloud provider from grains
    return 'aws' if grains['ec2']
    return 'azure' if grains['azure']
    return 'gcp' if grains['gce']
    return 'digitalocean' if grains['digitalocean']
    return 'vmware' if grains['virtual'] == 'VMware'
    return 'docker' if grains['virtual'] == 'container'
    return 'virtualbox' if grains['virtual'] == 'VirtualBox'

    'bare_metal'
  end
end