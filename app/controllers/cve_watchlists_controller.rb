# frozen_string_literal: true

class CveWatchlistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_cve_watchlist, only: [:show, :edit, :update, :destroy, :test, :debug]

  def index
    @cve_watchlists = CveWatchlist.includes(:server).order(created_at: :desc)

    # Filter by server if specified
    if params[:server_id].present?
      @cve_watchlists = @cve_watchlists.where(server_id: params[:server_id])
    end

    # Filter by active status
    if params[:active].present?
      @cve_watchlists = @cve_watchlists.where(active: params[:active] == 'true')
    end
  end

  def show
    @recent_alerts = @cve_watchlist.vulnerability_alerts.order(created_at: :desc).limit(20)
  end

  def new
    @cve_watchlist = CveWatchlist.new
    @servers = Server.order(:hostname)
  end

  def create
    @cve_watchlist = CveWatchlist.new(cve_watchlist_params)

    if @cve_watchlist.save
      flash[:notice] = 'CVE Watchlist created successfully'
      redirect_to cve_watchlists_path
    else
      @servers = Server.order(:hostname)
      flash.now[:error] = 'Failed to create watchlist'
      render :new
    end
  end

  def edit
    @servers = Server.order(:hostname)
  end

  def update
    if @cve_watchlist.update(cve_watchlist_params)
      flash[:notice] = 'CVE Watchlist updated successfully'
      redirect_to cve_watchlist_path(@cve_watchlist)
    else
      @servers = Server.order(:hostname)
      flash.now[:error] = 'Failed to update watchlist'
      render :edit
    end
  end

  def destroy
    @cve_watchlist.destroy
    flash[:notice] = 'CVE Watchlist deleted successfully'
    redirect_to cve_watchlists_path
  end

  def test
    begin
      # Force a full scan by temporarily clearing last_checked_at
      force_full_scan = params[:force_full_scan].present?

      if force_full_scan
        original_last_checked = @cve_watchlist.last_checked_at
        @cve_watchlist.update_column(:last_checked_at, nil)
      end

      # Run immediate check on this watchlist
      alerts = CveMonitoringService.check_watchlist(@cve_watchlist)

      # Restore original timestamp if we forced a full scan
      if force_full_scan && original_last_checked
        @cve_watchlist.update_column(:last_checked_at, original_last_checked)
      end

      if alerts.size > 0
        flash[:notice] = "Watchlist checked successfully. Found #{alerts.size} new vulnerabilities."
      else
        # Check total vulnerabilities
        total_vulns = CveMonitoringService.fetch_vendor_product_vulnerabilities(
          @cve_watchlist.vendor,
          @cve_watchlist.product
        )
        flash[:info] = "No NEW vulnerabilities found since last check. Total known vulnerabilities: #{total_vulns.size}. Use 'Force Full Scan' to re-import all."
      end

      redirect_to cve_watchlist_path(@cve_watchlist)
    rescue StandardError => e
      Rails.logger.error "Test watchlist error: #{e.message}\n#{e.backtrace.join("\n")}"
      flash[:error] = "Failed to check watchlist: #{e.message}"
      redirect_to cve_watchlist_path(@cve_watchlist)
    end
  end

  def debug
    begin
      # Fetch vulnerabilities with debug info
      start_time = Time.current
      vulnerabilities = CveMonitoringService.fetch_vendor_product_vulnerabilities(
        @cve_watchlist.vendor,
        @cve_watchlist.product
      )
      end_time = Time.current

      @debug_info = {
        request: {
          vendor: @cve_watchlist.vendor,
          product: @cve_watchlist.product,
          version: @cve_watchlist.version || 'All versions',
          api_url: SystemSetting.get('vulnerability_lookup_url', 'https://vulnerability.circl.lu')
        },
        response: {
          count: vulnerabilities.size,
          duration_ms: ((end_time - start_time) * 1000).round(2),
          vulnerabilities: vulnerabilities.map do |vuln|
            {
              cve_id: vuln['cve_id'],
              published: vuln['published'],
              severity: vuln['severity'],
              cvss_score: vuln['cvss_score'],
              description: vuln['description']&.truncate(200)
            }
          end
        },
        raw_response: vulnerabilities.first(3) # Show first 3 complete records
      }

      render layout: 'application'
    rescue StandardError => e
      @debug_info = {
        error: e.message,
        backtrace: e.backtrace.first(10)
      }
      render layout: 'application'
    end
  end

  private

  def set_cve_watchlist
    @cve_watchlist = CveWatchlist.find(params[:id])
  end

  def cve_watchlist_params
    params.require(:cve_watchlist).permit(
      :server_id,
      :vendor,
      :product,
      :version,
      :active,
      :notification_enabled,
      :notification_threshold,
      :description
    )
  end
end
