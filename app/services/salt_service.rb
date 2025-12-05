# frozen_string_literal: true

require 'httparty'
require 'json'

# Main service class for interacting with Salt API
# Handles authentication, token management, and API calls
#
# THREAD-SAFETY: This service uses Rails.cache (Redis-backed) for token storage
# instead of class variables to ensure thread-safety in multi-threaded environments
# (Puma workers, Sidekiq jobs, etc.)
class SaltService
  include HTTParty

  # Configure HTTParty
  format :json
  headers 'Accept' => 'application/json'
  headers 'Content-Type' => 'application/json'

  # Set timeout for long-running commands (ping, updates, etc.)
  default_timeout 60

  # Configuration
  API_URL = ENV.fetch('SALT_API_URL', 'http://localhost:8001')
  USERNAME = ENV.fetch('SALT_API_USERNAME', 'saltapi')
  # SECURITY: Fail fast if password is not set - no empty string fallback
  PASSWORD = ENV.fetch('SALT_API_PASSWORD') do
    raise ArgumentError, 'SALT_API_PASSWORD environment variable is required for security'
  end
  EAUTH = ENV.fetch('SALT_API_EAUTH', 'pam')

  # Token expiration (11 hours to be safe with 12-hour server setting)
  TOKEN_EXPIRY = 11.hours

  # THREAD-SAFE TOKEN STORAGE: Cache keys for Redis-backed storage
  # Using Rails.cache ensures:
  # - Thread-safety across Puma workers
  # - Shared token state across processes
  # - Automatic expiration handling
  # - No memory leaks from class variables
  CACHE_KEY_TOKEN = 'salt_api_auth_token'
  CACHE_KEY_EXPIRES_AT = 'salt_api_token_expires_at'

  # MUTEX for thread-safe token refresh
  # This prevents race conditions when multiple threads try to refresh simultaneously
  # The mutex is per-process, but combined with cache checking it prevents over-authentication
  @token_refresh_mutex = Mutex.new

  class SaltAPIError < StandardError; end
  class AuthenticationError < SaltAPIError; end
  class ConnectionError < SaltAPIError; end

  class << self
    # Get authentication token (with thread-safe caching)
    # This method checks the cache first and only authenticates if needed
    # The mutex ensures only one thread can refresh the token at a time
    def auth_token
      if token_expired?
        # Use mutex to prevent multiple threads from authenticating simultaneously
        @token_refresh_mutex.synchronize do
          # Double-check inside mutex - another thread may have refreshed while we waited
          if token_expired?
            authenticate!
          end
        end
      end

      # Read from cache (thread-safe)
      read_token_from_cache
    end

    # Force authentication
    # This method updates the shared cache that all threads/processes can access
    def authenticate!
      Rails.logger.info "Authenticating with Salt API at #{API_URL}"

      begin
        response = post("#{API_URL}/login",
          body: {
            username: USERNAME,
            password: PASSWORD,
            eauth: EAUTH
          }.to_json
        )

        if response.success? && response['return']&.first
          data = response['return'].first
          token = data['token']
          expires_at = TOKEN_EXPIRY.from_now

          # THREAD-SAFE: Write to cache instead of class variables
          # This ensures all Puma workers and Sidekiq jobs share the same token
          write_token_to_cache(token, expires_at)

          Rails.logger.info "Successfully authenticated with Salt API"
          Rails.logger.debug "Token expires at: #{expires_at}"

          token
        else
          error_msg = response['error'] || 'Authentication failed'
          Rails.logger.error "Salt API authentication failed: #{error_msg}"
          raise AuthenticationError, error_msg
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        Rails.logger.error "Salt API connection timeout: #{e.message}"
        raise ConnectionError, "Cannot connect to Salt API: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Salt API authentication error: #{e.message}"
        raise AuthenticationError, "Authentication failed: #{e.message}"
      end
    end

    # Check if token is expired
    # THREAD-SAFE: Reads from cache instead of class variables
    def token_expired?
      token = read_token_from_cache
      expires_at = read_expiry_from_cache

      token.nil? || expires_at.nil? || expires_at < Time.current
    end

    # Clear authentication token
    # THREAD-SAFE: Clears from cache, affecting all threads/processes
    def clear_token!
      Rails.logger.debug "Clearing Salt API authentication token from cache"
      Rails.cache.delete(CACHE_KEY_TOKEN)
      Rails.cache.delete(CACHE_KEY_EXPIRES_AT)
    end

    # Make an authenticated API call
    def api_call(method, endpoint, options = {})
      token = auth_token

      # Add authentication header
      options[:headers] ||= {}
      options[:headers]['X-Auth-Token'] = token
      options[:headers]['Accept'] = 'application/json'

      # Allow custom timeout for long-running operations
      # Extract timeout from options if provided, merge into options hash
      custom_timeout = options.delete(:timeout)
      if custom_timeout
        options[:timeout] = custom_timeout
        Rails.logger.debug "Using custom timeout: #{custom_timeout}s"
      end

      # Make the request
      url = "#{API_URL}#{endpoint}"
      Rails.logger.debug "Salt API #{method.upcase} #{url}"

      begin
        response = send(method, url, options)

        if response.success?
          response.parsed_response
        elsif response.code == 401
          # Token expired, retry once
          Rails.logger.warn "Salt API token expired, re-authenticating..."
          clear_token!
          token = auth_token
          options[:headers]['X-Auth-Token'] = token

          response = send(method, url, options)
          response.success? ? response.parsed_response : handle_error(response)
        else
          handle_error(response)
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        Rails.logger.error "Salt API request timeout: #{e.message}"
        raise ConnectionError, "Request timeout: #{e.message}"
      rescue StandardError => e
        Rails.logger.error "Salt API request error: #{e.message}"
        raise SaltAPIError, "API request failed: #{e.message}"
      end
    end

    # Handle error responses
    def handle_error(response)
      error_msg = if response.parsed_response.is_a?(Hash)
                    response.parsed_response['error'] || response.message
                  else
                    "HTTP #{response.code}: #{response.message}"
                  end

      Rails.logger.error "Salt API error: #{error_msg}"
      raise SaltAPIError, error_msg
    end

    # ===== High-level Salt API Methods =====

    # Test connectivity with minions
    # @param minion_id [String] Target minion ID or glob pattern (default: '*')
    # @param timeout [Integer] Timeout in seconds for minions to respond (default: 30)
    # @return [Hash] Response from Salt API with ping results
    def ping_minion(minion_id = '*', timeout: 30)
      api_call(:post, '/', {
        body: {
          client: 'local',
          tgt: minion_id,
          fun: 'test.ping',
          timeout: timeout  # Salt-level timeout for minion responses
        }.to_json,
        timeout: timeout + 30  # HTTP timeout: generous buffer for many minions
      })
    end

    # Get list of all minions
    def list_minions
      api_call(:get, '/minions')
    end

    # Get minion details
    def get_minion(minion_id)
      api_call(:get, "/minions/#{minion_id}")
    end

    # Get minion grains (system facts)
    def get_grains(minion_id)
      api_call(:post, '/', {
        body: {
          client: 'local',
          tgt: minion_id,
          fun: 'grains.items'
        }.to_json
      })
    end

    # Run a command on minions
    # @param minion_id [String] Target minion ID
    # @param command [String] Salt command to run
    # @param args [Array] Optional arguments for the command
    # @param timeout [Integer] Optional timeout in seconds (default: 60)
    # @return [Hash] Parsed result with :success and :output keys
    def run_command(minion_id, command, args = nil, timeout: nil)
      body = {
        client: 'local',
        tgt: minion_id,
        fun: command
      }
      body[:arg] = args if args

      options = { body: body.to_json }
      options[:timeout] = timeout if timeout

      result = api_call(:post, '/', options)

      # Parse Salt API response format
      if result && result['return'] && result['return'].first
        return_data = result['return'].first

        # Check if this is a glob pattern (*, ?, etc.) or specific minion
        is_glob = minion_id.include?('*') || minion_id.include?('?') || minion_id.include?('[')

        if is_glob
          # Glob pattern - return all minions' responses
          if return_data.is_a?(Hash) && return_data.any?
            # Format all minions' responses
            formatted_output = return_data.map do |minion, data|
              formatted_data = data.is_a?(String) ? data : JSON.pretty_generate(data)
              "#{minion}:\n  #{formatted_data}"
            end.join("\n\n")

            {
              success: true,
              output: formatted_output
            }
          else
            {
              success: false,
              output: "No minions matched pattern '#{minion_id}'"
            }
          end
        else
          # Specific minion ID
          output = return_data[minion_id]

          if output.nil?
            success = false
            formatted_output = "No response from minion '#{minion_id}'"
          elsif output == false
            success = false
            formatted_output = "Command returned false"
          else
            success = true
            formatted_output = output.is_a?(String) ? output : JSON.pretty_generate(output)
          end

          {
            success: success,
            output: formatted_output
          }
        end
      else
        {
          success: false,
          output: "No response from Salt API"
        }
      end
    rescue StandardError => e
      Rails.logger.error "Salt command failed for #{minion_id}: #{e.message}"
      {
        success: false,
        output: "Error: #{e.message}"
      }
    end

    # Run a command and return RAW Salt API response format
    # This is for backward compatibility with code that expects the original Salt API format
    # (e.g., MetricsCollector which needs to parse result['return'])
    #
    # @param minion_id [String] Target minion ID
    # @param command [String] Salt command to run
    # @param args [Array] Optional arguments for the command
    # @param timeout [Integer] Optional timeout in seconds (default: 60)
    # @return [Hash] Raw Salt API response with 'return' key
    def run_command_raw(minion_id, command, args = nil, timeout: nil)
      body = {
        client: 'local',
        tgt: minion_id,
        fun: command
      }
      body[:arg] = args if args

      options = { body: body.to_json }
      options[:timeout] = timeout if timeout

      # Return raw API response without parsing
      api_call(:post, '/', options)
    rescue StandardError => e
      Rails.logger.error "Salt command (raw) failed for #{minion_id}: #{e.message}"
      # Return empty result structure to prevent nil errors
      { 'return' => [{}] }
    end

    # Execute shell command on minions
    def execute_shell(minion_id, shell_command)
      run_command(minion_id, 'cmd.run', [shell_command])
    end

    # Apply a Salt state
    def apply_state(minion_id, state_name, test: false)
      fun = test ? 'state.test' : 'state.apply'
      run_command(minion_id, fun, [state_name])
    end

    # Get job details
    def get_job(job_id)
      api_call(:get, "/jobs/#{job_id}")
    end

    # Get job status (wrapper for get_job with error handling)
    # @param job_id [String] Salt job ID
    # @return [Hash] Status information with :success, :data keys
    def get_job_status(job_id)
      result = get_job(job_id)

      if result && result['return']
        job_data = result['return'].first
        {
          success: true,
          data: {
            state: determine_job_state(job_data),
            return: job_data,
            error: nil
          }
        }
      else
        {
          success: false,
          data: { state: 'unknown', return: nil, error: 'No data returned' }
        }
      end
    rescue StandardError => e
      Rails.logger.error "Failed to get job status for #{job_id}: #{e.message}"
      {
        success: false,
        data: { state: 'error', return: nil, error: e.message }
      }
    end

    # Determine job state from Salt job data
    def determine_job_state(job_data)
      return 'unknown' if job_data.nil?

      # Check if job is still running (no return data yet)
      return 'running' if job_data.empty? || job_data['return'].nil?

      # Check if all minions have returned
      expected_minions = job_data['Minions'] || []
      returned_minions = job_data['return']&.keys || []

      if returned_minions.empty?
        'pending'
      elsif expected_minions.sort == returned_minions.sort
        'complete'
      else
        'running'
      end
    end

    # List recent jobs
    def list_jobs(limit = 20)
      api_call(:post, '/', {
        body: {
          client: 'runner',
          fun: 'jobs.list_jobs'
        }.to_json
      })
    end

    # Get Salt master stats
    def get_stats
      api_call(:get, '/stats')
    end

    # Get all keys (accepted, pending, rejected)
    def list_keys
      api_call(:post, '/', {
        body: {
          client: 'wheel',
          fun: 'key.list_all'
        }.to_json
      })
    end

    # Accept a minion key
    def accept_key(minion_id)
      api_call(:post, '/', {
        body: {
          client: 'wheel',
          fun: 'key.accept',
          match: minion_id
        }.to_json
      })
    end

    # Reject a minion key
    def reject_key(minion_id)
      api_call(:post, '/', {
        body: {
          client: 'wheel',
          fun: 'key.reject',
          match: minion_id
        }.to_json
      })
    end

    # Delete a minion key
    def delete_key(minion_id)
      Rails.logger.info "Deleting minion key: #{minion_id}"

      # Use Salt API wheel.key.delete
      api_result = api_call(:post, '/', {
        body: {
          client: 'wheel',
          fun: 'key.delete',
          match: minion_id
        }.to_json
      })

      # Check if deletion was successful
      # wheel.key.delete returns success: true if it worked, return: {} (empty hash)
      if api_result && api_result['return']
        data = api_result['return'].first
        if data && data['data']
          success = data['data']['success']
          if success
            Rails.logger.info "Successfully deleted key: #{minion_id}"
          else
            Rails.logger.error "Failed to delete key #{minion_id}: API returned success=false"
          end
        end
      else
        Rails.logger.error "Failed to delete key #{minion_id}: No return data from API"
      end

      api_result
    end

    # ===== Enhanced Key Management Methods =====

    # Get pending minion keys with fingerprints
    def list_pending_keys
      Rails.logger.info "Fetching pending minion keys"

      keys_response = list_keys
      return [] unless keys_response && keys_response['return']

      data = keys_response['return'].first['data']
      pending_keys = data['return']['minions_pre'] || []

      Rails.logger.info "Found #{pending_keys.count} pending keys"

      # Get fingerprints for each pending key
      pending_keys.map do |minion_id|
        {
          minion_id: minion_id,
          fingerprint: get_key_fingerprint(minion_id),
          status: 'pending'
        }
      end
    rescue StandardError => e
      Rails.logger.error "Error listing pending keys: #{e.message}"
      []
    end

    # Get key fingerprint for a specific minion
    def get_key_fingerprint(minion_id)
      Rails.logger.debug "Getting fingerprint for minion: #{minion_id}"

      response = api_call(:post, '/', {
        body: {
          client: 'wheel',
          fun: 'key.finger',
          match: minion_id
        }.to_json
      })

      if response && response['return']
        data = response['return'].first['data']['return']
        # Use dig to safely navigate hash - check minions_pre first (pending keys), then minions (accepted keys)
        fingerprint = data.dig('minions_pre', minion_id) || data.dig('minions', minion_id)
        Rails.logger.debug "Fingerprint for #{minion_id}: #{fingerprint}"
        fingerprint
      else
        Rails.logger.warn "Could not get fingerprint for #{minion_id}"
        nil
      end
    rescue StandardError => e
      Rails.logger.error "Error getting fingerprint for #{minion_id}: #{e.message}"
      nil
    end

    # Accept a minion key with fingerprint verification
    def accept_key_with_verification(minion_id, expected_fingerprint)
      Rails.logger.info "Accepting key for #{minion_id} with fingerprint verification"

      # Get actual fingerprint
      actual_fingerprint = get_key_fingerprint(minion_id)

      unless actual_fingerprint
        error_msg = "Could not retrieve fingerprint for #{minion_id}"
        Rails.logger.error error_msg
        raise SaltAPIError, error_msg
      end

      # Verify fingerprint matches
      unless actual_fingerprint.downcase.strip == expected_fingerprint.downcase.strip
        error_msg = "Fingerprint mismatch for #{minion_id}! Expected: #{expected_fingerprint}, Got: #{actual_fingerprint}"
        Rails.logger.error error_msg
        raise SaltAPIError, error_msg
      end

      # Fingerprint verified, accept the key
      Rails.logger.info "Fingerprint verified for #{minion_id}, accepting key"
      result = accept_key(minion_id)

      if result && result['return']
        Rails.logger.info "Successfully accepted key for #{minion_id}"
        { success: true, minion_id: minion_id, message: "Key accepted successfully" }
      else
        error_msg = "Failed to accept key for #{minion_id}"
        Rails.logger.error error_msg
        raise SaltAPIError, error_msg
      end
    rescue SaltAPIError => e
      # Re-raise Salt API errors
      raise e
    rescue StandardError => e
      Rails.logger.error "Error accepting key for #{minion_id}: #{e.message}"
      raise SaltAPIError, "Error accepting key: #{e.message}"
    end

    # Discover all accepted minions with their details
    # OPTIMIZED: Uses batch operations to ping and get grains for all minions at once
    # Enhanced with error tracking for better diagnostics
    def discover_all_minions
      Rails.logger.info "Discovering all accepted minions"

      # Get list of all accepted minions
      keys_response = list_keys
      return [] unless keys_response && keys_response['return']

      data = keys_response['return'].first['data']
      accepted_minions = data['return']['minions'] || []

      Rails.logger.info "Found #{accepted_minions.count} accepted minions"
      return [] if accepted_minions.empty?

      # OPTIMIZATION: Ping ALL minions at once with glob targeting
      Rails.logger.debug "Pinging all minions with single API call"
      ping_start_time = Time.current
      ping_result = ping_minion('*')
      ping_duration = Time.current - ping_start_time
      ping_responses = ping_result && ping_result['return'] && ping_result['return'].first ? ping_result['return'].first : {}

      Rails.logger.debug "Ping completed in #{ping_duration.round(2)}s"

      # OPTIMIZATION: Get grains for ALL minions at once
      Rails.logger.debug "Fetching grains for all minions with single API call"
      grains_result = get_grains('*')
      grains_responses = grains_result && grains_result['return'] && grains_result['return'].first ? grains_result['return'].first : {}

      # Build minion data from batch results with enhanced error tracking
      minions_data = accepted_minions.map do |minion_id|
        ping_response = ping_responses[minion_id]
        online = ping_response == true
        grains = online ? (grains_responses[minion_id] || {}) : {}

        # Determine error reason if ping failed
        ping_error = if online
                       nil
                     elsif ping_response == false
                       "Minion returned false (minion service may be unhealthy)"
                     elsif ping_response.nil?
                       "No response from minion (timeout or unreachable)"
                     elsif ping_response.is_a?(String)
                       "Error: #{ping_response}"
                     else
                       "Unknown ping response: #{ping_response.inspect}"
                     end

        # Log failures for visibility
        if !online && accepted_minions.count <= 20
          # Only log individual failures if we have a reasonable number of minions
          Rails.logger.warn "Minion #{minion_id} offline: #{ping_error}"
        end

        {
          minion_id: minion_id,
          online: online,
          grains: grains,
          ping_error: ping_error,
          last_checked: Time.current
        }
      end

      online_count = minions_data.count { |m| m[:online] }
      offline_count = minions_data.count - online_count

      Rails.logger.info "Successfully discovered #{minions_data.count} minions (#{online_count} online, #{offline_count} offline)"

      # Log offline minions summary if there are many
      if offline_count > 0 && accepted_minions.count > 20
        offline_minions = minions_data.select { |m| !m[:online] }.map { |m| m[:minion_id] }
        Rails.logger.warn "Offline minions: #{offline_minions.join(', ')}"
      end

      minions_data
    rescue StandardError => e
      Rails.logger.error "Error discovering minions: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      []
    end

    # Sync grains for a specific minion (alias for get_grains for clarity)
    def sync_minion_grains(minion_id)
      Rails.logger.info "Syncing grains for minion: #{minion_id}"
      grains_result = get_grains(minion_id)

      if grains_result && grains_result['return'] && grains_result['return'].first
        grains = grains_result['return'].first[minion_id]
        Rails.logger.info "Successfully synced grains for #{minion_id}"
        grains
      else
        Rails.logger.warn "Could not sync grains for #{minion_id}"
        {}
      end
    rescue StandardError => e
      Rails.logger.error "Error syncing grains for #{minion_id}: #{e.message}"
      {}
    end

    # Get system metrics from minion
    def get_metrics(minion_id)
      # Run multiple commands in parallel
      commands = {
        cpu_percent: ['status.cpuload'],
        memory: ['status.meminfo'],
        disk: ['disk.usage'],
        network: ['network.interfaces'],
        processes: ['ps.num_cpus'],
        uptime: ['status.uptime']
      }

      results = {}
      commands.each do |key, cmd|
        results[key] = run_command(minion_id, cmd.first, cmd[1..-1])
      end

      results
    end

    # Run async job
    def run_async(minion_id, command, args = nil)
      body = {
        client: 'local_async',
        tgt: minion_id,
        fun: command
      }
      body[:arg] = args if args

      api_call(:post, '/', { body: body.to_json })
    end

    # Run batch job
    def run_batch(minion_pattern, command, batch_size = '10%')
      api_call(:post, '/', {
        body: {
          client: 'local_batch',
          tgt: minion_pattern,
          fun: command,
          batch: batch_size
        }.to_json
      })
    end

    # ===== Pillar Management Methods =====
    # Pillar data is encrypted per-minion and never appears in command-line arguments
    # This is the SECURE way to pass secrets to minions

    # Write pillar data for a specific minion
    # Creates a pillar file that only this minion can access
    # @param minion_id [String] Target minion ID
    # @param pillar_name [String] Name for the pillar file (e.g., 'netbird')
    # @param data [Hash] Pillar data to write
    # @return [Hash] Result with :success key
    def write_minion_pillar(minion_id, pillar_name, data)
      Rails.logger.info "Writing pillar '#{pillar_name}' for minion: #{minion_id}"

      # Create pillar content in YAML format
      pillar_content = data.to_yaml

      # Write pillar file using Salt's file_roots runner
      # This creates /srv/pillar/minions/<minion_id>/<pillar_name>.sls
      pillar_dir = "/srv/pillar/minions/#{minion_id}"
      pillar_file = "#{pillar_dir}/#{pillar_name}.sls"

      # Use Salt master's cmd.run to create the pillar file
      # This runs on the Salt master itself, not a minion
      result = api_call(:post, '/', {
        body: {
          client: 'runner',
          fun: 'salt.cmd',
          arg: [
            'file.mkdir',
            pillar_dir
          ]
        }.to_json
      })

      # Write the pillar file
      write_result = api_call(:post, '/', {
        body: {
          client: 'runner',
          fun: 'salt.cmd',
          arg: [
            'file.write',
            pillar_file,
            pillar_content
          ]
        }.to_json
      })

      # Ensure proper permissions (readable only by salt)
      api_call(:post, '/', {
        body: {
          client: 'runner',
          fun: 'salt.cmd',
          arg: [
            'file.set_mode',
            pillar_file,
            '0600'
          ]
        }.to_json
      })

      Rails.logger.info "Pillar file written: #{pillar_file}"
      { success: true, pillar_file: pillar_file }
    rescue StandardError => e
      Rails.logger.error "Error writing pillar for #{minion_id}: #{e.message}"
      { success: false, error: e.message }
    end

    # Delete pillar data for a specific minion
    # @param minion_id [String] Target minion ID
    # @param pillar_name [String] Name of the pillar file to delete
    # @return [Hash] Result with :success key
    def delete_minion_pillar(minion_id, pillar_name)
      Rails.logger.info "Deleting pillar '#{pillar_name}' for minion: #{minion_id}"

      pillar_file = "/srv/pillar/minions/#{minion_id}/#{pillar_name}.sls"

      result = api_call(:post, '/', {
        body: {
          client: 'runner',
          fun: 'salt.cmd',
          arg: [
            'file.remove',
            pillar_file
          ]
        }.to_json
      })

      Rails.logger.info "Pillar file deleted: #{pillar_file}"
      { success: true }
    rescue StandardError => e
      Rails.logger.error "Error deleting pillar for #{minion_id}: #{e.message}"
      { success: false, error: e.message }
    end

    # Refresh pillar data on a minion
    # This tells the minion to re-read its pillar data from the master
    # @param minion_id [String] Target minion ID
    # @return [Hash] Result with :success key
    def refresh_pillar(minion_id)
      Rails.logger.info "Refreshing pillar for minion: #{minion_id}"

      result = run_command(minion_id, 'saltutil.refresh_pillar')

      if result[:success]
        Rails.logger.info "Pillar refreshed for #{minion_id}"
      else
        Rails.logger.warn "Failed to refresh pillar for #{minion_id}: #{result[:output]}"
      end

      result
    rescue StandardError => e
      Rails.logger.error "Error refreshing pillar for #{minion_id}: #{e.message}"
      { success: false, error: e.message }
    end

    # Apply a Salt state with pillar data
    # The state can access secrets via pillar['key'] without them appearing in logs
    # @param minion_id [String] Target minion ID
    # @param state_name [String] Name of the state to apply
    # @param timeout [Integer] Timeout in seconds
    # @return [Hash] Result with :success and :output keys
    def apply_state_with_pillar(minion_id, state_name, timeout: 300)
      Rails.logger.info "Applying state '#{state_name}' to minion: #{minion_id}"

      result = run_command(minion_id, 'state.apply', [state_name], timeout: timeout)

      if result[:success]
        Rails.logger.info "State '#{state_name}' applied successfully to #{minion_id}"
      else
        Rails.logger.error "State '#{state_name}' failed on #{minion_id}: #{result[:output]}"
      end

      result
    rescue StandardError => e
      Rails.logger.error "Error applying state to #{minion_id}: #{e.message}"
      { success: false, error: e.message }
    end

    # Test method for checking connectivity
    def test_connection
      begin
        authenticate!
        get_stats
        { status: 'connected', api_url: API_URL, authenticated: true }
      rescue StandardError => e
        { status: 'error', message: e.message, api_url: API_URL }
      end
    end

    # Uninstall salt-minion from a server
    # @param minion_id [String] The minion ID to uninstall
    # @return [Hash] Result with :success, :message, :output
    def uninstall_minion(minion_id)
      Rails.logger.info "Uninstalling salt-minion from #{minion_id}"

      begin
        # First check if server is online
        ping_result = ping_minion(minion_id)
        is_online = ping_result && ping_result['return']&.first&.dig(minion_id)

        unless is_online
          return {
            success: false,
            message: "Server is offline, cannot uninstall remotely",
            output: "Minion not responding to ping"
          }
        end

        # Get OS family to determine package manager
        grains = sync_minion_grains(minion_id)
        os_family = grains['os_family']&.downcase || 'unknown'

        # Build complete uninstall command (stop, disable, remove, purge)
        # IMPORTANT: We use nohup and background (&) so the command survives salt-minion shutdown
        # The sleep at the start gives Salt time to return success before the minion stops
        uninstall_command = nil
        if os_family == 'redhat' || os_family == 'rhel'
          # Check if dnf is available (RHEL 8+, Fedora, AlmaLinux, Rocky)
          dnf_check = run_command(minion_id, 'cmd.run', ['which dnf'], timeout: 10)
          has_dnf = dnf_check && dnf_check['return']&.first&.dig(minion_id)&.include?('/dnf')

          if has_dnf
            # Complete cleanup for dnf-based systems (AlmaLinux, Rocky, RHEL 8+)
            # nohup ensures command continues after salt-minion is stopped
            uninstall_command = "nohup bash -c 'sleep 2 && systemctl stop salt-minion && systemctl disable salt-minion && dnf remove -y salt-minion && rm -rf /etc/salt /var/cache/salt /var/log/salt /var/run/salt' > /tmp/salt-uninstall.log 2>&1 &"
            Rails.logger.info "Using dnf for RedHat family uninstall with full cleanup (backgrounded)"
          else
            # Complete cleanup for yum-based systems (RHEL 7, CentOS 7)
            uninstall_command = "nohup bash -c 'sleep 2 && systemctl stop salt-minion && systemctl disable salt-minion && yum remove -y salt-minion && rm -rf /etc/salt /var/cache/salt /var/log/salt /var/run/salt' > /tmp/salt-uninstall.log 2>&1 &"
            Rails.logger.info "Using yum for RedHat family uninstall with full cleanup (backgrounded)"
          end
        else
          # Determine uninstall command for other OS families
          uninstall_command = case os_family
                             when 'debian'
                               # Complete cleanup for Debian/Ubuntu
                               "nohup bash -c 'sleep 2 && systemctl stop salt-minion && systemctl disable salt-minion && apt-get remove -y salt-minion && apt-get purge -y salt-minion && apt-get autoremove -y && rm -rf /etc/salt /var/cache/salt /var/log/salt /var/run/salt' > /tmp/salt-uninstall.log 2>&1 &"
                             when 'suse'
                               # Complete cleanup for SUSE
                               "nohup bash -c 'sleep 2 && systemctl stop salt-minion && systemctl disable salt-minion && zypper remove -y salt-minion && rm -rf /etc/salt /var/cache/salt /var/log/salt /var/run/salt' > /tmp/salt-uninstall.log 2>&1 &"
                             when 'arch'
                               # Complete cleanup for Arch
                               "nohup bash -c 'sleep 2 && systemctl stop salt-minion && systemctl disable salt-minion && pacman -Rns --noconfirm salt && rm -rf /etc/salt /var/cache/salt /var/log/salt /var/run/salt' > /tmp/salt-uninstall.log 2>&1 &"
                             else
                               return {
                                 success: false,
                                 message: "Unknown OS family: #{os_family}",
                                 output: "Cannot determine package manager for #{os_family}"
                               }
                             end
        end

        Rails.logger.info "Running uninstall command for #{os_family}: #{uninstall_command}"

        # Run uninstall command - this returns immediately since it's backgrounded
        # The actual uninstall happens in the background after a 2-second delay
        result = run_command(minion_id, 'cmd.run', [uninstall_command], timeout: 30)

        if result && result[:success]
          output = result[:output] || "Uninstall command dispatched (running in background)"

          Rails.logger.info "Uninstall command dispatched for #{minion_id}: #{output}"
          {
            success: true,
            message: "Salt minion uninstallation initiated on #{minion_id} (running in background)",
            output: output
          }
        else
          Rails.logger.error "Failed to dispatch uninstall command on #{minion_id}: #{result[:output]}"
          {
            success: false,
            message: "Failed to dispatch uninstall command",
            output: result[:output] || result.inspect
          }
        end
      rescue StandardError => e
        Rails.logger.error "Error uninstalling minion #{minion_id}: #{e.message}"
        {
          success: false,
          message: "Error: #{e.message}",
          output: e.backtrace.join("\n")
        }
      end
    end

    # Completely remove a minion (uninstall + delete key)
    # @param minion_id [String] The minion ID to remove
    # @return [Hash] Result with :success, :message, :details
    def remove_minion_completely(minion_id)
      Rails.logger.info "Completely removing minion: #{minion_id}"

      results = {
        uninstall: nil,
        delete_key: nil
      }

      # Step 1: Try to uninstall salt-minion from the server (if online)
      # The uninstall command runs in background with a 2-second delay to allow
      # Salt to return success before the minion stops
      uninstall_result = uninstall_minion(minion_id)
      results[:uninstall] = uninstall_result

      # Wait for the backgrounded uninstall to start (2s delay + 3s buffer)
      # This ensures salt-minion has stopped before we delete the key
      sleep 5 if uninstall_result[:success]

      # Step 2: Delete the minion key from Salt master
      begin
        key_result = delete_key(minion_id)

        if key_result && key_result['return']
          results[:delete_key] = {
            success: true,
            message: "Minion key deleted from Salt master"
          }
        else
          results[:delete_key] = {
            success: false,
            message: "Failed to delete minion key"
          }
        end
      rescue StandardError => e
        Rails.logger.error "Error deleting key for #{minion_id}: #{e.message}"
        results[:delete_key] = {
          success: false,
          message: "Error deleting key: #{e.message}"
        }
      end

      # Determine overall success
      key_deleted = results[:delete_key]&.dig(:success)
      uninstall_succeeded = results[:uninstall]&.dig(:success)

      {
        success: key_deleted == true, # Key deletion is critical
        message: build_removal_message(results),
        details: results
      }
    end

    # Clean up orphaned pending keys (keys that don't have associated servers)
    # This is useful after reinstalling Salt master or cleaning up old infrastructure
    # @return [Hash] Result with :success, :deleted_keys, :failed_keys
    def cleanup_orphaned_pending_keys
      Rails.logger.info "Cleaning up orphaned pending keys"

      # Get all pending keys
      pending_keys_data = list_pending_keys
      pending_minion_ids = pending_keys_data.map { |k| k[:minion_id] }

      return {
        success: true,
        deleted_keys: [],
        failed_keys: [],
        message: "No pending keys to clean up"
      } if pending_minion_ids.empty?

      # Get all minion_ids that exist in the database
      existing_minion_ids = Server.pluck(:minion_id)

      # Find orphaned keys (pending keys that don't have a server record)
      orphaned_keys = pending_minion_ids - existing_minion_ids

      if orphaned_keys.empty?
        return {
          success: true,
          deleted_keys: [],
          failed_keys: [],
          message: "No orphaned pending keys found. All pending keys are awaiting acceptance."
        }
      end

      Rails.logger.info "Found #{orphaned_keys.count} orphaned pending keys: #{orphaned_keys.join(', ')}"

      deleted = []
      failed = []

      orphaned_keys.each do |minion_id|
        begin
          result = delete_key(minion_id)
          if result && result['return']
            deleted << minion_id
            Rails.logger.info "Deleted orphaned key: #{minion_id}"
          else
            failed << minion_id
            Rails.logger.warn "Failed to delete orphaned key: #{minion_id}"
          end
        rescue StandardError => e
          Rails.logger.error "Error deleting orphaned key #{minion_id}: #{e.message}"
          failed << minion_id
        end
      end

      {
        success: failed.empty?,
        deleted_keys: deleted,
        failed_keys: failed,
        message: "Deleted #{deleted.count} orphaned key(s)#{failed.any? ? ", #{failed.count} failed" : ""}"
      }
    rescue StandardError => e
      Rails.logger.error "Error cleaning up orphaned keys: #{e.message}"
      {
        success: false,
        deleted_keys: [],
        failed_keys: [],
        message: "Error: #{e.message}"
      }
    end

    private

    # ===== THREAD-SAFE CACHE OPERATIONS =====
    # These private methods handle all interactions with Rails.cache
    # They provide fallback behavior if cache is unavailable

    # Read authentication token from cache
    # @return [String, nil] The authentication token or nil if not found/expired
    def read_token_from_cache
      begin
        Rails.cache.read(CACHE_KEY_TOKEN)
      rescue Redis::BaseError => e
        # Cache unavailable (Redis down) - log warning but don't crash
        Rails.logger.error "Redis cache unavailable when reading token: #{e.message}"
        Rails.logger.warn "Salt API will re-authenticate on each request until Redis is available"
        nil
      end
    end

    # Read token expiration time from cache
    # @return [Time, nil] The expiration time or nil if not found
    def read_expiry_from_cache
      begin
        Rails.cache.read(CACHE_KEY_EXPIRES_AT)
      rescue Redis::BaseError => e
        # Cache unavailable (Redis down) - log warning but don't crash
        Rails.logger.error "Redis cache unavailable when reading expiry: #{e.message}"
        nil
      end
    end

    # Write authentication token and expiry to cache
    # @param token [String] The authentication token
    # @param expires_at [Time] When the token expires
    def write_token_to_cache(token, expires_at)
      begin
        # Write token with TTL matching the expiration time
        # This ensures automatic cleanup and prevents stale tokens
        ttl = (expires_at - Time.current).to_i

        Rails.cache.write(CACHE_KEY_TOKEN, token, expires_in: ttl.seconds)
        Rails.cache.write(CACHE_KEY_EXPIRES_AT, expires_at, expires_in: ttl.seconds)

        Rails.logger.debug "Wrote Salt API token to cache with TTL: #{ttl}s"
      rescue Redis::BaseError => e
        # Cache unavailable (Redis down) - log error but allow authentication to succeed
        # The token will only be valid for this request, causing re-auth on next request
        Rails.logger.error "Redis cache unavailable when writing token: #{e.message}"
        Rails.logger.warn "Salt API authentication succeeded but token not cached - will re-authenticate on next request"
      end
    end

    # Build a comprehensive message about the removal process
    def build_removal_message(results)
      messages = []

      # Uninstall status
      if results[:uninstall]
        if results[:uninstall][:success]
          messages << "Salt minion uninstall initiated (running in background)"
        else
          messages << "Could not uninstall from server: #{results[:uninstall][:message]}"
        end
      end

      # Key deletion status
      if results[:delete_key]
        if results[:delete_key][:success]
          messages << "Minion key deleted from Salt master"
        else
          messages << "Could not delete key: #{results[:delete_key][:message]}"
        end
      end

      messages.join(". ")
    end
  end
end
