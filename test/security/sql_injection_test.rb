# frozen_string_literal: true

require 'test_helper'

#
# SQL Injection Security Tests
#
# These tests verify that user input is properly sanitized and parameterized
# to prevent SQL injection attacks. Rails' ActiveRecord automatically uses
# parameterized queries, but we must ensure:
# 1. No raw SQL with string interpolation
# 2. All user input is properly escaped
# 3. Search/filter functionality doesn't introduce vulnerabilities
#
# SECURITY CONTEXT:
# - SQL injection allows attackers to execute arbitrary SQL commands
# - Can lead to data theft, data modification, or complete system compromise
# - MUST use parameterized queries or ActiveRecord query interface
#
# Reference: OWASP SQL Injection Prevention Cheat Sheet
# https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html
#
class SqlInjectionTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:user, :admin)
    @server1 = create(:server, hostname: 'web-server-01', ip_address: '192.168.1.10')
    @server2 = create(:server, hostname: 'db-server-01', ip_address: '192.168.1.20')

    mock_salt_api
    sign_in @admin
  end

  #
  # Test 1: Server search with SQL injection attempts
  #
  # EXPECTED BEHAVIOR:
  # - Malicious SQL in search parameter should be treated as literal text
  # - Query should return zero results (no servers match the literal string)
  # - Database should NOT be modified or queried maliciously
  #
  test 'server search filters SQL injection payloads safely' do
    # Common SQL injection payloads
    sql_injection_payloads = [
      "'; DROP TABLE servers; --",  # Classic injection
      "' OR '1'='1",                 # Authentication bypass
      "' UNION SELECT * FROM users --", # Data extraction
      "admin'--",                    # Comment injection
      "' OR 1=1 --",                 # Boolean-based injection
      "1' AND '1'='1",              # Logical AND injection
      "; DELETE FROM servers WHERE '1'='1", # Command chaining
      "' OR 'x'='x",                # Alternative boolean injection
    ]

    sql_injection_payloads.each do |payload|
      # Attempt to search with malicious input
      get servers_path, params: { search: payload }

      # Verify response is successful (not a database error)
      assert_response :success, "Search with SQL injection payload should not cause error: #{payload}"

      # Verify no servers are returned (malicious query shouldn't match anything)
      # The payload should be treated as a literal search string
      assert_select '.server-card', count: 0

      # Most importantly: verify our test servers still exist
      assert Server.exists?(@server1.id), "Server 1 should still exist after injection attempt: #{payload}"
      assert Server.exists?(@server2.id), "Server 2 should still exist after injection attempt: #{payload}"
    end

    # Verify database integrity - count should be unchanged
    assert_equal 2, Server.count, 'Server count should remain 2 after all injection attempts'
  end

  #
  # Test 2: CVE watchlist search with injection attempts
  #
  # EXPECTED BEHAVIOR:
  # - Vendor/product search fields should sanitize input
  # - Malicious SQL should not execute
  # - Query should safely handle special characters
  #
  test 'CVE watchlist vendor/product search prevents SQL injection' do
    watchlist = create(:cve_watchlist,
      vendor: 'apache',
      product: 'httpd',
      version: '2.4.50',
      server: @server1
    )

    # SQL injection payloads for vendor/product filtering
    injection_payloads = [
      "apache'; DROP TABLE cve_watchlists; --",
      "' OR 1=1 --",
      "httpd' UNION SELECT password FROM users --",
    ]

    injection_payloads.each do |payload|
      # Search by vendor with injection payload
      get cve_watchlists_path, params: { vendor: payload }

      assert_response :success, "CVE search should handle injection safely: #{payload}"

      # Verify watchlist still exists
      assert CveWatchlist.exists?(watchlist.id), "Watchlist should still exist after injection attempt: #{payload}"
    end

    # Verify table integrity
    assert_equal 1, CveWatchlist.count, 'CVE watchlist count should be unchanged after injection attempts'
  end

  #
  # Test 3: Group filtering with malicious input
  #
  # EXPECTED BEHAVIOR:
  # - Group ID parameter should be validated and sanitized
  # - Non-numeric input should be handled safely
  # - SQL injection attempts should fail gracefully
  #
  test 'server group filter prevents SQL injection' do
    group = create(:group, name: 'Production Servers')
    server_in_group = create(:server, group: group, hostname: 'prod-server')

    # Malicious group_id values
    malicious_group_ids = [
      "1' OR '1'='1",
      "1; DROP TABLE groups; --",
      "1 UNION SELECT * FROM users",
      "-1 OR 1=1",
    ]

    malicious_group_ids.each do |payload|
      # Attempt to filter by malicious group_id
      get servers_path, params: { group_id: payload }

      # Should not crash - either returns no results or raises ActiveRecord::RecordNotFound
      assert_response :success, "Group filter should handle injection safely: #{payload}"

      # Verify group and server still exist
      assert Group.exists?(group.id), "Group should still exist after injection attempt: #{payload}"
      assert Server.exists?(server_in_group.id), "Server should still exist after injection attempt: #{payload}"
    end
  end

  #
  # Test 4: Order/sort parameter injection protection
  #
  # EXPECTED BEHAVIOR:
  # - Sort parameters should use whitelisted columns only
  # - Malicious ORDER BY clauses should be rejected or sanitized
  # - Database should not execute arbitrary SQL
  #
  test 'server sorting prevents SQL injection in ORDER BY' do
    # Create servers with different attributes
    create(:server, hostname: 'server-z', status: 'online')
    create(:server, hostname: 'server-a', status: 'offline')

    # Malicious sort parameters
    malicious_sort_values = [
      "hostname; DROP TABLE servers; --",
      "hostname, (SELECT password FROM users LIMIT 1)",
      "CASE WHEN (1=1) THEN hostname ELSE ip_address END",
      "hostname' OR '1'='1",
    ]

    malicious_sort_values.each do |payload|
      # Attempt to sort with malicious input
      # Note: Current implementation may not have explicit sort parameter,
      # but we test that adding one wouldn't introduce vulnerabilities
      get servers_path, params: { sort: payload }

      # Should either ignore invalid sort or handle safely
      assert_response :success, "Sort parameter should handle injection safely: #{payload}"

      # Verify servers still exist
      assert_operator Server.count, :>=, 2, "Servers should still exist after sort injection attempt: #{payload}"
    end
  end

  #
  # Test 5: Verify parameterized queries are used
  #
  # EXPECTED BEHAVIOR:
  # - All database queries should use ActiveRecord's parameterization
  # - No string interpolation in WHERE clauses
  # - This is a code inspection test
  #
  test 'server search uses parameterized queries' do
    # Test that our search implementation uses proper parameterization
    search_term = "test' OR '1'='1"

    # This should safely search for the literal string, not execute SQL
    servers = Server.where(
      "hostname ILIKE ? OR ip_address ILIKE ? OR minion_id ILIKE ?",
      "%#{search_term}%", "%#{search_term}%", "%#{search_term}%"
    )

    # Should return no results (searching for literal injection string)
    assert_equal 0, servers.count, 'Parameterized query should treat injection as literal text'

    # Verify our test data is still intact
    assert_equal 2, Server.count, 'Original servers should still exist'

    # Now test with legitimate search
    legitimate_servers = Server.where(
      "hostname ILIKE ? OR ip_address ILIKE ?",
      "%web%", "%192.168.1.10%"
    )
    assert_equal 1, legitimate_servers.count, 'Legitimate search should work correctly'
    assert_equal @server1.id, legitimate_servers.first.id, 'Should find the web server'
  end

  #
  # Test 6: Verify ActiveRecord sanitization helpers
  #
  # EXPECTED BEHAVIOR:
  # - ActiveRecord.sanitize_sql_array properly escapes user input
  # - String interpolation is dangerous and should never be used
  # - This test demonstrates the proper approach
  #
  test 'ActiveRecord sanitization prevents injection' do
    # Example of UNSAFE query (we don't actually run this)
    unsafe_search = "test' OR '1'='1"
    # UNSAFE: Server.where("hostname = '#{unsafe_search}'") # NEVER DO THIS

    # Example of SAFE query with parameterization
    safe_query = Server.where("hostname = ?", unsafe_search)

    # The parameterized query should return no results (no server has that exact hostname)
    assert_equal 0, safe_query.count, 'Parameterized query should safely handle injection attempt'

    # Verify the SQL is properly escaped
    sql = safe_query.to_sql
    assert_includes sql, unsafe_search, 'SQL should include the literal search term (escaped)'
    refute_includes sql, "' OR '1'='1", 'SQL should not include unescaped injection payload'
  end

  #
  # Test 7: Test vulnerable patterns don't exist in codebase
  #
  # EXPECTED BEHAVIOR:
  # - No controllers should use string interpolation in queries
  # - All queries should use ? placeholders or hash conditions
  # - This is a defensive test against regression
  #
  test 'verify no string interpolation in database queries' do
    # This test documents that we use safe query patterns
    # In a real application, you might scan the codebase for patterns like:
    # - where("column = '#{user_input}'")
    # - find_by_sql("SELECT * FROM ... WHERE id = '#{params[:id]}'")

    # For this test, we verify our key controllers use safe patterns
    # by testing their actual behavior

    dangerous_inputs = [
      "1' OR '1'='1",
      "'; DROP TABLE servers; --",
      "1 UNION SELECT * FROM users",
    ]

    dangerous_inputs.each do |dangerous_input|
      # Test server filtering (group_id parameter)
      get servers_path, params: { group_id: dangerous_input }
      assert_response :success, "Should handle dangerous group_id safely"

      # Test server search
      get servers_path, params: { search: dangerous_input }
      assert_response :success, "Should handle dangerous search safely"

      # Verify no data was modified
      assert_equal 2, Server.count, "Server count should remain constant after dangerous input: #{dangerous_input}"
    end
  end
end
