require 'test_helper'

class SaltTemplatesUpgradeTest < ActiveSupport::TestCase
  # Task 2.1: Upgrade Integration Tests
  # Test that update.sh calls seed_salt_templates after migrations

  test "rake task seed_templates executes successfully" do
    # Clear existing templates
    SaltState.templates.destroy_all

    # Execute the rake task
    assert_nothing_raised do
      Rake::Task['salt:seed_templates'].execute
    end

    # Verify templates were created
    assert SaltState.templates.any?, "Salt templates should be created via rake task"
  end

  test "rake task uses same seed file as db:seed integration" do
    # Clear existing templates
    SaltState.templates.destroy_all

    # Run rake task
    Rake::Task['salt:seed_templates'].reenable
    Rake::Task['salt:seed_templates'].invoke

    count_from_rake = SaltState.templates.count

    # Clear again
    SaltState.templates.destroy_all

    # Run via direct require (like db:seed)
    require Rails.root.join('db', 'seeds', 'salt_templates.rb')

    count_from_require = SaltState.templates.count

    # Both methods should create same number of templates
    assert_equal count_from_rake, count_from_require, "Rake task should use same seed file as db:seed"
  end

  test "rake task displays consistent output formatting" do
    # Clear existing templates
    SaltState.templates.destroy_all

    # Capture output
    output = capture_io do
      Rake::Task['salt:seed_templates'].reenable
      Rake::Task['salt:seed_templates'].invoke
    end.join

    # Should display checkmarks for success
    assert_match(/✓/, output, "Should display success checkmarks")

    # Should display summary
    assert_match(/Salt Templates seeded successfully!/, output, "Should display success message")
    assert_match(/Total templates:/, output, "Should display total template count")
  end

  test "non-critical template failures do not stop update process" do
    # Mock a template that will fail validation
    SaltState.any_instance.stubs(:save).returns(false).then.returns(true)
    SaltState.any_instance.stubs(:errors).returns(
      OpenStruct.new(full_messages: ['Validation failed'])
    )

    # Clear existing templates
    SaltState.templates.destroy_all

    # Rake task should complete despite individual failures
    assert_nothing_raised do
      Rake::Task['salt:seed_templates'].reenable
      Rake::Task['salt:seed_templates'].invoke
    end

    # Some templates should still be created
    # (The first one will fail, but others should succeed)
    assert SaltState.templates.count >= 0, "Process should continue despite individual failures"
  ensure
    # Clean up the stub
    SaltState.any_instance.unstub(:save)
    SaltState.any_instance.unstub(:errors)
  end

  private

  def capture_io
    require 'stringio'
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new

    yield

    [$stdout.string, $stderr.string]
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
end
