# frozen_string_literal: true

# Mailer for sending notifications to administrators
class AdminMailer < ApplicationMailer
  # Notify admins when a new user is created
  # @param user [User] The newly created user
  # @param created_by [User] The admin who created the user
  def new_user_created(user, created_by)
    @user = user
    @created_by = created_by
    @login_url = root_url

    mail(
      to: admin_emails,
      subject: "New User Created: #{user.email}"
    )
  end

  # Notify admins when a server goes offline
  # @param server [Server] The server that went offline
  def server_offline_alert(server)
    @server = server
    @server_url = server_url(server)

    mail(
      to: admin_emails,
      subject: "Server Offline Alert: #{server.hostname}"
    )
  end

  # Notify admins when a scheduled task fails
  # @param task_execution [TaskExecution] The failed task execution
  def task_execution_failed(task_execution)
    @task_execution = task_execution
    @task = task_execution.scheduled_task
    @execution_url = task_execution_url(task_execution)

    mail(
      to: admin_emails,
      subject: "Task Execution Failed: #{@task.name}"
    )
  end

  private

  # Get all admin email addresses
  # @return [Array<String>] List of admin emails
  def admin_emails
    User.where(role: 'admin').pluck(:email)
  end
end
