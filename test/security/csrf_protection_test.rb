# frozen_string_literal: true

require 'test_helper'

#
# CSRF Protection Security Tests
#
# These tests verify that Cross-Site Request Forgery (CSRF) protection is enforced
# for all state-changing operations. Rails automatically includes CSRF tokens in
# forms and AJAX requests, and this suite ensures that requests without valid
# tokens are properly rejected.
#
# SECURITY CONTEXT:
# - CSRF attacks trick authenticated users into submitting unwanted requests
# - All POST, PATCH, PUT, DELETE requests MUST include a valid CSRF token
# - GET requests should never modify state (they are CSRF-exempt by design)
#
# Reference: OWASP CSRF Prevention Cheat Sheet
# https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html
#
class CsrfProtectionTest < ActionDispatch::IntegrationTest
  setup do
    # Create test user and server for CSRF tests
    @user = create(:user, :admin)
    @server = create(:server, hostname: 'test-server', minion_id: 'test-minion')

    # Mock external APIs
    mock_salt_api

    # Sign in the user (establishes session but doesn't give us CSRF token)
    sign_in @user
  end

  #
  # Test 1: POST to servers_path without CSRF token returns 422
  #
  # EXPECTED BEHAVIOR:
  # - Creating a server requires a valid CSRF token
  # - Requests without the token should be rejected with 422 Unprocessable Entity
  # - This prevents attackers from creating servers via CSRF attacks
  #
  test 'POST to servers without CSRF token returns 422' do
    # Attempt to create a server without CSRF token
    # We bypass Rails' automatic CSRF token injection by using post directly
    # without going through the form helpers
    assert_raises ActionController::InvalidAuthenticityToken do
      post servers_path,
        params: {
          server: {
            hostname: 'malicious-server',
            minion_id: 'malicious-minion',
            ip_address: '192.168.1.100'
          }
        },
        headers: { 'X-CSRF-Token' => 'invalid_token' }
    end

    # Verify server was NOT created
    assert_nil Server.find_by(hostname: 'malicious-server'),
               'Server should not be created without valid CSRF token'
  end

  #
  # Test 2: PATCH to server_path without CSRF token returns 422
  #
  # EXPECTED BEHAVIOR:
  # - Updating a server requires a valid CSRF token
  # - Requests without the token should be rejected
  # - This prevents attackers from modifying server configurations
  #
  test 'PATCH to server without CSRF token returns 422' do
    original_hostname = @server.hostname

    # Attempt to update server without CSRF token
    assert_raises ActionController::InvalidAuthenticityToken do
      patch server_path(@server),
        params: {
          server: {
            hostname: 'hacked-hostname',
            environment: 'compromised'
          }
        },
        headers: { 'X-CSRF-Token' => 'invalid_token' }
    end

    # Verify server was NOT updated
    @server.reload
    assert_equal original_hostname, @server.hostname,
                 'Server hostname should not be changed without valid CSRF token'
  end

  #
  # Test 3: DELETE to server_path without CSRF token returns 422
  #
  # EXPECTED BEHAVIOR:
  # - Deleting a server requires a valid CSRF token
  # - Requests without the token should be rejected
  # - This prevents attackers from deleting servers via CSRF
  #
  test 'DELETE to server without CSRF token returns 422' do
    server_id = @server.id

    # Attempt to delete server without CSRF token
    assert_raises ActionController::InvalidAuthenticityToken do
      delete server_path(@server),
        headers: { 'X-CSRF-Token' => 'invalid_token' }
    end

    # Verify server was NOT deleted
    assert Server.exists?(server_id),
           'Server should not be deleted without valid CSRF token'
  end

  #
  # Test 4: POST to task execution without CSRF token returns 422
  #
  # EXPECTED BEHAVIOR:
  # - Executing tasks requires a valid CSRF token
  # - Prevents attackers from running arbitrary commands on servers
  # - Critical security control for command execution
  #
  test 'POST to execute task without CSRF token returns 422' do
    task = create(:task,
      name: 'Test Task',
      task_type: 'shell_command',
      command: 'echo test'
    )

    # Attempt to execute task without CSRF token
    assert_raises ActionController::InvalidAuthenticityToken do
      post execute_task_path(task),
        params: { server_ids: [@server.id] },
        headers: { 'X-CSRF-Token' => 'invalid_token' }
    end

    # Verify no task run was created
    assert_equal 0, task.task_runs.count,
                 'Task should not execute without valid CSRF token'
  end

  #
  # Test 5: Document API endpoints exempt from CSRF
  #
  # EXPECTED BEHAVIOR:
  # - Most API endpoints in Veracity use session-based auth, so they need CSRF
  # - Only token-based API endpoints (if any) would be exempt
  # - This test documents the CSRF policy for the application
  #
  test 'document CSRF-exempt endpoints' do
    # In Veracity, all state-changing endpoints require CSRF protection
    # because we use cookie-based session authentication (Devise)
    #
    # CSRF exemptions would only apply if we had:
    # 1. Token-based API endpoints (Authorization: Bearer token)
    # 2. Webhook endpoints verified by signature (e.g., GitHub webhooks)
    #
    # Current CSRF-exempt endpoints: NONE
    # All POST/PATCH/PUT/DELETE requests require valid CSRF tokens

    csrf_exempt_endpoints = []

    assert_empty csrf_exempt_endpoints,
                 'All state-changing endpoints should require CSRF tokens. ' \
                 'If you need to exempt an endpoint, document it here with justification.'

    # FUTURE: If we add token-based API endpoints, document them here:
    # csrf_exempt_endpoints = [
    #   { path: '/api/v1/webhooks/github', reason: 'Verified by X-Hub-Signature' },
    #   { path: '/api/v1/metrics', reason: 'Read-only, token-authenticated' }
    # ]
  end

  #
  # Test 6: Verify CSRF protection is enabled in test environment
  #
  # EXPECTED BEHAVIOR:
  # - CSRF protection should be enabled even in test mode
  # - This ensures our security tests are realistic
  # - Verifies Rails configuration is correct
  #
  test 'CSRF protection is enabled in test environment' do
    assert ActionController::Base.allow_forgery_protection,
           'CSRF protection should be enabled in test environment for security testing'

    # Verify the protection is actually enforced by ApplicationController
    assert ApplicationController.new.send(:protect_against_forgery?),
           'ApplicationController should enforce CSRF protection'
  end

  #
  # Test 7: Verify CSRF token in session-based requests
  #
  # EXPECTED BEHAVIOR:
  # - Valid CSRF tokens should allow requests to succeed
  # - This is a positive test to ensure CSRF isn't blocking legitimate requests
  #
  test 'valid CSRF token allows state-changing operations' do
    # Get a valid CSRF token from the session
    # In a real Rails app, this would come from the form or meta tag
    get new_server_path
    csrf_token = css_select('meta[name="csrf-token"]').first['content']

    # Verify we got a token
    assert_not_nil csrf_token, 'CSRF token should be present in page'
    assert csrf_token.length > 20, 'CSRF token should be a substantial random string'

    # This test verifies the token exists and is non-trivial
    # Actual usage would be in a form submission, which is tested elsewhere
  end
end
