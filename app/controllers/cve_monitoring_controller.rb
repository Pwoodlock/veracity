# frozen_string_literal: true

class CveMonitoringController < ApplicationController
  before_action :authenticate_user!
  before_action :check_authorization
  before_action :set_vulnerability_alert, only: [:show_alert, :acknowledge_alert, :patch_alert, :ignore_alert]
  before_action :set_watchlist, only: [:show_watchlist, :edit_watchlist, :update_watchlist, :destroy_watchlist, :scan_watchlist]

  # Dashboard - Overview of all CVE monitoring
  def index
    @stats = {
      total_alerts: VulnerabilityAlert.count,
      active_alerts: VulnerabilityAlert.active.count,
      critical_alerts: VulnerabilityAlert.active.critical.count,
      exploited_alerts: VulnerabilityAlert.active.exploited.count,
      watchlists: CveWatchlist.active.count,
      servers_monitored: Server.where(cve_scan_enabled: true).count
    }

    # Recent alerts
    begin
      @recent_alerts = VulnerabilityAlert.active
                                         .includes(:server, :cve_watchlist)
                                         .by_severity
                                         .limit(10)
    rescue
      @recent_alerts = []
    end

    # Watchlists
    begin
      @watchlists = CveWatchlist.active
                                .includes(:server)
                                .order(last_checked_at: :desc)
                                .limit(5)
    rescue
      @watchlists = []
    end

    # Servers with most vulnerabilities
    begin
      @vulnerable_servers = Server.joins(:vulnerability_alerts)
                                  .where(vulnerability_alerts: { status: %w[new acknowledged investigating] })
                                  .group('servers.id')
                                  .order('COUNT(vulnerability_alerts.id) DESC')
                                  .limit(5)
                                  .select('servers.*, COUNT(vulnerability_alerts.id) as vuln_count')
    rescue
      @vulnerable_servers = []
    end

    # Recent scan history
    begin
      @recent_scans = CveScanHistory.includes(:server)
                                    .recent
                                    .limit(5)
    rescue
      @recent_scans = []
    end
  end

  # List all vulnerability alerts
  def alerts
    @alerts = VulnerabilityAlert.includes(:server, :cve_watchlist)

    # Filtering
    @alerts = @alerts.where(status: params[:status]) if params[:status].present?
    @alerts = @alerts.where(severity: params[:severity]) if params[:severity].present?
    @alerts = @alerts.where(server_id: params[:server_id]) if params[:server_id].present?
    @alerts = @alerts.where(is_exploited: true) if params[:exploited] == 'true'

    # Sorting
    case params[:sort]
    when 'severity'
      @alerts = @alerts.by_severity
    when 'published'
      @alerts = @alerts.order(published_at: :desc)
    else
      @alerts = @alerts.order(created_at: :desc)
    end

    @alerts = @alerts.page(params[:page]).per(25)

    respond_to do |format|
      format.html
      format.json { render json: @alerts }
    end
  end

  # Show individual alert details
  def show_alert
    @related_alerts = VulnerabilityAlert.where(cve_id: @alert.cve_id)
                                        .where.not(id: @alert.id)
                                        .includes(:server)
  end

  # Acknowledge an alert
  def acknowledge_alert
    @alert.acknowledge!(current_user)

    respond_to do |format|
      format.html { redirect_to cve_monitoring_alerts_path, notice: 'Alert acknowledged.' }
      format.turbo_stream
      format.json { render json: @alert }
    end
  end

  # Mark alert as patched
  def patch_alert
    @alert.mark_as_patched!(current_user)

    respond_to do |format|
      format.html { redirect_to cve_monitoring_alerts_path, notice: 'Alert marked as patched.' }
      format.turbo_stream
      format.json { render json: @alert }
    end
  end

  # Ignore an alert
  def ignore_alert
    @alert.mark_as_ignored!(current_user, params[:reason])

    respond_to do |format|
      format.html { redirect_to cve_monitoring_alerts_path, notice: 'Alert ignored.' }
      format.turbo_stream
      format.json { render json: @alert }
    end
  end

  # List all watchlists
  def watchlists
    @watchlists = CveWatchlist.includes(:server)
                              .order(:vendor, :product)

    @global_watchlists = CveWatchlist.global.includes(:server).order(:vendor, :product)
    @server_watchlists = CveWatchlist.server_specific.includes(:server).order(:vendor, :product)
  end

  # Show watchlist details
  def show_watchlist
    @recent_alerts = @watchlist.vulnerability_alerts
                               .includes(:server)
                               .order(created_at: :desc)
                               .limit(10)
  end

  # New watchlist form
  def new_watchlist
    @watchlist = CveWatchlist.new
    @servers = Server.order(:hostname)
  end

  # Create watchlist
  def create_watchlist
    @watchlist = CveWatchlist.new(watchlist_params)

    if @watchlist.save
      # Trigger initial scan
      CveScanJob.perform_later('watchlist', @watchlist.id) rescue nil

      respond_to do |format|
        format.html { redirect_to cve_monitoring_watchlists_path, notice: 'Watchlist created successfully.' }
        format.json { render json: @watchlist, status: :created }
      end
    else
      @servers = Server.order(:hostname)
      render :new_watchlist
    end
  end

  # Edit watchlist form
  def edit_watchlist
    @servers = Server.order(:hostname)
  end

  # Update watchlist
  def update_watchlist
    if @watchlist.update(watchlist_params)
      respond_to do |format|
        format.html { redirect_to cve_monitoring_watchlists_path, notice: 'Watchlist updated successfully.' }
        format.json { render json: @watchlist }
      end
    else
      @servers = Server.order(:hostname)
      render :edit_watchlist
    end
  end

  # Delete watchlist
  def destroy_watchlist
    @watchlist.destroy

    respond_to do |format|
      format.html { redirect_to cve_monitoring_watchlists_path, notice: 'Watchlist deleted.' }
      format.json { head :no_content }
    end
  end

  # Manually trigger scan for a watchlist
  def scan_watchlist
    CveScanJob.perform_later('watchlist', @watchlist.id)

    respond_to do |format|
      format.html { redirect_back(fallback_location: cve_monitoring_watchlists_path, notice: 'Scan initiated.') }
      format.json { render json: { status: 'scanning' } }
    end
  end

  # Scan a specific server
  def scan_server
    @server = Server.find(params[:server_id])

    CveScanJob.perform_later('server', @server.id)

    respond_to do |format|
      format.html { redirect_back(fallback_location: server_path(@server), notice: 'CVE scan initiated.') }
      format.json { render json: { status: 'scanning' } }
    end
  end

  # Bulk operations on alerts
  def bulk_update_alerts
    alert_ids = params[:alert_ids]
    action = params[:action_type]

    alerts = VulnerabilityAlert.where(id: alert_ids)

    case action
    when 'acknowledge'
      alerts.each { |a| a.acknowledge!(current_user) }
      message = "#{alerts.count} alerts acknowledged."
    when 'patch'
      alerts.each { |a| a.mark_as_patched!(current_user) }
      message = "#{alerts.count} alerts marked as patched."
    when 'ignore'
      alerts.each { |a| a.mark_as_ignored!(current_user, params[:reason]) }
      message = "#{alerts.count} alerts ignored."
    else
      message = "Unknown action."
    end

    respond_to do |format|
      format.html { redirect_to cve_monitoring_alerts_path, notice: message }
      format.json { render json: { message: message } }
    end
  end

  # API endpoint for real-time updates
  def status
    render json: {
      active_alerts: VulnerabilityAlert.active.count,
      critical_alerts: VulnerabilityAlert.active.critical.count,
      last_scan: CveScanHistory.completed.maximum(:scan_completed_at),
      watchlists_active: CveWatchlist.active.count
    }
  end

  # Initialize default watchlists
  def setup
    begin
      # Create default watchlists with error handling for duplicates
      default_watchlists = [
        { vendor: 'proxmox', product: 'proxmox_ve', description: 'Proxmox Virtual Environment' },
        { vendor: 'canonical', product: 'ubuntu_linux', description: 'Ubuntu Linux' },
        { vendor: 'debian', product: 'debian_linux', description: 'Debian Linux' },
        { vendor: 'docker', product: 'docker', description: 'Docker Engine' },
        { vendor: 'openssl', product: 'openssl', description: 'OpenSSL' },
        { vendor: 'openssh', product: 'openssh', description: 'OpenSSH' }
      ]

      created_count = 0
      default_watchlists.each do |wl|
        watchlist = CveWatchlist.find_or_initialize_by(
          vendor: wl[:vendor],
          product: wl[:product],
          server_id: nil
        )

        if watchlist.new_record?
          watchlist.description = wl[:description]
          watchlist.active = (wl[:vendor] == 'proxmox') # Only Proxmox active by default
          watchlist.frequency = 'hourly'
          watchlist.save
          created_count += 1
        end
      end

      # Auto-detect watchlists from servers
      Server.find_each do |server|
        begin
          CveWatchlist.create_from_server(server) rescue nil
        rescue => e
          Rails.logger.error "Error creating watchlist for server #{server.hostname}: #{e.message}"
        end
      end

      redirect_to cve_monitoring_path, notice: "CVE monitoring setup completed. #{created_count} watchlists created."
    rescue => e
      redirect_to cve_monitoring_path, alert: "Setup error: #{e.message}"
    end
  end

  private

  def set_vulnerability_alert
    @alert = VulnerabilityAlert.find(params[:id])
  end

  def set_watchlist
    @watchlist = CveWatchlist.find(params[:id])
  end

  def watchlist_params
    params.require(:cve_watchlist).permit(
      :vendor, :product, :version, :cpe_string,
      :description, :active, :frequency, :server_id
    )
  end

  def check_authorization
    unless current_user&.admin? || current_user&.operator?
      redirect_to root_path, alert: 'Not authorized to access CVE monitoring.'
    end
  end
end