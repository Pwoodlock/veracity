# frozen_string_literal: true

class GroupsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_group, only: [:show, :edit, :update, :destroy, :manage_servers]

  # SECURITY: Authorization checks to prevent IDOR attacks
  # Viewers: Can only view groups (index, show)
  # Operators: Can manage groups (new, create, edit, update, destroy, manage_servers)
  # Admins: Full access
  before_action :require_operator!, only: [:new, :create, :edit, :update, :destroy, :manage_servers]

  # GET /groups
  def index
    @groups = Group.includes(:servers).ordered
    @ungrouped_count = Server.ungrouped.count
  end

  # GET /groups/:id
  def show
    @servers = @group.servers.order(:hostname)
    @stats = @group.server_stats
    @recent_commands = Command.where(server_id: @group.servers.pluck(:id))
                              .order(created_at: :desc)
                              .limit(10)
    # Get available servers (ungrouped or in other groups) for bulk assignment
    @available_servers = Server.where.not(id: @group.server_ids).order(:hostname)
  end

  # GET /groups/new
  def new
    @group = Group.new
  end

  # GET /groups/:id/edit
  def edit
  end

  # POST /groups
  def create
    @group = Group.new(group_params)

    if @group.save
      redirect_to groups_path, notice: "Group '#{@group.name}' was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /groups/:id
  def update
    if @group.update(group_params)
      redirect_to group_path(@group), notice: "Group '#{@group.name}' was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /groups/:id
  def destroy
    name = @group.name
    servers_count = @group.servers_count

    # Unassign all servers from this group
    @group.servers.update_all(group_id: nil)

    @group.destroy
    redirect_to groups_path, notice: "Group '#{name}' was deleted. #{servers_count} server(s) are now ungrouped."
  end

  # POST /groups/:id/manage_servers
  # Bulk add/remove servers from this group
  def manage_servers
    add_server_ids = params[:add_server_ids] || []
    remove_server_ids = params[:remove_server_ids] || []

    added_count = 0
    removed_count = 0

    # Add servers to this group
    if add_server_ids.any?
      servers_to_add = Server.where(id: add_server_ids)
      added_count = servers_to_add.update_all(group_id: @group.id)
    end

    # Remove servers from this group (set group_id to nil)
    if remove_server_ids.any?
      servers_to_remove = @group.servers.where(id: remove_server_ids)
      removed_count = servers_to_remove.update_all(group_id: nil)
    end

    messages = []
    messages << "#{added_count} server(s) added" if added_count > 0
    messages << "#{removed_count} server(s) removed" if removed_count > 0

    if messages.any?
      redirect_to group_path(@group), notice: messages.join(", ") + " successfully."
    else
      redirect_to group_path(@group), alert: "No servers were selected."
    end
  end

  private

  def set_group
    @group = Group.find(params[:id])
  end

  def group_params
    params.require(:group).permit(:name, :description, :color, :slug)
  end
end
