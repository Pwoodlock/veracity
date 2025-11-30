class TasksController < ApplicationController
  before_action :set_task, only: [:show, :edit, :update, :destroy, :execute]
  before_action :authorize_user

  def index
    @tasks = current_user.admin? ? Task.all : current_user.tasks
    @tasks = @tasks.includes(:user, :task_runs)
                   .order(created_at: :desc)
                   .limit(50)

    @stats = {
      total: @tasks.count,
      enabled: @tasks.enabled.count,
      scheduled: @tasks.scheduled.count,
      running: TaskRun.running.count
    }
  end

  def show
    @recent_runs = @task.task_runs
                        .includes(:user)
                        .recent
                        .limit(10)

    @stats = {
      total_runs: @task.task_runs.count,
      success_rate: @task.success_rate,
      avg_duration: @task.average_duration,
      last_run: @task.last_run
    }
  end

  def new
    @task = current_user.tasks.build
    @servers = Server.accessible_by(current_user).order(:hostname)
    @groups = Group.accessible_by(current_user).order(:name)
    @templates = TaskTemplate.active.order(:category, :name)
  end

  def create
    @task = current_user.tasks.build(task_params)

    if @task.save
      redirect_to @task, notice: 'Task was successfully created.'
    else
      @servers = Server.accessible_by(current_user).order(:hostname)
      @groups = Group.accessible_by(current_user).order(:name)
      @templates = TaskTemplate.active.order(:category, :name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @servers = Server.accessible_by(current_user).order(:hostname)
    @groups = Group.accessible_by(current_user).order(:name)
  end

  def update
    if @task.update(task_params)
      redirect_to @task, notice: 'Task was successfully updated.'
    else
      @servers = Server.accessible_by(current_user).order(:hostname)
      @groups = Group.accessible_by(current_user).order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy
    redirect_to tasks_url, notice: 'Task was successfully deleted.'
  end

  def execute
    if @task.running?
      redirect_to @task, alert: 'Task is already running.'
    else
      task_run = @task.execute!(triggered_by: current_user)
      redirect_to task_task_run_path(@task, task_run),
                  notice: 'Task execution started.'
    end
  end

  private

  def set_task
    @task = Task.find(params[:id])
  end

  def task_params
    params.require(:task).permit(
      :name, :description, :command,
      :target_type, :target_id, :target_pattern,
      :cron_schedule, :enabled,
      :alert_on_threshold, :disk_usage_threshold, :memory_usage_threshold, :alert_priority
    )
  end

  def authorize_user
    unless current_user.admin? || current_user.operator?
      redirect_to root_path, alert: 'You are not authorized to access this page.'
    end
  end
end