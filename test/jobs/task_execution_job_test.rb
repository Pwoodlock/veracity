# frozen_string_literal: true

require "test_helper"

class TaskExecutionJobTest < ActiveJob::TestCase
  setup do
    @user = create(:user, :admin)
    @server = create(:server, :online, hostname: "test-server", minion_id: "test-minion")
    @task = create(:task,
      user: @user,
      name: "Test Task",
      command: "test.ping",
      target_type: "server",
      target_id: @server.id,
      enabled: true
    )
    @task_run = create(:task_run, task: @task, status: "pending")
  end

  # =============================================================================
  # Test 4.4.1: TaskExecutionJob executes tasks correctly
  # =============================================================================
  test "perform executes task and marks run as completed on success" do
    # Mock the Salt command execution
    mock_salt_output = {
      @server.minion_id => true
    }.to_json

    Open3.stubs(:capture3).returns([mock_salt_output, "", mock(success?: true)])

    TaskExecutionJob.perform_now(@task_run)

    @task_run.reload
    assert_equal "completed", @task_run.status
    assert_not_nil @task_run.output
    assert_not_nil @task_run.completed_at
  end

  test "perform marks run as failed when no targets found" do
    # Create task targeting non-existent server
    @task.update!(target_type: "server", target_id: SecureRandom.uuid)

    TaskExecutionJob.perform_now(@task_run)

    @task_run.reload
    assert_equal "failed", @task_run.status
    assert_match(/No valid targets/, @task_run.output)
  end

  test "perform skips already finished task runs" do
    @task_run.update!(status: "completed", completed_at: Time.current)

    # Should not change anything
    TaskExecutionJob.perform_now(@task_run)

    @task_run.reload
    assert_equal "completed", @task_run.status
  end

  test "perform handles execution errors gracefully" do
    Open3.stubs(:capture3).raises(StandardError.new("Unexpected error"))

    TaskExecutionJob.perform_now(@task_run)

    @task_run.reload
    assert_equal "failed", @task_run.status
    assert_match(/Execution error/, @task_run.output)
  end

  # =============================================================================
  # Test 4.4.2: Task timeout calculation
  # =============================================================================
  test "calculate_timeout returns appropriate timeout for standard commands" do
    job = TaskExecutionJob.new

    # Standard command with 1 target
    timeout = job.calculate_timeout(1, "test.ping")
    assert_equal 150, timeout  # base_timeout(120) + per_target(30)

    # Standard command with 5 targets
    timeout = job.calculate_timeout(5, "disk.usage")
    assert_equal 270, timeout  # 120 + (5 * 30)
  end

  test "calculate_timeout returns longer timeout for upgrade commands" do
    job = TaskExecutionJob.new

    # Upgrade command gets longer timeout
    timeout = job.calculate_timeout(1, "pkg.upgrade")
    assert_equal 2400, timeout  # base(1800) + per_target(600)

    # apt-get upgrade also gets longer timeout
    timeout = job.calculate_timeout(1, "apt-get upgrade")
    assert_equal 2400, timeout
  end

  test "calculate_timeout respects maximum timeout" do
    job = TaskExecutionJob.new

    # Many targets should cap at max
    timeout = job.calculate_timeout(100, "test.ping")
    assert_equal 1800, timeout  # max_timeout for standard

    # Upgrade max is higher
    timeout = job.calculate_timeout(100, "pkg.upgrade")
    assert_equal 3600, timeout  # max_timeout for upgrade
  end

  # =============================================================================
  # Test 4.4.3: Snapshot detection for update tasks
  # =============================================================================
  test "requires_snapshots returns true for upgrade commands" do
    job = TaskExecutionJob.new

    assert job.send(:requires_snapshots?, "pkg.upgrade")
    assert job.send(:requires_snapshots?, "apt-get upgrade")
    assert job.send(:requires_snapshots?, "apt-get dist-upgrade")
    assert job.send(:requires_snapshots?, "yum update")
    assert job.send(:requires_snapshots?, "dnf upgrade")
  end

  test "requires_snapshots returns false for non-upgrade commands" do
    job = TaskExecutionJob.new

    assert_not job.send(:requires_snapshots?, "test.ping")
    assert_not job.send(:requires_snapshots?, "disk.usage")
    assert_not job.send(:requires_snapshots?, "cmd.run echo hello")
  end
end
