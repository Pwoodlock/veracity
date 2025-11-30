class TaskSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    # Find all tasks that are due to run
    due_tasks = Task.due

    Rails.logger.info "TaskScheduler: Found #{due_tasks.count} due tasks"

    due_tasks.find_each do |task|
      # Skip if already running
      next if task.running?

      Rails.logger.info "TaskScheduler: Executing task '#{task.name}' (ID: #{task.id})"

      begin
        task.execute!
      rescue StandardError => e
        Rails.logger.error "TaskScheduler: Failed to execute task '#{task.name}': #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end
end