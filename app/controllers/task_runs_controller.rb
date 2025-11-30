class TaskRunsController < ApplicationController
  before_action :set_task, only: [:index, :show, :cancel]
  before_action :set_task_run, only: [:show, :cancel]
  before_action :authorize_user

  def index
    @task_runs = @task ? @task.task_runs : TaskRun.all
    @task_runs = @task_runs.includes(:task, :user)
                           .recent
                           .limit(50)
  end

  def show
    respond_to do |format|
      format.html
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "task_run_#{@task_run.id}",
          partial: 'task_runs/task_run',
          locals: { task_run: @task_run }
        )
      end
    end
  end

  def cancel
    if @task_run.running?
      @task_run.mark_as_cancelled!
      redirect_back fallback_location: @task,
                    notice: 'Task execution was cancelled.'
    else
      redirect_back fallback_location: @task,
                    alert: 'Cannot cancel a task that is not running.'
    end
  end

  private

  def set_task
    @task = Task.find(params[:task_id]) if params[:task_id]
  end

  def set_task_run
    @task_run = @task ? @task.task_runs.find(params[:id]) : TaskRun.find(params[:id])
  end

  def authorize_user
    unless current_user.admin? || current_user.operator?
      redirect_to root_path, alert: 'You are not authorized to access this page.'
    end
  end
end