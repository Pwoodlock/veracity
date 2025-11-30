# frozen_string_literal: true

require 'open3'
require 'json'

# Service to monitor CVEs using PyVulnerabilityLookup
class CveMonitoringService
  class CveMonitoringError < StandardError; end
  class PythonError < CveMonitoringError; end

  # Python script template for PyVulnerabilityLookup integration
  # Note: {{ROOT_URL}} will be replaced with actual URL at runtime
  PYTHON_SCRIPT = <<~PYTHON
    import sys
    import json
    from datetime import datetime, timedelta
    from pyvulnerabilitylookup import PyVulnerabilityLookup

    def main():
        try:
            # Initialize client with configurable root_url
            root_url = sys.argv[1] if len(sys.argv) > 1 else 'https://vulnerability.circl.lu'
            pvl = PyVulnerabilityLookup(root_url=root_url)

            # Parse command line arguments (sys.argv[1] is root_url, sys.argv[2] is command)
            if len(sys.argv) < 3:
                print(json.dumps({"error": "No command specified"}))
                sys.exit(1)

            command = sys.argv[2]

            if command == "check_cve":
                cve_id = sys.argv[3]
                result = pvl.get_vulnerability(cve_id)
                print(json.dumps(result))

            elif command == "check_vendor_product":
                vendor = sys.argv[3]
                product = sys.argv[4]
                # Get vulnerabilities for vendor/product
                result = pvl.get_vendor_product_vulnerabilities(vendor, product)
                print(json.dumps(result))

            elif command == "get_recent":
                # number parameter returns the last N vulnerabilities, not days
                num_vulns = int(sys.argv[3]) if len(sys.argv) > 3 else 100
                result = pvl.get_last(number=num_vulns)
                print(json.dumps(result))

            elif command == "get_cisa_kevs":
                # Get known exploited vulnerabilities
                result = pvl.get_cisa_kevs()
                print(json.dumps(result))

            elif command == "check_cpe":
                cpe = sys.argv[3]
                result = pvl.get_vulnerabilities_by_cpe(cpe)
                print(json.dumps(result))

            elif command == "get_epss":
                cve_id = sys.argv[3]
                result = pvl.get_epss(cve_id)
                print(json.dumps(result))

            elif command == "test_connection":
                # Test connection by checking API health/version
                # Note: is_up is a property, not a method
                is_up = pvl.is_up
                info = pvl.get_info() if is_up else {}
                # Get package version
                try:
                    from importlib.metadata import version as pkg_version
                    lib_version = pkg_version('pyvulnerabilitylookup')
                except Exception:
                    lib_version = 'unknown'
                print(json.dumps({"status": "ok" if is_up else "down", "root_url": root_url, "info": info, "library_version": lib_version}))

            else:
                print(json.dumps({"error": f"Unknown command: {command}"}))
                sys.exit(1)

        except Exception as e:
            print(json.dumps({"error": str(e)}))
            sys.exit(1)

    if __name__ == "__main__":
        main()
  PYTHON

  class << self
    # Check a specific watchlist for new vulnerabilities
    def check_watchlist(watchlist)
      Rails.logger.info "CveMonitoringService: Checking watchlist #{watchlist.display_name}"

      # Check if we have any existing alerts for this watchlist
      # If not, this is effectively a first check - fetch ALL vulnerabilities
      has_existing_alerts = VulnerabilityAlert.where(server_id: watchlist.server_id).exists?

      # Only filter by date if we already have alerts (incremental check)
      # Otherwise, fetch all known vulnerabilities for initial population
      since_date = has_existing_alerts ? watchlist.last_checked_at : nil

      vulnerabilities = fetch_vendor_product_vulnerabilities(
        watchlist.vendor,
        watchlist.product,
        since: since_date
      )

      new_alerts = []

      vulnerabilities.each do |vuln_data|
        cve_id = vuln_data['cve_id'] || vuln_data['id']
        next unless cve_id

        # Skip if we already have this alert
        existing = VulnerabilityAlert.find_by(
          cve_id: cve_id,
          server_id: watchlist.server_id
        )
        next if existing

        # Create new alert
        alert = create_alert_from_vulnerability(vuln_data, watchlist)
        new_alerts << alert if alert
      end

      # Update watchlist
      watchlist.mark_checked!
      watchlist.increment!(:hits_count, new_alerts.size)

      # Send notifications if new alerts found
      notify_new_vulnerabilities(new_alerts) if new_alerts.any?

      new_alerts
    rescue StandardError => e
      Rails.logger.error "CveMonitoringService: Error checking watchlist #{watchlist.id}: #{e.message}"
      raise
    end

    # Check all active watchlists
    def check_all_watchlists
      Rails.logger.info "CveMonitoringService: Starting watchlist check"

      results = {
        checked: 0,
        new_vulnerabilities: 0,
        errors: []
      }

      CveWatchlist.due_for_check.find_each do |watchlist|
        begin
          alerts = check_watchlist(watchlist)
          results[:checked] += 1
          results[:new_vulnerabilities] += alerts.size
        rescue StandardError => e
          results[:errors] << { watchlist_id: watchlist.id, error: e.message }
        end
      end

      Rails.logger.info "CveMonitoringService: Completed. Checked: #{results[:checked]}, New CVEs: #{results[:new_vulnerabilities]}"
      results
    end

    # Scan a server for vulnerabilities based on its OS and packages
    def scan_server(server)
      Rails.logger.info "CveMonitoringService: Scanning server #{server.hostname}"

      scan_history = CveScanHistory.create!(
        server: server,
        scan_started_at: Time.current,
        status: 'running'
      )

      begin
        # Get or create watchlists for this server
        create_server_watchlists(server)

        # Check each watchlist
        total_vulnerabilities = 0
        new_vulnerabilities = 0

        server.cve_watchlists.active.each do |watchlist|
          alerts = check_watchlist(watchlist)
          total_vulnerabilities += alerts.size
          new_vulnerabilities += alerts.size
        end

        # Update server
        server.update!(
          last_cve_scan_at: Time.current,
          vulnerability_count: server.vulnerability_alerts.active.count,
          critical_vulnerability_count: server.vulnerability_alerts.active.critical.count
        )

        # Update scan history
        scan_history.update!(
          scan_completed_at: Time.current,
          vulnerabilities_found: total_vulnerabilities,
          new_vulnerabilities: new_vulnerabilities,
          status: 'completed'
        )

        scan_history
      rescue StandardError => e
        scan_history.update!(
          status: 'failed',
          error_message: e.message
        )
        raise
      end
    end

    # Fetch vulnerabilities for a vendor/product combination
    def fetch_vendor_product_vulnerabilities(vendor, product, since: nil)
      command = ['check_vendor_product', vendor, product]

      result = execute_python_script(command)

      # Extract vulnerabilities from the results structure
      # API returns: {'results': {'data_source': [[cve_id, data], ...]}, 'total_count': N}
      vulnerabilities = []

      if result['results'].is_a?(Hash)
        result['results'].each_value do |source_data|
          next unless source_data.is_a?(Array)

          source_data.each do |item|
            next unless item.is_a?(Array) && item.size >= 2

            cve_id = item[0]
            vuln_data = item[1]

            next unless vuln_data.is_a?(Hash)

            # Normalize the data structure (handle both NVD and CVElistV5 formats)
            normalized = {
              'cve_id' => extract_cve_id(vuln_data, cve_id),
              'id' => extract_cve_id(vuln_data, cve_id),
              'published' => extract_published_date(vuln_data),
              'modified' => extract_modified_date(vuln_data),
              'description' => extract_description(vuln_data),
              'cvss_score' => extract_cvss_score(vuln_data),
              'cvss_vector' => extract_cvss_vector(vuln_data),
              'severity' => extract_severity(vuln_data),
              'references' => extract_references(vuln_data),
              'raw_data' => vuln_data
            }

            vulnerabilities << normalized
          end
        end
      end

      # Filter by date if specified
      if since
        vulnerabilities.select do |vuln|
          published = vuln['published']
          next false unless published

          DateTime.parse(published) > since
        rescue ArgumentError
          false
        end
      else
        vulnerabilities
      end
    end

    # Get specific CVE details
    def get_vulnerability_details(cve_id)
      command = ['check_cve', cve_id]
      execute_python_script(command)
    end

    # Get EPSS score for a CVE
    def get_epss_score(cve_id)
      command = ['get_epss', cve_id]
      result = execute_python_script(command)
      result['epss_score'] || result['score']
    end

    # Get recent CVEs from CISA Known Exploited Vulnerabilities
    def get_exploited_vulnerabilities
      command = ['get_cisa_kevs']
      result = execute_python_script(command)
      result['vulnerabilities'] || []
    end

    # Check CPE string for vulnerabilities
    def check_cpe(cpe_string)
      command = ['check_cpe', cpe_string]
      result = execute_python_script(command)
      result['vulnerabilities'] || []
    end

    # Test API connection
    def test_api_connection(api_url = nil, timeout = nil)
      begin
        # Temporarily override settings for testing
        original_url = SystemSetting.get('vulnerability_lookup_url')
        original_timeout = SystemSetting.get('vulnerability_lookup_timeout')

        if api_url
          SystemSetting.set('vulnerability_lookup_url', api_url, 'string')
        end

        if timeout
          SystemSetting.set('vulnerability_lookup_timeout', timeout, 'integer')
        end

        command = ['test_connection']
        result = execute_python_script(command)

        {
          success: true,
          message: "Connection successful! API URL: #{result['root_url']}",
          version: result['version'],
          library_version: result['library_version'],
          api_info: result['info']
        }
      rescue PythonError => e
        {
          success: false,
          message: "Connection failed: #{e.message}"
        }
      rescue StandardError => e
        {
          success: false,
          message: "Unexpected error: #{e.message}"
        }
      ensure
        # Restore original settings if we overrode them
        if api_url && original_url
          SystemSetting.set('vulnerability_lookup_url', original_url, 'string')
        end

        if timeout && original_timeout
          SystemSetting.set('vulnerability_lookup_timeout', original_timeout, 'integer')
        end
      end
    end

    private

    # Execute Python script with PyVulnerabilityLookup
    def execute_python_script(command)
      # Create temporary Python script
      script_file = Tempfile.new(['cve_monitor', '.py'])
      script_file.write(PYTHON_SCRIPT)
      script_file.close

      begin
        # Get configurable settings
        api_url = SystemSetting.get('vulnerability_lookup_url', 'https://vulnerability.circl.lu')
        python_path = SystemSetting.get('vulnerability_lookup_python_path', '/opt/veracity/app/integrations_venv/bin/python')
        timeout = SystemSetting.get('vulnerability_lookup_timeout', 120)

        # Use configured Python path, fallback if doesn't exist
        python_cmd = if File.exist?(python_path)
                      python_path
                    elsif File.exist?('/opt/veracity/app/integrations_venv/bin/python')
                      '/opt/veracity/app/integrations_venv/bin/python'
                    else
                      'python3'
                    end

        # Build command: python script.py <api_url> <command> <args...>
        cmd = [python_cmd, script_file.path, api_url] + command

        # Execute with configurable timeout
        stdout, stderr, status = Timeout.timeout(timeout.to_i) do
          Open3.capture3(*cmd)
        end

        unless status.success?
          raise PythonError, "Python script failed: #{stderr}"
        end

        # Parse JSON result
        JSON.parse(stdout)
      rescue JSON::ParserError => e
        Rails.logger.error "CveMonitoringService: Failed to parse JSON: #{stdout}"
        raise PythonError, "Invalid JSON response: #{e.message}"
      ensure
        script_file.unlink if script_file
      end
    end

    # Create alert from vulnerability data
    def create_alert_from_vulnerability(vuln_data, watchlist)
      cve_id = vuln_data['cve_id'] || vuln_data['id']
      return nil unless cve_id

      # Get additional details if needed
      if vuln_data['description'].blank?
        vuln_data = get_vulnerability_details(cve_id)
      end

      # Get EPSS score if not present
      if vuln_data['epss_score'].blank?
        epss_data = get_epss_score(cve_id)
        vuln_data['epss_score'] = epss_data if epss_data
      end

      VulnerabilityAlert.create_from_vulnerability_data(
        cve_id,
        vuln_data,
        watchlist: watchlist,
        server: watchlist.server
      )
    rescue StandardError => e
      Rails.logger.error "CveMonitoringService: Failed to create alert for #{cve_id}: #{e.message}"
      nil
    end

    # Create watchlists for a server based on its configuration
    def create_server_watchlists(server)
      # Create OS watchlist
      CveWatchlist.create_from_server(server)

      # Get installed packages if we haven't already
      if server.installed_packages.blank?
        fetch_installed_packages(server)
      end
    end

    # Fetch installed packages from server via Salt
    def fetch_installed_packages(server)
      return unless server.online?

      # Get package list via Salt
      result = SaltService.run_command(
        server.minion_id,
        'pkg.list_pkgs',
        []
      )

      if result[:success] && result[:output].is_a?(Hash)
        server.update!(installed_packages: result[:output])

        # Create watchlists for important packages
        CveWatchlist.create_from_packages(server, result[:output])
      end
    rescue StandardError => e
      Rails.logger.error "CveMonitoringService: Failed to fetch packages for #{server.hostname}: #{e.message}"
    end

    # Helper methods to extract data from vulnerability JSON
    # Supports both NVD and CVElistV5 formats

    def extract_cve_id(vuln_data, fallback_id)
      # CVElistV5 format
      vuln_data.dig('cveMetadata', 'cveId') ||
        # NVD format
        vuln_data['id'] ||
        # Fallback
        fallback_id
    end

    def extract_published_date(vuln_data)
      # CVElistV5 format
      vuln_data.dig('cveMetadata', 'datePublished') ||
        # NVD format
        vuln_data['published']
    end

    def extract_modified_date(vuln_data)
      # CVElistV5 format
      vuln_data.dig('cveMetadata', 'dateUpdated') ||
        # NVD format
        vuln_data['lastModified']
    end

    def extract_references(vuln_data)
      # CVElistV5 format
      cvelistv5_refs = vuln_data.dig('containers', 'cna', 'references')
      return cvelistv5_refs if cvelistv5_refs.is_a?(Array)

      # NVD format
      vuln_data['references'] || []
    end

    def extract_description(vuln_data)
      # CVElistV5 format - containers.cna.descriptions
      cvelistv5_desc = vuln_data.dig('containers', 'cna', 'descriptions')
      if cvelistv5_desc.is_a?(Array) && cvelistv5_desc.any?
        en_desc = cvelistv5_desc.find { |d| d['lang'] == 'en' }
        return en_desc['value'] if en_desc && en_desc['value']
        return cvelistv5_desc.first['value'] if cvelistv5_desc.first && cvelistv5_desc.first['value']
      end

      # NVD format - descriptions array
      descriptions = vuln_data['descriptions'] || []
      en_desc = descriptions.find { |d| d['lang'] == 'en' }
      en_desc&.dig('value') || descriptions.first&.dig('value') || 'No description available'
    end

    def extract_cvss_score(vuln_data)
      # CVElistV5 format - containers.cna.metrics[0].cvssV3_1.baseScore
      cvelistv5_metrics = vuln_data.dig('containers', 'cna', 'metrics')
      if cvelistv5_metrics.is_a?(Array) && cvelistv5_metrics.any?
        cvss_v31 = cvelistv5_metrics.first&.dig('cvssV3_1', 'baseScore')
        return cvss_v31 if cvss_v31

        cvss_v30 = cvelistv5_metrics.first&.dig('cvssV3_0', 'baseScore')
        return cvss_v30 if cvss_v30

        cvss_v2 = cvelistv5_metrics.first&.dig('cvssV2', 'baseScore')
        return cvss_v2 if cvss_v2
      end

      # NVD format - metrics.cvssMetricV31[0].cvssData.baseScore
      metrics = vuln_data['metrics'] || {}
      cvss_data = metrics['cvssMetricV31']&.first ||
                  metrics['cvssMetricV30']&.first ||
                  metrics['cvssMetricV2']&.first

      cvss_data&.dig('cvssData', 'baseScore')
    end

    def extract_cvss_vector(vuln_data)
      # CVElistV5 format
      cvelistv5_metrics = vuln_data.dig('containers', 'cna', 'metrics')
      if cvelistv5_metrics.is_a?(Array) && cvelistv5_metrics.any?
        vector = cvelistv5_metrics.first&.dig('cvssV3_1', 'vectorString') ||
                 cvelistv5_metrics.first&.dig('cvssV3_0', 'vectorString') ||
                 cvelistv5_metrics.first&.dig('cvssV2', 'vectorString')
        return vector if vector
      end

      # NVD format
      metrics = vuln_data['metrics'] || {}
      cvss_data = metrics['cvssMetricV31']&.first ||
                  metrics['cvssMetricV30']&.first ||
                  metrics['cvssMetricV2']&.first

      cvss_data&.dig('cvssData', 'vectorString')
    end

    def extract_severity(vuln_data)
      # CVElistV5 format
      cvelistv5_metrics = vuln_data.dig('containers', 'cna', 'metrics')
      if cvelistv5_metrics.is_a?(Array) && cvelistv5_metrics.any?
        severity = cvelistv5_metrics.first&.dig('cvssV3_1', 'baseSeverity') ||
                   cvelistv5_metrics.first&.dig('cvssV3_0', 'baseSeverity') ||
                   cvelistv5_metrics.first&.dig('cvssV2', 'baseSeverity')
        return severity.upcase if severity
      end

      # NVD format
      metrics = vuln_data['metrics'] || {}
      cvss_data = metrics['cvssMetricV31']&.first ||
                  metrics['cvssMetricV30']&.first ||
                  metrics['cvssMetricV2']&.first

      severity = cvss_data&.dig('cvssData', 'baseSeverity') || cvss_data&.dig('baseSeverity')

      # Normalize to uppercase or determine from score
      severity&.upcase || determine_severity_from_score(extract_cvss_score(vuln_data))
    end

    def determine_severity_from_score(score)
      return 'UNKNOWN' unless score

      case score
      when 9.0..10.0 then 'CRITICAL'
      when 7.0...9.0 then 'HIGH'
      when 4.0...7.0 then 'MEDIUM'
      when 0.1...4.0 then 'LOW'
      else 'UNKNOWN'
      end
    end

    # Send notifications for new vulnerabilities
    def notify_new_vulnerabilities(alerts)
      return unless alerts.any?

      # Group by severity
      critical_alerts = alerts.select(&:critical?)
      high_alerts = alerts.select { |a| a.severity == 'HIGH' }

      # Send email if critical vulnerabilities found
      if critical_alerts.any?
        CveAlertMailer.critical_vulnerabilities(critical_alerts).deliver_later
      end

      # Send Gotify push notifications based on threshold settings
      alerts.each do |alert|
        next unless should_notify?(alert)

        GotifyNotificationService.notify_cve_alert(alert)
      end

      # Broadcast to dashboard
      ActionCable.server.broadcast(
        'dashboard_channel',
        {
          type: 'new_vulnerabilities',
          count: alerts.size,
          critical_count: critical_alerts.size,
          high_count: high_alerts.size,
          alerts: alerts.map { |a| alert_summary(a) }
        }
      )
    end

    # Determine if an alert should trigger a notification
    def should_notify?(alert)
      # Check if notifications are enabled globally
      return false unless SystemSetting.get('vulnerability_lookup_enabled', true)

      # Get watchlist-specific settings if available
      watchlist = alert.cve_watchlist
      if watchlist
        # Check if watchlist has notifications enabled
        return false unless watchlist.notification_enabled.nil? || watchlist.notification_enabled

        # Use watchlist-specific threshold if set, otherwise use global
        threshold = watchlist.notification_threshold || SystemSetting.get('vulnerability_lookup_notification_threshold', 'high')
      else
        # Use global threshold
        threshold = SystemSetting.get('vulnerability_lookup_notification_threshold', 'high')
      end

      # Check if alert severity meets the threshold
      meets_threshold?(alert.severity, threshold)
    end

    # Check if severity meets the notification threshold
    def meets_threshold?(severity, threshold)
      severity_levels = {
        'info' => 0,
        'low' => 1,
        'medium' => 2,
        'high' => 3,
        'critical' => 4
      }

      threshold_levels = {
        'info' => 0,
        'low' => 1,
        'medium' => 2,
        'high' => 3,
        'critical' => 4
      }

      severity_value = severity_levels[severity.to_s.downcase] || 0
      threshold_value = threshold_levels[threshold.to_s.downcase] || 3

      severity_value >= threshold_value
    end

    def alert_summary(alert)
      {
        id: alert.id,
        cve_id: alert.cve_id,
        severity: alert.severity,
        server: alert.server&.hostname,
        description: alert.description&.truncate(200),
        is_exploited: alert.is_exploited
      }
    end
  end
end