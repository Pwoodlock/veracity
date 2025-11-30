# frozen_string_literal: true

module Admin
  #
  # Admin::SaltCliController - Salt Master CLI Interface
  #
  # Provides a full terminal interface for executing Salt commands.
  # Admin-only access with full command history and audit logging.
  #
  class SaltCliController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    # GET /admin/salt_cli
    # Main terminal interface
    def index
      @recent_commands = SaltCliCommand.recent.limit(50)
    end

    # GET /admin/salt_cli/history
    # Command history with filtering
    def history
      @commands = SaltCliCommand.recent
      @commands = @commands.by_user(User.find(params[:user_id])) if params[:user_id].present?
      @commands = @commands.where(status: params[:status]) if params[:status].present?
      @commands = @commands.page(params[:page]).per(50) if defined?(Kaminari)
      @commands = @commands.limit(100) unless defined?(Kaminari)
    end

    # POST /admin/salt_cli/execute
    # Execute a Salt command
    def execute
      command = params[:command].to_s.strip

      if command.blank?
        render json: { error: 'Command cannot be empty' }, status: :unprocessable_entity
        return
      end

      # Create command record
      cli_command = SaltCliCommand.create!(
        user: current_user,
        command: command,
        status: 'pending'
      )

      # Execute in background and stream output
      SaltCliExecutionJob.perform_later(cli_command.id)

      render json: {
        success: true,
        command_id: cli_command.id,
        message: 'Command submitted'
      }
    end

    # GET /admin/salt_cli/command/:id
    # Get command details (for polling fallback)
    def show_command
      command = SaltCliCommand.find(params[:id])
      render json: {
        id: command.id,
        command: command.command,
        output: command.output,
        status: command.status,
        exit_status: command.exit_status,
        started_at: command.started_at,
        completed_at: command.completed_at,
        duration: command.duration
      }
    end

    # DELETE /admin/salt_cli/history/:id
    # Delete a command from history
    def destroy_command
      command = SaltCliCommand.find(params[:id])
      command.destroy

      respond_to do |format|
        format.html { redirect_to admin_salt_cli_history_path, notice: 'Command deleted' }
        format.json { render json: { success: true } }
      end
    end

    # DELETE /admin/salt_cli/history
    # Clear all command history
    def clear_history
      SaltCliCommand.destroy_all

      respond_to do |format|
        format.html { redirect_to admin_salt_cli_history_path, notice: 'History cleared' }
        format.json { render json: { success: true } }
      end
    end

    private

    def authorize_admin!
      unless current_user.admin?
        respond_to do |format|
          format.html do
            flash[:error] = 'You must be an admin to access the Salt CLI'
            redirect_to root_path
          end
          format.json { render json: { error: 'Unauthorized' }, status: :forbidden }
        end
      end
    end
  end
end
