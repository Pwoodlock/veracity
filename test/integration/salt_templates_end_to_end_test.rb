require 'test_helper'

class SaltTemplatesEndToEndTest < ActiveSupport::TestCase
  # Task 4.3: Strategic end-to-end tests to fill critical gaps
  # Focus on complete workflows and edge cases

  test "fresh installation end-to-end - db:setup populates templates" do
    # Simulate fresh installation by clearing all templates
    SaltState.templates.destroy_all

    # Load seeds as db:setup would
    load Rails.root.join('db', 'seeds.rb')

    # Verify templates were created
    assert SaltState.templates.any?, "Templates should be created during fresh installation"
    assert SaltState.templates.count >= 14, "Should create at least 14 templates"

    # Verify different categories exist
    categories = SaltState.templates.pluck(:category).uniq
    assert_includes categories, 'base', "Should include base category"
    assert_includes categories, 'security', "Should include security category"
    assert_includes categories, 'web', "Should include web category"
  end

  test "individual template failure does not stop batch" do
    # Clear existing templates
    SaltState.templates.destroy_all

    # Track created templates
    created_count = 0

    # Override seed_template to simulate one failure
    failure_triggered = false
    original_method = method(:seed_template) rescue nil

    # Define a custom seed_template that fails once
    SaltState.class_eval do
      alias_method :original_save, :save

      define_method(:save) do
        if !defined?(@failure_triggered) && self.name == 'base/init'
          @failure_triggered = true
          false
        else
          original_save
        end
      end
    end

    # Load seed file - should continue despite failure
    begin
      load Rails.root.join('db', 'seeds', 'salt_templates.rb')
    rescue => e
      # Should not raise error
      flunk "Seed should not raise error on individual template failure: #{e.message}"
    end

    # Clean up
    SaltState.class_eval do
      remove_method(:save)
      alias_method :save, :original_save
      remove_method(:original_save)
    end

    # At least some templates should be created despite one failure
    assert SaltState.templates.count >= 10, "Process should continue and create other templates"
  end

  test "template content updates when seed runs again" do
    # Clear and seed first time
    SaltState.templates.destroy_all
    load Rails.root.join('db', 'seeds', 'salt_templates.rb')

    # Get a template
    template = SaltState.templates.find_by(name: 'base/init')
    assert_not_nil template, "Template should exist"

    original_content = template.content

    # Modify the template
    template.update!(content: 'modified content')
    assert_equal 'modified content', template.reload.content

    # Run seed again
    load Rails.root.join('db', 'seeds', 'salt_templates.rb')

    # Content should be restored to original
    template.reload
    assert_equal original_content, template.content, "Seed should update existing templates"
  end

  test "user-created states (is_template: false) are not affected by seeding" do
    # Clear templates
    SaltState.templates.destroy_all

    # Create a user state (not a template)
    user_state = SaltState.create!(
      name: 'my-custom-state',
      state_type: :state,
      category: 'base',
      content: 'my custom content',
      is_template: false
    )

    original_content = user_state.content

    # Run seed
    load Rails.root.join('db', 'seeds', 'salt_templates.rb')

    # User state should remain unchanged
    user_state.reload
    assert_equal original_content, user_state.content, "User states should not be modified"
    assert_equal false, user_state.is_template, "User state should remain non-template"
  end

  test "seed summary output shows correct success counts" do
    # Clear templates
    SaltState.templates.destroy_all

    # Capture output
    output = capture_io do
      load Rails.root.join('db', 'seeds', 'salt_templates.rb')
    end.join

    # Should show success checkmarks for each template
    checkmark_count = output.scan(/✓/).count
    assert checkmark_count >= 14, "Should show checkmarks for successful templates"

    # Should show total count
    assert_match(/Total templates: \d+/, output, "Should display total template count")

    # Should show categories breakdown
    assert_match(/base:/, output, "Should show base category count")
    assert_match(/security:/, output, "Should show security category count")
  end

  test "all template types are seeded correctly" do
    # Clear templates
    SaltState.templates.destroy_all

    # Run seed
    load Rails.root.join('db', 'seeds', 'salt_templates.rb')

    # Verify all expected state types exist
    state_types = SaltState.templates.pluck(:state_type).uniq
    assert_includes state_types, 'state', "Should include state templates"
    assert_includes state_types, 'cloud_profile', "Should include cloud_profile templates"
    assert_includes state_types, 'orchestration', "Should include orchestration templates"
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
