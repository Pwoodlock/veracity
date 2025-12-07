# frozen_string_literal: true

# Health check endpoint for application monitoring
# Returns JSON status with individual component checks
class HealthController < ActionController::Base
  # Skip authentication for health checks (used by load balancers, monitoring)
  skip_before_action :verify_authenticity_token

  # Status constants
  STATUS_HEALTHY = 'healthy'
  STATUS_DEGRADED = 'degraded'
  STATUS_UNHEALTHY = 'unhealthy'

  # Critical checks that determine overall health
  CRITICAL_CHECKS = %i[database].freeze

  # Disk usage thresholds
  DISK_WARNING_PERCENT = 80
  DISK_CRITICAL_PERCENT = 90

  def show
    checks = perform_checks
    overall_status = determine_overall_status(checks)
    http_status = overall_status == STATUS_UNHEALTHY ? :service_unavailable : :ok

    response_body = {
      status: overall_status,
      timestamp: Time.current.iso8601,
      version: Veracity::VERSION,
      build_id: Veracity::BUILD_ID,
      checks: checks
    }

    render json: response_body, status: http_status
  end

  private

  def perform_checks
    {
      database: check_database,
      redis: check_redis,
      salt: check_salt,
      disk: check_disk
    }
  end

  def check_database
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ActiveRecord::Base.connection.execute('SELECT 1')
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    {
      status: STATUS_HEALTHY,
      message: 'Database connection successful',
      response_time_ms: elapsed_ms
    }
  rescue StandardError => e
    {
      status: STATUS_UNHEALTHY,
      message: "Database connection failed: #{e.message}"
    }
  end

  def check_redis
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    redis_client = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'))
    redis_client.ping
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    {
      status: STATUS_HEALTHY,
      message: 'Redis connection successful',
      response_time_ms: elapsed_ms
    }
  rescue StandardError => e
    {
      status: STATUS_DEGRADED,
      message: "Redis connection failed: #{e.message}"
    }
  ensure
    redis_client&.close
  end

  def check_salt
    salt_api_url = ENV.fetch('SALT_API_URL', nil)

    unless salt_api_url.present?
      return {
        status: STATUS_DEGRADED,
        message: 'Salt API URL not configured'
      }
    end

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    uri = URI.parse(salt_api_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 5
    http.read_timeout = 5
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    request = Net::HTTP::Get.new('/')
    response = http.request(request)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

    if response.code.to_i < 500
      {
        status: STATUS_HEALTHY,
        message: 'Salt API reachable',
        response_time_ms: elapsed_ms
      }
    else
      {
        status: STATUS_DEGRADED,
        message: "Salt API returned status #{response.code}"
      }
    end
  rescue StandardError => e
    {
      status: STATUS_DEGRADED,
      message: "Salt API check failed: #{e.message}"
    }
  end

  def check_disk
    df_output = `df -P / 2>/dev/null`.strip
    lines = df_output.split("\n")

    if lines.length < 2
      return {
        status: STATUS_DEGRADED,
        message: 'Could not read disk information'
      }
    end

    # Parse df output: Filesystem 1024-blocks Used Available Capacity Mounted
    parts = lines[1].split
    total_kb = parts[1].to_i
    used_kb = parts[2].to_i
    available_kb = parts[3].to_i
    usage_percent = ((used_kb.to_f / total_kb) * 100).round(1)

    status = if usage_percent >= DISK_CRITICAL_PERCENT
               STATUS_UNHEALTHY
             elsif usage_percent >= DISK_WARNING_PERCENT
               STATUS_DEGRADED
             else
               STATUS_HEALTHY
             end

    {
      status: status,
      message: "Disk usage: #{usage_percent}%",
      total_gb: (total_kb / 1_048_576.0).round(2),
      available_gb: (available_kb / 1_048_576.0).round(2),
      usage_percent: usage_percent
    }
  rescue StandardError => e
    {
      status: STATUS_DEGRADED,
      message: "Disk check failed: #{e.message}"
    }
  end

  def determine_overall_status(checks)
    critical_statuses = checks.slice(*CRITICAL_CHECKS).values.map { |c| c[:status] }
    all_statuses = checks.values.map { |c| c[:status] }

    if critical_statuses.include?(STATUS_UNHEALTHY)
      STATUS_UNHEALTHY
    elsif all_statuses.include?(STATUS_UNHEALTHY)
      STATUS_DEGRADED
    elsif all_statuses.include?(STATUS_DEGRADED)
      STATUS_DEGRADED
    else
      STATUS_HEALTHY
    end
  end
end
