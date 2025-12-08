require 'test_helper'

class SaltTemplatesSeedTest < ActiveSupport::TestCase
  # Task 1.1: Installation Integration Tests
  # Test that rails db:seed loads salt_templates.rb successfully

  test "seed file loads salt_templates successfully" do
    # Clear existing templates
    SaltState.templates.destroy_all

    # Load the seed file
    assert_nothing_raised do
      require Rails.root.join('db', 'seeds', 'salt_templates.rb')
    end

    # Verify templates were created
    assert SaltState.templates.any?, "Salt templates should be created"
  end

  test "templates are created with is_template flag" do
    # Clear existing templates
    SaltState.templates.destroy_all

    # Load the seed file
    require Rails.root.join('db', 'seeds', 'salt_templates.rb')

    # All seeded states should have is_template: true
    SaltState.templates.each do |template|
      assert template.is_template, "Template #{template.name} should have is_template flag set"
    end
  end

  test "running seed twice does not create duplicates (idempotency)" do
    # Clear existing templates
    SaltState.templates.destroy_all

    # Load seed file first time
    require Rails.root.join('db', 'seeds', 'salt_templates.rb')
    first_count = SaltState.templates.count

    # Load seed file second time
    load Rails.root.join('db', 'seeds', 'salt_templates.rb')
    second_count = SaltState.templates.count

    # Count should remain the same (idempotent)
    assert_equal first_count, second_count, "Seed should be idempotent - no duplicates created"
    assert first_count > 0, "Should have created templates"
  end

  test "seed displays template count summary" do
    # Clear existing templates
    SaltState.templates.destroy_all

    # Capture output
    output = capture_io do
      load Rails.root.join('db', 'seeds', 'salt_templates.rb')
    end.join

    # Should display count information
    assert_match(/Total templates:/, output, "Should display total template count")
    assert_match(/Categories:/, output, "Should display category breakdown")
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
