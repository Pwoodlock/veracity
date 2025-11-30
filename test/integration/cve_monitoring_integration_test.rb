# frozen_string_literal: true

require "test_helper"

# Integration tests for CVE Monitoring Service
# These tests verify the Python script and API integration work correctly
# They require Python 3.8+ and pyvulnerabilitylookup to be installed
class CveMonitoringIntegrationTest < ActionDispatch::IntegrationTest
  # Skip these tests if Python/pyvulnerabilitylookup is not available
  def setup
    skip_unless_python_available
  end

  # ===========================================
  # Helper Methods
  # ===========================================

  def python_available?
    # Check for Python 3
    return false unless system("python3 --version > /dev/null 2>&1")

    # Check for pyvulnerabilitylookup
    system("python3 -c 'import pyvulnerabilitylookup' 2>/dev/null")
  end

  def skip_unless_python_available
    skip "Python 3 with pyvulnerabilitylookup not available" unless python_available?
  end

  # ===========================================
  # API Connection Tests
  # ===========================================

  test "can connect to vulnerability lookup API" do
    result = CveMonitoringService.test_api_connection

    assert result[:success], "API connection failed: #{result[:message]}"
    assert_includes result[:message], "Connection successful"
  end

  test "API returns valid info structure" do
    result = CveMonitoringService.test_api_connection

    assert result[:success]
    # The info hash should be present (may be empty but not nil)
    assert_not_nil result[:message]
  end

  # ===========================================
  # CVE Lookup Tests
  # ===========================================

  test "can fetch vulnerability details for known CVE" do
    # Use a well-known CVE that should always exist
    cve_id = 'CVE-2021-44228'  # Log4Shell

    result = CveMonitoringService.get_vulnerability_details(cve_id)

    assert_not_nil result, "Expected to get vulnerability details"
    # Result should have some standard CVE fields
    assert result.key?('cveMetadata') || result.key?('id'),
           "Expected CVE data structure, got: #{result.keys.inspect}"
  end

  test "can fetch vulnerabilities by vendor and product" do
    # Use a common product that should have vulnerabilities
    vulnerabilities = CveMonitoringService.fetch_vendor_product_vulnerabilities('apache', 'http_server')

    assert_kind_of Array, vulnerabilities
    # Apache HTTP Server should have known vulnerabilities
    assert vulnerabilities.any?, "Expected to find vulnerabilities for Apache HTTP Server"

    # Check structure of returned data
    first_vuln = vulnerabilities.first
    assert first_vuln.key?('cve_id'), "Expected cve_id in vulnerability data"
  end

  # ===========================================
  # EPSS Score Tests
  # ===========================================

  test "can fetch EPSS score for CVE" do
    # Use a CVE that should have an EPSS score
    cve_id = 'CVE-2021-44228'

    score = CveMonitoringService.get_epss_score(cve_id)

    # EPSS score may be nil for some CVEs, but the call should succeed
    # If we get a score, it should be between 0 and 1
    if score
      assert score >= 0 && score <= 1, "EPSS score should be between 0 and 1, got: #{score}"
    end
  end

  # ===========================================
  # CISA KEV Tests
  # ===========================================

  test "can fetch CISA known exploited vulnerabilities" do
    result = CveMonitoringService.get_exploited_vulnerabilities

    # Result should be an array (may be empty but should not error)
    assert_kind_of Array, result
  end

  # ===========================================
  # CPE Lookup Tests
  # ===========================================

  test "can check vulnerabilities by CPE" do
    # Use a CPE for Apache HTTP Server
    cpe = 'cpe:2.3:a:apache:http_server:2.4.51:*:*:*:*:*:*:*'

    result = CveMonitoringService.check_cpe(cpe)

    # Result should be an array
    assert_kind_of Array, result
  end

  # ===========================================
  # Error Handling Tests
  # ===========================================

  test "handles invalid CVE ID gracefully" do
    # This should not raise an exception, just return empty/nil result
    result = CveMonitoringService.get_vulnerability_details('INVALID-CVE-FORMAT')

    # API may return empty result or error in the response
    # The important thing is it doesn't crash
    assert_not_nil result
  end

  test "handles non-existent vendor product gracefully" do
    vulnerabilities = CveMonitoringService.fetch_vendor_product_vulnerabilities(
      'nonexistent_vendor_xyz_123',
      'nonexistent_product_xyz_123'
    )

    # Should return empty array, not crash
    assert_kind_of Array, vulnerabilities
    assert_empty vulnerabilities
  end
end
