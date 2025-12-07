class TaskTemplatesController < ApplicationController
  before_action :authorize_admin
  before_action :set_template, only: [:show, :use]

  def index
    @templates_by_category = TaskTemplate.active
                                        .group_by(&:category)
                                        .sort

    @categories = TaskTemplate::CATEGORIES
  end

  def show
    @required_params = @template.required_parameters
    @default_params = @template.default_parameters
  end

  def use
    @task = current_user.tasks.build(
      name: @template.name,
      description: @template.description,
      command: @template.apply_parameters # Use default parameters
    )

    @servers = Server.accessible_by(current_user).order(:hostname)
    @groups = Group.accessible_by(current_user).order(:name)

    render 'tasks/new'
  end

  private

  def set_template
    @template = TaskTemplate.find(params[:id])
  end

  def authorize_admin
    unless current_user.admin? || current_user.operator?
      redirect_to root_path, alert: 'You are not authorized to access this page.'
    end
  end
end