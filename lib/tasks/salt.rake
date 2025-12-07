# frozen_string_literal: true

namespace :salt do
  desc 'Seed Salt Editor templates (states, pillars, cloud profiles, orchestration)'
  task seed_templates: :environment do
    require Rails.root.join('db', 'seeds', 'salt_templates.rb')
  end

  desc 'Discover and register all accepted Salt minions'
  task discover: :environment do
    puts '=' * 80
    puts 'SALT MINION DISCOVERY'
    puts '=' * 80
    puts

    begin
      # Discover all minions
      puts '🔍 Discovering accepted minions from Salt Master...'
      minions_data = SaltService.discover_all_minions

      if minions_data.empty?
        puts '⚠️  No accepted minions found.'
        puts '   Run `salt-key -L` to check key status on Salt Master'
        next
      end

      puts "✓ Found #{minions_data.count} accepted minion(s)"
      puts

      # Process each minion
      created_count = 0
      updated_count = 0
      error_count = 0

      minions_data.each do |minion_data|
        minion_id = minion_data[:minion_id]
        online = minion_data[:online]
        grains = minion_data[:grains]

        print "  Processing #{minion_id}... "

        begin
          # Find or create server
          server = Server.find_or_initialize_by(minion_id: minion_id)
          is_new = server.new_record?

          # Update basic info
          server.hostname = grains['id'] || grains['nodename'] || minion_id
          server.ip_address = grains['fqdn_ip4']&.first || grains['ipv4']&.first
          server.status = online ? 'online' : 'offline'

          # Update OS info if available
          if grains.present?
            server.os_family = grains['os_family']
            server.os_name = grains['os']
            server.os_version = grains['osrelease'] || grains['osmajorrelease']&.to_s
            server.cpu_cores = grains['num_cpus']
            server.memory_gb = (grains['mem_total'].to_f / 1024.0).round(2) if grains['mem_total']
            server.grains = grains
          end

          # Set timestamps
          server.last_seen = Time.current if online
          server.last_heartbeat = Time.current if online

          # Save
          if server.save
            if is_new
              created_count += 1
              puts "✓ Created (#{server.status})"
            else
              updated_count += 1
              puts "✓ Updated (#{server.status})"
            end
          else
            error_count += 1
            puts "✗ Error: #{server.errors.full_messages.join(', ')}"
          end

        rescue StandardError => e
          error_count += 1
          puts "✗ Error: #{e.message}"
          Rails.logger.error "Error processing minion #{minion_id}: #{e.message}"
        end
      end

      # Summary
      puts
      puts '─' * 80
      puts 'SUMMARY'
      puts '─' * 80
      puts "  Servers created: #{created_count}"
      puts "  Servers updated: #{updated_count}"
      puts "  Errors: #{error_count}"
      puts

      if error_count > 0
        puts '⚠️  Some minions could not be processed. Check logs for details.'
      else
        puts '✓ All minions processed successfully!'
      end

    rescue StandardError => e
      puts
      puts "✗ ERROR: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end
  end

  desc 'Sync online/offline status for all registered servers'
  task sync_status: :environment do
    puts '=' * 80
    puts 'SYNC SERVER STATUS'
    puts '=' * 80
    puts

    servers = Server.all

    if servers.empty?
      puts '⚠️  No servers found in database.'
      puts '   Run `rails salt:discover` first to register minions'
      exit 0
    end

    puts "🔍 Checking status for #{servers.count} server(s)..."
    puts

    online_count = 0
    offline_count = 0
    error_count = 0

    servers.each do |server|
      print "  #{server.hostname} (#{server.minion_id})... "

      begin
        # Ping the minion
        result = SaltService.ping_minion(server.minion_id)
        online = result && result['return'] && result['return'].first && result['return'].first[server.minion_id] == true

        # Update status
        old_status = server.status
        server.status = online ? 'online' : 'offline'
        server.last_heartbeat = Time.current if online
        server.last_seen = Time.current if online
        server.save!

        if online
          online_count += 1
          puts "✓ online#{old_status != 'online' ? ' (changed)' : ''}"
        else
          offline_count += 1
          puts "✗ offline#{old_status != 'offline' ? ' (changed)' : ''}"
        end

      rescue StandardError => e
        error_count += 1
        puts "✗ Error: #{e.message}"
        Rails.logger.error "Error syncing status for #{server.minion_id}: #{e.message}"
      end
    end

    # Summary
    puts
    puts '─' * 80
    puts 'SUMMARY'
    puts '─' * 80
    puts "  Online: #{online_count}"
    puts "  Offline: #{offline_count}"
    puts "  Errors: #{error_count}"
    puts

    if error_count > 0
      puts '⚠️  Some servers could not be checked. Check logs for details.'
    else
      puts '✓ All servers synced successfully!'
    end
  end

  desc 'List pending minion keys with fingerprints'
  task pending_keys: :environment do
    puts '=' * 80
    puts 'PENDING MINION KEYS'
    puts '=' * 80
    puts

    begin
      pending_keys = SaltService.list_pending_keys

      if pending_keys.empty?
        puts '✓ No pending keys found.'
        puts '   All minions are either accepted or rejected.'
        next
      end

      puts "Found #{pending_keys.count} pending key(s):"
      puts

      pending_keys.each_with_index do |key_data, index|
        puts "#{index + 1}. Minion ID: #{key_data[:minion_id]}"
        puts "   Fingerprint: #{key_data[:fingerprint] || '(unavailable)'}"
        puts "   Status: #{key_data[:status]}"
        puts
      end

      puts '─' * 80
      puts 'To accept a key with fingerprint verification:'
      puts '  rails salt:accept_key[minion_id,fingerprint]'
      puts
      puts 'Example:'
      puts "  rails salt:accept_key[#{pending_keys.first[:minion_id]},#{pending_keys.first[:fingerprint]}]"
      puts

    rescue StandardError => e
      puts
      puts "✗ ERROR: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end
  end

  desc 'Accept a minion key with fingerprint verification'
  task :accept_key, [:minion_id, :fingerprint] => :environment do |_t, args|
    puts '=' * 80
    puts 'ACCEPT MINION KEY'
    puts '=' * 80
    puts

    # Validate arguments
    unless args[:minion_id] && args[:fingerprint]
      puts '✗ ERROR: Missing required arguments'
      puts
      puts 'Usage:'
      puts '  rails salt:accept_key[minion_id,fingerprint]'
      puts
      puts 'Example:'
      puts '  rails salt:accept_key[web-01.example.com,aa:bb:cc:dd:ee:ff:...]'
      puts
      puts 'To see pending keys with fingerprints:'
      puts '  rails salt:pending_keys'
      exit 1
    end

    minion_id = args[:minion_id]
    fingerprint = args[:fingerprint]

    puts "Minion ID:   #{minion_id}"
    puts "Fingerprint: #{fingerprint}"
    puts

    begin
      # Accept key with verification
      puts '🔐 Verifying fingerprint and accepting key...'
      result = SaltService.accept_key_with_verification(minion_id, fingerprint)

      if result[:success]
        puts "✓ Key accepted successfully for #{minion_id}"
        puts

        # Try to discover and register the minion immediately
        puts '🔍 Attempting to register minion in database...'
        sleep 2 # Give Salt a moment to process the key acceptance

        begin
          minions_data = SaltService.discover_all_minions
          minion_data = minions_data.find { |m| m[:minion_id] == minion_id }

          if minion_data
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

            if server.save
              puts "✓ Server registered in database: #{server.hostname}"
            else
              puts "⚠️  Could not register server: #{server.errors.full_messages.join(', ')}"
              puts "   You can manually run: rails salt:discover"
            end
          else
            puts '⚠️  Minion not responding yet. It may take a moment to come online.'
            puts "   Run 'rails salt:discover' in a few seconds to register it."
          end

        rescue StandardError => e
          puts "⚠️  Could not auto-register minion: #{e.message}"
          puts "   Run 'rails salt:discover' to complete registration"
        end

      else
        puts "✗ Failed to accept key: #{result[:message]}"
        exit 1
      end

    rescue SaltService::SaltAPIError => e
      puts
      puts "✗ ERROR: #{e.message}"
      puts
      puts 'Possible causes:'
      puts '  - Fingerprint mismatch (check with: rails salt:pending_keys)'
      puts '  - Minion key not found or already accepted'
      puts '  - Salt Master connection issue'
      exit 1
    rescue StandardError => e
      puts
      puts "✗ UNEXPECTED ERROR: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end
  end

  desc 'Show Salt Master statistics and connection info'
  task stats: :environment do
    puts '=' * 80
    puts 'SALT MASTER STATISTICS'
    puts '=' * 80
    puts

    begin
      # Test connection
      puts '🔌 Testing Salt API connection...'
      connection = SaltService.test_connection

      if connection[:status] == 'connected'
        puts '✓ Connected successfully'
        puts "  API URL: #{connection[:api_url]}"
        puts "  Authenticated: #{connection[:authenticated]}"
        puts
      else
        puts "✗ Connection failed: #{connection[:message]}"
        exit 1
      end

      # Get all keys
      puts '🔑 Fetching key status...'
      keys_response = SaltService.list_keys

      if keys_response && keys_response['return']
        data = keys_response['return'].first['data']['return']
        accepted = data['minions'] || []
        pending = data['minions_pre'] || []
        rejected = data['minions_rejected'] || []

        puts '  Accepted keys: ' + (accepted.count > 0 ? accepted.count.to_s : '0')
        puts '  Pending keys: ' + (pending.count > 0 ? pending.count.to_s : '0')
        puts '  Rejected keys: ' + (rejected.count > 0 ? rejected.count.to_s : '0')
        puts
      end

      # Database stats
      puts '💾 Database statistics:'
      puts "  Total servers: #{Server.count}"
      puts "  Online servers: #{Server.where(status: 'online').count}"
      puts "  Offline servers: #{Server.where(status: 'offline').count}"
      puts "  Total metrics: #{ServerMetric.count}"
      puts "  Total commands: #{Command.count}"
      puts

      puts '✓ All systems operational'

    rescue StandardError => e
      puts
      puts "✗ ERROR: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end
  end

  desc 'Deploy proxmox_api.py script to all Proxmox hosts'
  task deploy_proxmox_scripts: :environment do
    puts '=' * 80
    puts 'DEPLOY PROXMOX API SCRIPTS'
    puts '=' * 80
    puts

    # Find all Proxmox hosts (identified by hostname pattern or having proxmox_api_key)
    proxmox_servers = Server.where("minion_id LIKE 'pve%'").or(
      Server.where.not(proxmox_api_key_id: nil)
    ).where(status: 'online')

    if proxmox_servers.empty?
      puts '⚠️  No Proxmox servers found.'
      puts '   Servers must:'
      puts '   - Have minion_id starting with "pve"'
      puts '   - OR have a Proxmox API key configured'
      puts '   - AND be online'
      exit 0
    end

    puts "Found #{proxmox_servers.count} Proxmox host(s):"
    proxmox_servers.each { |s| puts "  - #{s.hostname} (#{s.minion_id})" }
    puts

    script_path = Rails.root.join('lib', 'scripts', 'proxmox_api.py')
    unless File.exist?(script_path)
      puts "✗ ERROR: Script not found at #{script_path}"
      exit 1
    end

    script_content = File.read(script_path)
    success_count = 0
    error_count = 0

    proxmox_servers.each do |server|
      print "  Deploying to #{server.hostname}... "

      begin
        # Create script content via Salt file.write
        result = SaltService.run_command(
          server.minion_id,
          'file.write',
          ['/usr/local/bin/proxmox_api.py', script_content]
        )

        if result[:success]
          # Set executable permissions
          chmod_result = SaltService.run_command(
            server.minion_id,
            'file.set_mode',
            ['/usr/local/bin/proxmox_api.py', '0755']
          )

          if chmod_result[:success]
            # Verify Python dependencies
            dep_result = SaltService.run_command(
              server.minion_id,
              'cmd.run',
              ['pip3 list | grep -E "(proxmoxer|requests)" || echo "MISSING"']
            )

            if dep_result[:success] && !dep_result[:output].include?('MISSING')
              success_count += 1
              puts '✓ Deployed successfully'
            else
              puts '⚠️  Deployed but dependencies missing (run: pip3 install proxmoxer requests)'
              success_count += 1
            end
          else
            error_count += 1
            puts "✗ Failed to set permissions: #{chmod_result[:output]}"
          end
        else
          error_count += 1
          puts "✗ Failed: #{result[:output]}"
        end

      rescue StandardError => e
        error_count += 1
        puts "✗ Error: #{e.message}"
        Rails.logger.error "Error deploying to #{server.minion_id}: #{e.message}"
      end
    end

    # Summary
    puts
    puts '─' * 80
    puts 'SUMMARY'
    puts '─' * 80
    puts "  Successful: #{success_count}"
    puts "  Errors: #{error_count}"
    puts

    if error_count > 0
      puts '⚠️  Some deployments failed. Check logs for details.'
    else
      puts '✓ All scripts deployed successfully!'
    end
  end

  desc 'Install Python dependencies on Proxmox hosts'
  task install_proxmox_dependencies: :environment do
    puts '=' * 80
    puts 'INSTALL PROXMOX PYTHON DEPENDENCIES'
    puts '=' * 80
    puts

    proxmox_servers = Server.where("minion_id LIKE 'pve%'").or(
      Server.where.not(proxmox_api_key_id: nil)
    ).where(status: 'online')

    if proxmox_servers.empty?
      puts '⚠️  No Proxmox servers found.'
      exit 0
    end

    puts "Installing dependencies on #{proxmox_servers.count} host(s)..."
    puts

    success_count = 0
    error_count = 0

    proxmox_servers.each do |server|
      print "  #{server.hostname}... "

      begin
        # Install proxmoxer and requests
        result = SaltService.run_command(
          server.minion_id,
          'cmd.run',
          ['pip3 install --break-system-packages proxmoxer requests 2>&1 | tail -5'],
          timeout: 180
        )

        if result[:success] && !result[:output].downcase.include?('error')
          success_count += 1
          puts '✓ Installed'
        else
          error_count += 1
          puts "✗ Failed: #{result[:output]}"
        end

      rescue StandardError => e
        error_count += 1
        puts "✗ Error: #{e.message}"
      end
    end

    puts
    puts "Successful: #{success_count}, Errors: #{error_count}"
  end

  desc 'Verify proxmox_api.py script on all Proxmox hosts'
  task verify_proxmox_scripts: :environment do
    puts '=' * 80
    puts 'VERIFY PROXMOX API SCRIPTS'
    puts '=' * 80
    puts

    proxmox_servers = Server.where("minion_id LIKE 'pve%'").or(
      Server.where.not(proxmox_api_key_id: nil)
    ).where(status: 'online')

    if proxmox_servers.empty?
      puts '⚠️  No Proxmox servers found.'
      exit 0
    end

    puts "Checking #{proxmox_servers.count} host(s)..."
    puts

    verified_count = 0
    missing_count = 0
    error_count = 0

    proxmox_servers.each do |server|
      print "  #{server.hostname}... "

      begin
        # Check if script exists
        result = SaltService.run_command(
          server.minion_id,
          'file.file_exists',
          ['/usr/local/bin/proxmox_api.py']
        )

        if result[:success] && result[:output] == true
          # Check dependencies
          dep_result = SaltService.run_command(
            server.minion_id,
            'cmd.run',
            ['python3 -c "import proxmoxer; import requests; print(\'OK\')" 2>&1']
          )

          if dep_result[:success] && dep_result[:output].include?('OK')
            verified_count += 1
            puts '✓ Script and dependencies OK'
          else
            error_count += 1
            puts '⚠️  Script exists but dependencies missing'
          end
        else
          missing_count += 1
          puts '✗ Script not found'
        end

      rescue StandardError => e
        error_count += 1
        puts "✗ Error: #{e.message}"
      end
    end

    puts
    puts '─' * 80
    puts 'SUMMARY'
    puts '─' * 80
    puts "  Verified: #{verified_count}"
    puts "  Missing script: #{missing_count}"
    puts "  Errors: #{error_count}"
    puts

    if missing_count > 0
      puts '⚠️  Some hosts are missing the script.'
      puts '   Run: rails salt:deploy_proxmox_scripts'
    end

    if error_count > 0
      puts '⚠️  Some hosts have dependency issues.'
      puts '   Run: rails salt:install_proxmox_dependencies'
    end

    if missing_count == 0 && error_count == 0
      puts '✓ All Proxmox hosts verified!'
    end
  end
end
