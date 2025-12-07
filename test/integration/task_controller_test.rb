# frozen_string_literal: true

require "test_helper"

class TaskControllerIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create(:user, :admin)
    @operator = create(:user, :operator)
    @viewer = create(:user, :viewer)

    @server = create(:server, :online)
    @group = create(:group, :production, :with_servers, server_count: 2)

    # Create task template for template-based task creation
    @template = create(:task_template, :updates)

    # Mock Salt API to avoid real API calls
    mock_salt_api
  end

  # =============================================================================
  # Authentication Tests
  # =============================================================================

  test "unauthenticated users are redirected to login" do
    get tasks_path
    assert_redirected_to new_user_session_path
  end

  test "viewer cannot access tasks" do
    sign_in @viewer

    get tasks_path
    assert_redirected_to root_path
  end

  test "operator can access tasks" do
    sign_in @operator

    get tasks_path
    assert_response :success
  end

  test "admin can access tasks" do
    sign_in @admin

    get tasks_path
    assert_response :success
  end

  # =============================================================================
  # Task Creation from Templates
  # =============================================================================

  test "admin can view template use page" do
    sign_in @admin

    get use_task_template_path(@template)
    assert_response :success
    assert_match @template.name, response.body
  end

  test "admin can create task from template" do
    sign_in @admin

    assert_difference("Task.count", 1) do
      post tasks_path, params: {
        task: {
          name: "System Update Task",
          description: @template.description,
          command: @template.apply_parameters,
          target_type: "all",
          enabled: true
        }
      }
    end

    task = Task.last
    assert_equal "System Update Task", task.name
    assert_equal @admin.id, task.user_id
    assert_redirected_to task_path(task)
  end

  test "operator can create task from template" do
    sign_in @operator

    assert_difference("Task.count", 1) do
      post tasks_path, params: {
        task: {
          name: "Operator Task",
          command: "cmd.run 'echo hello'",
          target_type: "all",
          enabled: true
        }
      }
    end

    task = Task.last
    assert_equal @operator.id, task.user_id
  end

  test "create task with server target" do
    sign_in @admin

    assert_difference("Task.count", 1) do
      post tasks_path, params: {
        task: {
          name: "Server Specific Task",
          command: "cmd.run 'df -h'",
          target_type: "server",
          target_id: @server.id,
          enabled: true
        }
      }
    end

    task = Task.last
    assert_equal "server", task.target_type
    assert_equal @server.id, task.target_id
  end

  test "create task with group target" do
    sign_in @admin

    assert_difference("Task.count", 1) do
      post tasks_path, params: {
        task: {
          name: "Group Task",
          command: "cmd.run 'uptime'",
          target_type: "group",
          target_id: @group.id,
          enabled: true
        }
      }
    end

    task = Task.last
    assert_equal "group", task.target_type
    assert_equal @group.id, task.target_id
  end

  test "create task with pattern target" do
    sign_in @admin

    assert_difference("Task.count", 1) do
      post tasks_path, params: {
        task: {
          name: "Pattern Task",
          command: "cmd.run 'whoami'",
          target_type: "pattern",
          target_pattern: "web-*",
          enabled: true
        }
      }
    end

    task = Task.last
    assert_equal "pattern", task.target_type
    assert_equal "web-*", task.target_pattern
  end

  test "create fails with invalid target" do
    sign_in @admin

    assert_no_difference("Task.count") do
      post tasks_path, params: {
        task: {
          name: "Invalid Task",
          command: "cmd.run 'test'",
          target_type: "server",
          target_id: nil,
          enabled: true
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # =============================================================================
  # Task Scheduling Operations
  # =============================================================================

  test "admin can create scheduled task" do
    sign_in @admin

    assert_difference("Task.count", 1) do
      post tasks_path, params: {
        task: {
          name: "Scheduled Task",
          command: "cmd.run 'date'",
          target_type: "all",
          cron_schedule: "0 2 * * *",
          enabled: true
        }
      }
    end

    task = Task.last
    assert_equal "0 2 * * *", task.cron_schedule
    assert_not_nil task.next_run_at
  end

  test "admin can update task schedule" do
    sign_in @admin
    task = create(:task, :unscheduled, user: @admin)

    patch task_path(task), params: {
      task: {
        cron_schedule: "0 */4 * * *"
      }
    }

    assert_redirected_to task_path(task)
    task.reload
    assert_equal "0 */4 * * *", task.cron_schedule
  end

  test "admin can disable task scheduling" do
    sign_in @admin
    task = create(:task, :scheduled, user: @admin)

    patch task_path(task), params: {
      task: {
        enabled: false
      }
    }

    assert_redirected_to task_path(task)
    task.reload
    assert_not task.enabled
  end

  test "admin can enable task scheduling" do
    sign_in @admin
    task = create(:task, :scheduled, :disabled, user: @admin)

    patch task_path(task), params: {
      task: {
        enabled: true
      }
    }

    assert_redirected_to task_path(task)
    task.reload
    assert task.enabled
  end

  # =============================================================================
  # Task Execution
  # =============================================================================

  test "admin can execute task manually" do
    sign_in @admin
    task = create(:task, :target_all, user: @admin)

    assert_difference("TaskRun.count", 1) do
      post execute_task_path(task)
    end

    task_run = TaskRun.last
    assert_equal task.id, task_run.task_id
    assert_equal @admin.id, task_run.user_id
    assert_redirected_to task_task_run_path(task, task_run)
  end

  test "cannot execute task that is already running" do
    sign_in @admin
    task = create(:task, user: @admin)
    create(:task_run, :running, task: task)

    assert_no_difference("TaskRun.count") do
      post execute_task_path(task)
    end

    assert_redirected_to task_path(task)
    follow_redirect!
    assert_match "already running", response.body
  end

  # =============================================================================
  # Task Run History Retrieval
  # =============================================================================

  test "admin can view task run history" do
    sign_in @admin
    task = create(:task, user: @admin)
    runs = create_list(:task_run, 5, :completed, task: task)

    get task_task_runs_path(task)
    assert_response :success
  end

  test "admin can view specific task run" do
    sign_in @admin
    task = create(:task, user: @admin)
    task_run = create(:task_run, :completed, task: task, output: "Task completed successfully")

    get task_task_run_path(task, task_run)
    assert_response :success
    assert_match task_run.output, response.body
  end

  test "task show page displays run statistics" do
    sign_in @admin
    task = create(:task, user: @admin)
    create_list(:task_run, 3, :completed, task: task)
    create_list(:task_run, 1, :failed, task: task)

    get task_path(task)
    assert_response :success
  end

  test "task show page lists recent runs" do
    sign_in @admin
    task = create(:task, user: @admin)
    recent_run = create(:task_run, :completed, task: task)

    get task_path(task)
    assert_response :success
  end

  # =============================================================================
  # Task Templates Index
  # =============================================================================

  test "admin can view task templates" do
    sign_in @admin

    get task_templates_path
    assert_response :success
    assert_match @template.name, response.body
  end

  test "operator can view task templates" do
    sign_in @operator

    get task_templates_path
    assert_response :success
  end

  test "viewer cannot view task templates" do
    sign_in @viewer

    get task_templates_path
    assert_redirected_to root_path
  end

  # =============================================================================
  # Task CRUD Operations
  # =============================================================================

  test "admin can delete task" do
    sign_in @admin
    task = create(:task, user: @admin)

    assert_difference("Task.count", -1) do
      delete task_path(task)
    end

    assert_redirected_to tasks_path
  end

  test "deleting task also deletes associated runs" do
    sign_in @admin
    task = create(:task, user: @admin)
    create_list(:task_run, 3, task: task)

    assert_difference("TaskRun.count", -3) do
      delete task_path(task)
    end
  end

  test "admin can update task details" do
    sign_in @admin
    task = create(:task, user: @admin, name: "Original Name")

    patch task_path(task), params: {
      task: {
        name: "Updated Name",
        description: "Updated description"
      }
    }

    assert_redirected_to task_path(task)
    task.reload
    assert_equal "Updated Name", task.name
    assert_equal "Updated description", task.description
  end
end
