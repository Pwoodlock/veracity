# frozen_string_literal: true

require "test_helper"

class CveMonitoringServiceTest < ActiveSupport::TestCase
  setup do
    # Mock SystemSetting to return test values
    SystemSetting.stubs(:get).with('vulnerability_lookup_url', anything).returns('https://vulnerability.circl.lu')
    SystemSetting.stubs(:get).with('vulnerability_lookup_python_path', anything).returns(python_path)
    SystemSetting.stubs(:get).with('vulnerability_lookup_timeout', anything).returns(30)
    SystemSetting.stubs(:get).with('vulnerability_lookup_enabled', anything).returns(true)
    SystemSetting.stubs(:get).with('vulnerability_lookup_notification_threshold', anything).returns('high')
  end

  # Helper to find Python - checks both venv and system Python
  def python_path
    paths = [
      '/opt/veracity/app/integrations_venv/bin/python',
      '/usr/bin/python3',
      'python3'
    ]
    paths.find { |p| File.exist?(p) || system("which #{p} > /dev/null 2>&1") } || 'python3'
  end

  # Helper to check if pyvulnerabilitylookup is available
  def pyvulnerabilitylookup_available?
    system("#{python_path} -c 'import pyvulnerabilitylookup' 2>/dev/null")
  end

  # ===========================================
  # Unit Tests (with mocked Python execution)
  # ===========================================

  test "test_api_connection returns success hash on successful connection" do
    # Mock the Python execution
    CveMonitoringService.stubs(:execute_python_script)
      .with(['test_connection'])
      .returns({ 'status' => 'ok', 'root_url' => 'https://vulnerability.circl.lu', 'info' => {} })

    result = CveMonitoringService.test_api_connection

    assert result[:success], "Expected success to be true"
    assert_includes result[:message], "Connection successful"
  end

  test "test_api_connection returns failure hash on connection error" do
    # Mock a Python error
    CveMonitoringService.stubs(:execute_python_script)
      .with(['test_connection'])
      .raises(CveMonitoringService::PythonError.new("Connection refused"))

    result = CveMonitoringService.test_api_connection

    assert_not result[:success], "Expected success to be false"
    assert_includes result[:message], "Connection failed"
  end

  test "get_vulnerability_details calls Python with correct command" do
    cve_id = 'CVE-2024-1234'
    expected_result = { 'cveMetadata' => { 'cveId' => cve_id } }

    CveMonitoringService.stubs(:execute_python_script)
      .with(['check_cve', cve_id])
      .returns(expected_result)

    result = CveMonitoringService.get_vulnerability_details(cve_id)

    assert_equal expected_result, result
  end

  test "fetch_vendor_product_vulnerabilities parses API response correctly" do
    # Mock the API response format from PyVulnerabilityLookup
    api_response = {
      'results' => {
        'fkie_nvd' => [
          ['CVE-2024-0001', {
            'cveMetadata' => { 'cveId' => 'CVE-2024-0001' },
            'containers' => {
              'cna' => {
                'descriptions' => [{ 'lang' => 'en', 'value' => 'Test vulnerability' }],
                'metrics' => [{ 'cvssV3_1' => { 'baseScore' => 7.5, 'baseSeverity' => 'HIGH' } }]
              }
            }
          }]
        ]
      },
      'total_count' => 1
    }

    CveMonitoringService.stubs(:execute_python_script)
      .with(['check_vendor_product', 'test_vendor', 'test_product'])
      .returns(api_response)

    vulnerabilities = CveMonitoringService.fetch_vendor_product_vulnerabilities('test_vendor', 'test_product')

    assert_kind_of Array, vulnerabilities
    assert_equal 1, vulnerabilities.length
    assert_equal 'CVE-2024-0001', vulnerabilities.first['cve_id']
  end

  test "fetch_vendor_product_vulnerabilities filters by since date" do
    # Mock response with multiple CVEs
    api_response = {
      'results' => {
        'fkie_nvd' => [
          ['CVE-2024-0001', {
            'cveMetadata' => { 'cveId' => 'CVE-2024-0001', 'datePublished' => '2024-01-15T00:00:00Z' }
          }],
          ['CVE-2024-0002', {
            'cveMetadata' => { 'cveId' => 'CVE-2024-0002', 'datePublished' => '2024-01-01T00:00:00Z' }
          }]
        ]
      }
    }

    CveMonitoringService.stubs(:execute_python_script).returns(api_response)

    # Filter for CVEs after Jan 10, 2024
    since_date = DateTime.new(2024, 1, 10)
    vulnerabilities = CveMonitoringService.fetch_vendor_product_vulnerabilities('vendor', 'product', since: since_date)

    # Should only return CVE-2024-0001 (published Jan 15)
    assert_equal 1, vulnerabilities.length
    assert_equal 'CVE-2024-0001', vulnerabilities.first['cve_id']
  end

  test "get_epss_score returns score from API" do
    CveMonitoringService.stubs(:execute_python_script)
      .with(['get_epss', 'CVE-2024-1234'])
      .returns({ 'epss_score' => 0.45 })

    score = CveMonitoringService.get_epss_score('CVE-2024-1234')

    assert_equal 0.45, score
  end

  test "check_cpe returns vulnerabilities for CPE string" do
    cpe = 'cpe:2.3:a:apache:http_server:2.4.51:*:*:*:*:*:*:*'
    expected = { 'vulnerabilities' => ['CVE-2024-0001'] }

    CveMonitoringService.stubs(:execute_python_script)
      .with(['check_cpe', cpe])
      .returns(expected)

    result = CveMonitoringService.check_cpe(cpe)

    assert_equal ['CVE-2024-0001'], result
  end

  # ===========================================
  # Data Extraction Tests
  # ===========================================

  test "extracts CVE ID from CVElistV5 format" do
    vuln_data = { 'cveMetadata' => { 'cveId' => 'CVE-2024-1234' } }
    result = CveMonitoringService.send(:extract_cve_id, vuln_data, 'fallback')
    assert_equal 'CVE-2024-1234', result
  end

  test "extracts CVE ID from NVD format" do
    vuln_data = { 'id' => 'CVE-2024-5678' }
    result = CveMonitoringService.send(:extract_cve_id, vuln_data, 'fallback')
    assert_equal 'CVE-2024-5678', result
  end

  test "extracts description from CVElistV5 format" do
    vuln_data = {
      'containers' => {
        'cna' => {
          'descriptions' => [
            { 'lang' => 'en', 'value' => 'English description' },
            { 'lang' => 'es', 'value' => 'Spanish description' }
          ]
        }
      }
    }
    result = CveMonitoringService.send(:extract_description, vuln_data)
    assert_equal 'English description', result
  end

  test "extracts CVSS score from CVElistV5 format" do
    vuln_data = {
      'containers' => {
        'cna' => {
          'metrics' => [{ 'cvssV3_1' => { 'baseScore' => 9.8 } }]
        }
      }
    }
    result = CveMonitoringService.send(:extract_cvss_score, vuln_data)
    assert_equal 9.8, result
  end

  test "determines severity from CVSS score" do
    assert_equal 'CRITICAL', CveMonitoringService.send(:determine_severity_from_score, 9.5)
    assert_equal 'HIGH', CveMonitoringService.send(:determine_severity_from_score, 8.0)
    assert_equal 'MEDIUM', CveMonitoringService.send(:determine_severity_from_score, 5.5)
    assert_equal 'LOW', CveMonitoringService.send(:determine_severity_from_score, 2.0)
    assert_equal 'UNKNOWN', CveMonitoringService.send(:determine_severity_from_score, nil)
  end

  # ===========================================
  # Notification Threshold Tests
  # ===========================================

  test "meets_threshold returns true when severity meets threshold" do
    assert CveMonitoringService.send(:meets_threshold?, 'CRITICAL', 'high')
    assert CveMonitoringService.send(:meets_threshold?, 'CRITICAL', 'critical')
    assert CveMonitoringService.send(:meets_threshold?, 'HIGH', 'high')
    assert CveMonitoringService.send(:meets_threshold?, 'HIGH', 'medium')
  end

  test "meets_threshold returns false when severity below threshold" do
    assert_not CveMonitoringService.send(:meets_threshold?, 'MEDIUM', 'high')
    assert_not CveMonitoringService.send(:meets_threshold?, 'LOW', 'critical')
    assert_not CveMonitoringService.send(:meets_threshold?, 'INFO', 'medium')
  end

  # ===========================================
  # Python Script Syntax Test
  # ===========================================

  test "embedded Python script has valid syntax" do
    # Extract the Python script and check syntax
    script = CveMonitoringService::PYTHON_SCRIPT

    # Write to temp file and check syntax
    require 'tempfile'
    Tempfile.create(['cve_test', '.py']) do |f|
      f.write(script)
      f.close

      # Use python3 -m py_compile to check syntax
      result = system("python3 -m py_compile #{f.path} 2>/dev/null")
      assert result, "Python script has syntax errors"
    end
  end
end
