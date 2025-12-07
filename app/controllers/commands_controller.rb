class CommandsController < ApplicationController
  before_action :authenticate_user!

  def index
    # N+1 Query Optimization:
    # - :server - accessed in view for hostname and server_path
    # - :user - accessed in view for user_display_name
    @commands = Command.includes(:server, :user)
                       .order(started_at: :desc)
                       .limit(100)

    # Apply status filter if provided
    if params[:status].present?
      @commands = @commands.where(status: params[:status])
    end

    # Apply server filter if provided
    if params[:server_id].present?
      @commands = @commands.where(server_id: params[:server_id])
    end

    @servers = Server.order(:hostname)
  end

  def show
    @command = Command.find(params[:id])
  end
end
