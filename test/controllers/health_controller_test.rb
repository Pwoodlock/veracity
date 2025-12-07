# frozen_string_literal: true

require 'test_helper'

class HealthControllerTest < ActionDispatch::IntegrationTest
  test 'health endpoint returns healthy when all checks pass' do
    # Mock Redis to succeed
    mock_redis = mock('redis')
    mock_redis.stubs(:ping).returns('PONG')
    mock_redis.stubs(:close)
    Redis.stubs(:new).returns(mock_redis)

    # Set Salt API URL env var
    ENV.stubs(:fetch).with('SALT_API_URL', nil).returns('https://localhost:8000')
    ENV.stubs(:fetch).with('REDIS_URL', 'redis://localhost:6379').returns('redis://localhost:6379')

    # Mock Net::HTTP for Salt API check
    mock_response = mock('response')
    mock_response.stubs(:code).returns('200')

    mock_http = mock('http')
    mock_http.stubs(:use_ssl=)
    mock_http.stubs(:open_timeout=)
    mock_http.stubs(:read_timeout=)
    mock_http.stubs(:verify_mode=)
    mock_http.stubs(:request).returns(mock_response)
    Net::HTTP.stubs(:new).returns(mock_http)

    get health_check_path

    assert_response :success

    json_response = JSON.parse(response.body)
    assert_equal 'healthy', json_response['status']
    assert_includes json_response.keys, 'timestamp'
    assert_includes json_response.keys, 'version'
    assert_includes json_response.keys, 'checks'

    # Verify individual checks are present
    checks = json_response['checks']
    assert_includes checks.keys, 'database'
    assert_includes checks.keys, 'redis'
    assert_includes checks.keys, 'salt'
    assert_includes checks.keys, 'disk'

    # Database should be healthy
    assert_equal 'healthy', checks['database']['status']
  end

  test 'health endpoint returns degraded when optional checks fail' do
    # Mock Redis to fail (optional service)
    Redis.stubs(:new).raises(Redis::CannotConnectError.new('Connection refused'))

    # Mock Salt API URL as not configured (optional service)
    ENV.stubs(:fetch).with('SALT_API_URL', nil).returns(nil)
    ENV.stubs(:fetch).with('REDIS_URL', 'redis://localhost:6379').returns('redis://localhost:6379')

    get health_check_path

    assert_response :success

    json_response = JSON.parse(response.body)
    assert_equal 'degraded', json_response['status']

    checks = json_response['checks']
    # Database should still be healthy (critical check)
    assert_equal 'healthy', checks['database']['status']
    # Redis should be degraded
    assert_equal 'degraded', checks['redis']['status']
    # Salt should be degraded (not configured)
    assert_equal 'degraded', checks['salt']['status']
  end

  test 'health endpoint returns unhealthy when critical checks fail' do
    # Mock database connection to fail
    ActiveRecord::Base.connection.stubs(:execute).raises(
      ActiveRecord::ConnectionNotEstablished.new('Database is down')
    )

    # Mock Redis to succeed
    mock_redis = mock('redis')
    mock_redis.stubs(:ping).returns('PONG')
    mock_redis.stubs(:close)
    Redis.stubs(:new).returns(mock_redis)

    # Mock Salt config as not configured
    ENV.stubs(:fetch).with('SALT_API_URL', nil).returns(nil)
    ENV.stubs(:fetch).with('REDIS_URL', 'redis://localhost:6379').returns('redis://localhost:6379')

    get health_check_path

    assert_response :service_unavailable

    json_response = JSON.parse(response.body)
    assert_equal 'unhealthy', json_response['status']

    checks = json_response['checks']
    # Database should be unhealthy (critical check)
    assert_equal 'unhealthy', checks['database']['status']
    assert_match(/Database connection failed/, checks['database']['message'])
  end

  test 'health endpoint is accessible without authentication' do
    # Mock Redis to succeed
    mock_redis = mock('redis')
    mock_redis.stubs(:ping).returns('PONG')
    mock_redis.stubs(:close)
    Redis.stubs(:new).returns(mock_redis)

    # Stub Salt API URL to nil (skip Salt check)
    ENV.stubs(:fetch).with('SALT_API_URL', nil).returns(nil)
    ENV.stubs(:fetch).with('REDIS_URL', 'redis://localhost:6379').returns('redis://localhost:6379')

    # This test verifies the endpoint does not require login
    # by not signing in before making the request
    get health_check_path

    # Should not redirect to login page
    assert_not_equal 302, response.status
    assert_not response.redirect?

    # Should return JSON
    assert_equal 'application/json; charset=utf-8', response.content_type
  end

  test 'health endpoint includes version information' do
    # Mock dependencies to avoid connection failures
    mock_redis = mock('redis')
    mock_redis.stubs(:ping).returns('PONG')
    mock_redis.stubs(:close)
    Redis.stubs(:new).returns(mock_redis)
    ENV.stubs(:fetch).with('SALT_API_URL', nil).returns(nil)
    ENV.stubs(:fetch).with('REDIS_URL', 'redis://localhost:6379').returns('redis://localhost:6379')

    get health_check_path

    json_response = JSON.parse(response.body)
    assert_equal Veracity::VERSION, json_response['version']
    assert_includes json_response.keys, 'build_id'
    assert_includes json_response.keys, 'timestamp'

    # Timestamp should be valid ISO8601
    timestamp = json_response['timestamp']
    assert_nothing_raised { Time.iso8601(timestamp) }
  end
end
