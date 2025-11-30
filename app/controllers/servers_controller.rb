class ServersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_server, only: [:show, :edit, :update, :destroy, :sync, :diagnose, :manual_refresh_proxmox, :start_hetzner, :stop_hetzner, :reboot_hetzner, :refresh_hetzner_status, :hetzner_snapshots, :create_hetzner_snapshot, :delete_hetzner_snapshot, :start_proxmox, :stop_proxmox, :shutdown_proxmox, :reboot_proxmox, :refresh_proxmox_status, :proxmox_snapshots, :create_proxmox_snapshot, :rollback_proxmox_snapshot, :delete_proxmox_snapshot]

  # SECURITY: Authorization checks to prevent IDOR attacks
  # Viewers: Can only view servers (index, show)
  # Operators: Can view and manage servers (edit, update, sync, Hetzner/Proxmox controls)
  # Admins: Full access including destroy
  before_action :require_operator!, only: [:edit, :update, :sync, :diagnose, :manual_refresh_proxmox, :start_hetzner, :stop_hetzner, :reboot_hetzner, :refresh_hetzner_status, :hetzner_snapshots, :create_hetzner_snapshot, :delete_hetzner_snapshot, :fetch_hetzner_servers, :start_proxmox, :stop_proxmox, :shutdown_proxmox, :reboot_proxmox, :refresh_proxmox_status, :proxmox_snapshots, :create_proxmox_snapshot, :rollback_proxmox_snapshot, :delete_proxmox_snapshot, :fetch_proxmox_vms]
  before_action :require_admin!, only: [:destroy]

  # List all servers
  def index
    servers_query = Server.includes(:group).order(status: :asc, hostname: :asc)
    @groups = Group.ordered

    # Apply group filter if provided
    if params[:group_id].present?
      if params[:group_id] == 'ungrouped'
        servers_query = servers_query.ungrouped
      else
        servers_query = servers_query.where(group_id: params[:group_id])
      end
    end

    # Apply status filter if provided
    if params[:status].present?
      servers_query = servers_query.where(status: params[:status])
    end

    # Apply search if provided
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      servers_query = servers_query.where(
        "hostname ILIKE ? OR ip_address ILIKE ? OR minion_id ILIKE ?",
        search_term, search_term, search_term
      )
    end

    # Paginate results - 10 servers per page
    @pagy, @servers = pagy(servers_query, items: 10)

    # Get total counts (not paginated)
    @total_online = Server.where(status: 'online').count
    @total_offline = Server.where(status: 'offline').count
    @total_unreachable = Server.where(status: 'unreachable').count
  end

  # Show server details
  def show
    # N+1 Query Optimization: Preload user association for recent commands
    # The commands index view accesses user_display_name
    @recent_commands = @server.commands
                              .includes(:user)
                              .order(started_at: :desc)
                              .limit(10)

    # Fetch latest metrics (no N+1 issue here since it's a single server)
    @latest_metrics = @server.server_metrics.order(collected_at: :desc).first
  end

  # Edit server (mainly for group assignment)
  def edit
    @groups = Group.ordered
  end

  # Update server (mainly for group assignment)
  def update
    if @server.update(server_params)
      redirect_to server_path(@server), notice: "Server updated successfully."
    else
      @groups = Group.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  # Delete server
  def destroy
    minion_id = @server.minion_id
    hostname = @server.hostname

    # Attempt to uninstall salt-minion and delete key
    result = SaltService.remove_minion_completely(minion_id)

    # Delete server record regardless of uninstall result
    # (user may want to remove offline servers)
    @server.destroy

    if result[:success]
      redirect_to servers_path, notice: "Server #{hostname} deleted. #{result[:message]}"
    else
      redirect_to servers_path, alert: "Server #{hostname} deleted from database. #{result[:message]}"
    end
  rescue StandardError => e
    Rails.logger.error "Error during server deletion: #{e.message}"
    @server.destroy if @server.persisted?
    redirect_to servers_path, alert: "Server deleted but cleanup failed: #{e.message}"
  end

  # Sync server data from Salt
  def sync
    # Use @server from before_action :set_server
    begin
      # Ping to check status
      ping_result = SaltService.ping_minion(@server.minion_id)
      @server.status = (ping_result && ping_result['return']&.first&.dig(@server.minion_id)) ? 'online' : 'offline'
      @server.last_seen = Time.current if @server.status == 'online'

      # Get fresh grains if online
      if @server.status == 'online'
        grains = SaltService.sync_minion_grains(@server.minion_id)
        if grains.present?
          @server.os_name = grains['os']
          @server.os_version = grains['osrelease'] || grains['osmajorrelease']&.to_s
          @server.cpu_cores = grains['num_cpus']
          @server.memory_gb = (grains['mem_total'].to_f / 1024.0).round(2) if grains['mem_total']
          @server.grains = grains
        end
      end

      @server.save!
      redirect_to server_path(@server), notice: "Server data synced successfully"
    rescue StandardError => e
      redirect_to server_path(@server), alert: "Failed to sync server: #{e.message}"
    end
  end

  # Fetch Hetzner servers for a given API key (for dropdown population)
  def fetch_hetzner_servers
    api_key_id = params[:api_key_id]

    if api_key_id.blank?
      return render json: { success: false, error: 'API key ID is required' }, status: :bad_request
    end

    api_key = HetznerApiKey.find_by(id: api_key_id)

    unless api_key
      return render json: { success: false, error: 'API key not found' }, status: :not_found
    end

    unless api_key.enabled?
      return render json: { success: false, error: 'API key is disabled' }, status: :unprocessable_entity
    end

    # Fetch servers from Hetzner Cloud
    result = HetznerService.list_servers(api_key)

    if result[:success]
      # Format servers for dropdown
      servers = result[:data][:servers].map do |server|
        {
          id: server[:server_id],
          name: server[:name],
          status: server[:status],
          type: server[:server_type],
          datacenter: server[:datacenter],
          ipv4: server[:ipv4],
          display_name: "#{server[:name]} (ID: #{server[:server_id]}) - #{server[:status]}"
        }
      end

      render json: { success: true, servers: servers }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching Hetzner servers: #{e.message}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # Hetzner Cloud Control Actions

  # Start Hetzner server
  def start_hetzner
    unless @server.can_use_hetzner_features?
      redirect_to server_path(@server), alert: "This server is not configured for Hetzner Cloud control."
      return
    end

    result = HetznerService.start_server(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "Server is starting... (#{result[:data][:message]})"
    else
      redirect_to server_path(@server), alert: "Failed to start server: #{result[:error]}"
    end
  end

  # Stop Hetzner server
  def stop_hetzner
    unless @server.can_use_hetzner_features?
      redirect_to server_path(@server), alert: "This server is not configured for Hetzner Cloud control."
      return
    end

    result = HetznerService.stop_server(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "Server is stopping... (#{result[:data][:message]})"
    else
      redirect_to server_path(@server), alert: "Failed to stop server: #{result[:error]}"
    end
  end

  # Reboot Hetzner server
  def reboot_hetzner
    unless @server.can_use_hetzner_features?
      redirect_to server_path(@server), alert: "This server is not configured for Hetzner Cloud control."
      return
    end

    result = HetznerService.reboot_server(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "Server is rebooting... (#{result[:data][:message]})"
    else
      redirect_to server_path(@server), alert: "Failed to reboot server: #{result[:error]}"
    end
  end

  # Refresh Hetzner server status
  def refresh_hetzner_status
    unless @server.can_use_hetzner_features?
      redirect_to server_path(@server), alert: "This server is not configured for Hetzner Cloud control."
      return
    end

    result = HetznerService.get_server_status(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "Server status refreshed: #{result[:data][:status]}"
    else
      redirect_to server_path(@server), alert: "Failed to refresh status: #{result[:error]}"
    end
  end

  # List Hetzner snapshots
  def hetzner_snapshots
    unless @server.can_use_hetzner_features?
      redirect_to server_path(@server), alert: "This server is not configured for Hetzner Cloud snapshots."
      return
    end

    result = HetznerSnapshotService.list_snapshots(@server)

    if result[:success]
      @snapshots = result[:data][:snapshots]
      render :hetzner_snapshots
    else
      redirect_to server_path(@server), alert: "Failed to list snapshots: #{result[:error]}"
    end
  end

  # Create manual Hetzner snapshot
  def create_hetzner_snapshot
    unless @server.can_use_hetzner_features?
      redirect_to server_path(@server), alert: "This server is not configured for Hetzner Cloud snapshots."
      return
    end

    description = params[:description] || "Manual snapshot - #{Time.current.strftime('%Y-%m-%d %H:%M')}"

    # Create snapshot (non-blocking, just initiates it)
    result = HetznerSnapshotService.create_snapshot(@server, description: description)

    if result[:success]
      redirect_to server_path(@server), notice: "Snapshot creation initiated: #{result[:data][:snapshot_id]}"
    else
      redirect_to server_path(@server), alert: "Failed to create snapshot: #{result[:error]}"
    end
  end

  # Delete Hetzner snapshot
  def delete_hetzner_snapshot
    unless @server.can_use_hetzner_features?
      redirect_to hetzner_snapshots_server_path(@server), alert: "This server is not configured for Hetzner Cloud snapshots."
      return
    end

    snapshot_id = params[:snapshot_id]

    if snapshot_id.blank?
      redirect_to hetzner_snapshots_server_path(@server), alert: "Snapshot ID is required."
      return
    end

    # Delete snapshot via service
    result = HetznerSnapshotService.delete_snapshot(@server, snapshot_id)

    if result[:success]
      redirect_to hetzner_snapshots_server_path(@server), notice: "Snapshot #{snapshot_id} deleted successfully."
    else
      redirect_to hetzner_snapshots_server_path(@server), alert: "Failed to delete snapshot: #{result[:error]}"
    end
  end

  # Proxmox VM/LXC Control Actions

  # Fetch Proxmox VMs/LXCs for a given API key and node
  def fetch_proxmox_vms
    api_key_id = params[:api_key_id]
    node_name = params[:node_name]

    if api_key_id.blank?
      return render json: { success: false, error: 'API key ID is required' }, status: :bad_request
    end

    if node_name.blank?
      return render json: { success: false, error: 'Node name is required' }, status: :bad_request
    end

    api_key = ProxmoxApiKey.find_by(id: api_key_id)

    unless api_key
      return render json: { success: false, error: 'API key not found' }, status: :not_found
    end

    unless api_key.enabled?
      return render json: { success: false, error: 'API key is disabled' }, status: :unprocessable_entity
    end

    # Fetch VMs from Proxmox
    result = ProxmoxService.list_vms(api_key, node_name)

    if result[:success]
      # Format VMs for dropdown
      vms = result[:data][:vms].map do |vm|
        {
          vmid: vm[:vmid],
          name: vm[:name],
          type: vm[:type],
          status: vm[:status],
          node: vm[:node],
          display_name: "[#{vm[:type].upcase}] #{vm[:name]} (ID: #{vm[:vmid]}) - #{vm[:status]}"
        }
      end

      render json: { success: true, vms: vms }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching Proxmox VMs: #{e.message}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # Start Proxmox VM/LXC
  def start_proxmox
    unless @server.can_use_proxmox_features?
      redirect_to server_path(@server), alert: "This server is not configured for Proxmox VM/LXC control."
      return
    end

    result = ProxmoxService.start_vm(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "#{@server.proxmox_type_display} is starting..."
    else
      redirect_to server_path(@server), alert: "Failed to start #{@server.proxmox_type_display.downcase}: #{result[:error]}"
    end
  end

  # Stop (force) Proxmox VM/LXC
  def stop_proxmox
    unless @server.can_use_proxmox_features?
      redirect_to server_path(@server), alert: "This server is not configured for Proxmox VM/LXC control."
      return
    end

    result = ProxmoxService.stop_vm(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "#{@server.proxmox_type_display} is stopping (forced)..."
    else
      redirect_to server_path(@server), alert: "Failed to stop #{@server.proxmox_type_display.downcase}: #{result[:error]}"
    end
  end

  # Shutdown (graceful) Proxmox VM/LXC
  def shutdown_proxmox
    unless @server.can_use_proxmox_features?
      redirect_to server_path(@server), alert: "This server is not configured for Proxmox VM/LXC control."
      return
    end

    result = ProxmoxService.shutdown_vm(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "#{@server.proxmox_type_display} is shutting down gracefully..."
    else
      redirect_to server_path(@server), alert: "Failed to shutdown #{@server.proxmox_type_display.downcase}: #{result[:error]}"
    end
  end

  # Reboot Proxmox VM/LXC
  def reboot_proxmox
    unless @server.can_use_proxmox_features?
      redirect_to server_path(@server), alert: "This server is not configured for Proxmox VM/LXC control."
      return
    end

    result = ProxmoxService.reboot_vm(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "#{@server.proxmox_type_display} is rebooting..."
    else
      redirect_to server_path(@server), alert: "Failed to reboot #{@server.proxmox_type_display.downcase}: #{result[:error]}"
    end
  end

  # Refresh Proxmox VM/LXC status
  def refresh_proxmox_status
    unless @server.can_use_proxmox_features?
      redirect_to server_path(@server), alert: "This server is not configured for Proxmox VM/LXC control."
      return
    end

    result = ProxmoxService.get_vm_status(@server)

    if result[:success]
      redirect_to server_path(@server), notice: "#{@server.proxmox_type_display} status refreshed: #{result[:data][:status]}"
    else
      redirect_to server_path(@server), alert: "Failed to refresh status: #{result[:error]}"
    end
  end

  # List Proxmox snapshots
  def proxmox_snapshots
    unless @server.can_use_proxmox_features?
      redirect_to server_path(@server), alert: "This server is not configured for Proxmox snapshots."
      return
    end

    result = ProxmoxService.list_snapshots(@server)

    if result[:success]
      @snapshots = result[:data][:snapshots] || []
      render :proxmox_snapshots
    else
      redirect_to server_path(@server), alert: "Failed to list snapshots: #{result[:error]}"
    end
  end

  # Create Proxmox snapshot
  def create_proxmox_snapshot
    unless @server.can_use_proxmox_features?
      redirect_to server_path(@server), alert: "This server is not configured for Proxmox snapshots."
      return
    end

    snap_name = params[:snap_name]&.strip
    description = params[:description]&.strip || "Manual snapshot - #{Time.current.strftime('%Y-%m-%d %H:%M')}"

    if snap_name.blank?
      redirect_to proxmox_snapshots_server_path(@server), alert: "Snapshot name is required."
      return
    end

    # Validate snapshot name (alphanumeric, dash, underscore only)
    unless snap_name.match?(/\A[a-zA-Z0-9_-]+\z/)
      redirect_to proxmox_snapshots_server_path(@server), alert: "Invalid snapshot name. Use only letters, numbers, dash, and underscore."
      return
    end

    result = ProxmoxService.create_snapshot(@server, snap_name, description)

    if result[:success]
      redirect_to proxmox_snapshots_server_path(@server), notice: "Snapshot '#{snap_name}' created successfully."
    else
      redirect_to proxmox_snapshots_server_path(@server), alert: "Failed to create snapshot: #{result[:error]}"
    end
  end

  # Rollback Proxmox snapshot
  def rollback_proxmox_snapshot
    unless @server.can_use_proxmox_features?
      redirect_to proxmox_snapshots_server_path(@server), alert: "This server is not configured for Proxmox snapshots."
      return
    end

    snap_name = params[:snap_name]

    if snap_name.blank?
      redirect_to proxmox_snapshots_server_path(@server), alert: "Snapshot name is required."
      return
    end

    result = ProxmoxService.rollback_snapshot(@server, snap_name)

    if result[:success]
      redirect_to proxmox_snapshots_server_path(@server), notice: "Successfully rolled back to snapshot '#{snap_name}'."
    else
      redirect_to proxmox_snapshots_server_path(@server), alert: "Failed to rollback snapshot: #{result[:error]}"
    end
  end

  # Delete Proxmox snapshot
  def delete_proxmox_snapshot
    unless @server.can_use_proxmox_features?
      redirect_to proxmox_snapshots_server_path(@server), alert: "This server is not configured for Proxmox snapshots."
      return
    end

    snap_name = params[:snap_name]

    if snap_name.blank?
      redirect_to proxmox_snapshots_server_path(@server), alert: "Snapshot name is required."
      return
    end

    result = ProxmoxService.delete_snapshot(@server, snap_name)

    if result[:success]
      redirect_to proxmox_snapshots_server_path(@server), notice: "Snapshot '#{snap_name}' deleted successfully."
    else
      redirect_to proxmox_snapshots_server_path(@server), alert: "Failed to delete snapshot: #{result[:error]}"
    end
  end

  # Run comprehensive diagnostics on a server
  def diagnose
    begin
      @diagnostic_results = SaltHealthCheckService.diagnose(@server)

      respond_to do |format|
        format.html # Will render app/views/servers/diagnose.html.erb
        format.json { render json: @diagnostic_results }
      end
    rescue StandardError => e
      Rails.logger.error "Error running diagnostics for server #{@server.minion_id}: #{e.message}"

      respond_to do |format|
        format.html do
          redirect_to server_path(@server), alert: "Failed to run diagnostics: #{e.message}"
        end
        format.json { render json: { error: e.message }, status: :internal_server_error }
      end
    end
  end

  # Manually refresh Proxmox status for this server
  def manual_refresh_proxmox
    unless @server.proxmox_server?
      redirect_to server_path(@server), alert: "This server is not configured with Proxmox."
      return
    end

    begin
      proxmox_service = ProxmoxService.new(@server.proxmox_api_key)
      status_data = proxmox_service.get_vm_status(
        @server.proxmox_node,
        @server.proxmox_vmid,
        @server.proxmox_type
      )

      if status_data[:success]
        # Update server status based on Proxmox state
        updates = ProxmoxService.map_status_to_server_fields(status_data)
        @server.update!(updates)

        redirect_to server_path(@server), notice: "Proxmox status refreshed: VM is #{status_data[:status]}"
      else
        redirect_to server_path(@server), alert: "Failed to refresh Proxmox status: #{status_data[:error]}"
      end
    rescue StandardError => e
      Rails.logger.error "Error refreshing Proxmox status for #{@server.minion_id}: #{e.message}"
      redirect_to server_path(@server), alert: "Error refreshing Proxmox status: #{e.message}"
    end
  end

  private

  def set_server
    @server = Server.find(params[:id])
  end

  def server_params
    params.require(:server).permit(
      :group_id,
      :environment,
      :location,
      :provider,
      :latitude,
      :longitude,
      :hetzner_api_key_id,
      :hetzner_server_id,
      :enable_hetzner_snapshot,
      :proxmox_api_key_id,
      :proxmox_node,
      :proxmox_vmid,
      :proxmox_type,
      :proxmox_cluster
    )
  end
end
