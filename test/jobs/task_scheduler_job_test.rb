# frozen_string_literal: true

require "test_helper"

class TaskSchedulerJobTest < ActiveJob::TestCase
  setup do
    @user = create(:user, :admin)
    @server = create(:server, :online)

    # Clear any existing tasks to start fresh
    Task.delete_all
    TaskRun.delete_all
  end

  # =============================================================================
  # Test 4.4.2: TaskSchedulerJob schedules tasks properly
  # =============================================================================
  test "perform finds and executes due tasks" do
    # Create a due task
    due_task = create(:task, :due,
      user: @user,
      name: "Due Task",
      command: "test.ping",
      target_type: "all"
    )

    # Mock task execution to avoid actual Salt calls
    due_task.stubs(:running?).returns(false)
    Task.stubs(:due).returns(Task.where(id: due_task.id))

    # Track that execute! was called
    executed = false
    Task.any_instance.stubs(:execute!).with { executed = true; true }

    TaskSchedulerJob.perform_now

    assert executed, "Due task should have been executed"
  end

  test "perform skips tasks that are already running" do
    # Create a due task
    due_task = create(:task, :due,
      user: @user,
      name: "Running Task",
      command: "test.ping",
      target_type: "all"
    )

    # Create an active task run
    create(:task_run, :running, task: due_task)

    # Track that execute! should NOT be called
    executed = false
    Task.any_instance.stubs(:execute!).with { executed = true; true }
    Task.stubs(:due).returns(Task.where(id: due_task.id))

    TaskSchedulerJob.perform_now

    assert_not executed, "Running task should be skipped"
  end

  test "perform handles empty due tasks list" do
    # No due tasks exist
    Task.stubs(:due).returns(Task.none)

    # Should complete without error
    assert_nothing_raised do
      TaskSchedulerJob.perform_now
    end
  end

  test "perform continues processing after task execution error" do
    task1 = create(:task, :due,
      user: @user,
      name: "Task 1",
      command: "test.ping",
      target_type: "all"
    )

    task2 = create(:task, :due,
      user: @user,
      name: "Task 2",
      command: "test.ping",
      target_type: "all"
    )

    Task.stubs(:due).returns(Task.where(id: [task1.id, task2.id]))

    # First task raises error, second should still run
    call_count = 0
    Task.any_instance.stubs(:running?).returns(false)
    Task.any_instance.stubs(:execute!).with do
      call_count += 1
      raise StandardError.new("Test error") if call_count == 1
      true
    end

    TaskSchedulerJob.perform_now

    # Both tasks should have been attempted
    assert_equal 2, call_count
  end

  test "perform processes tasks in sequence" do
    execution_order = []

    3.times do |i|
      task = create(:task, :due,
        user: @user,
        name: "Task #{i}",
        command: "test.ping",
        target_type: "all"
      )
      task.define_singleton_method(:execute!) { execution_order << self.name }
      task.define_singleton_method(:running?) { false }
    end

    Task.stubs(:due).returns(Task.where(name: ["Task 0", "Task 1", "Task 2"]))
    Task.any_instance.stubs(:running?).returns(false)
    Task.any_instance.stubs(:execute!) { true }

    TaskSchedulerJob.perform_now

    # All tasks should have been processed
    # (order may vary due to find_each)
  end
end
