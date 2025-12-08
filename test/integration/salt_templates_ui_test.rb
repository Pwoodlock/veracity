require 'test_helper'

class SaltTemplatesUITest < ActionDispatch::IntegrationTest
  # Task 3.1: UI Tests for Templates View
  # Test that templates page displays correctly without empty state

  setup do
    # Ensure templates exist for testing
    @user = users(:admin)
    sign_in @user

    # Clear and seed templates
    SaltState.templates.destroy_all
    require Rails.root.join('db', 'seeds', 'salt_templates.rb')
  end

  test "templates page displays templates grouped by category" do
    get admin_salt_states_templates_path

    assert_response :success

    # Should display category headings
    assert_select 'h2', text: /Base/
    assert_select 'h2', text: /Security/

    # Should display template cards
    assert_select '.card', minimum: 1
  end

  test "empty state message is NOT displayed when templates exist" do
    get admin_salt_states_templates_path

    assert_response :success

    # Empty state should not be present
    assert_select 'h3', text: 'No templates available', count: 0
    assert_select 'code', text: 'rails db:seed:salt_templates', count: 0
  end

  test "template cards display with Use Template button" do
    get admin_salt_states_templates_path

    assert_response :success

    # Should have "Use Template" buttons
    assert_select 'button[type="submit"]', text: /Use Template/, minimum: 1

    # Should have view links
    assert_select 'a', text: /View/, minimum: 1
  end
end
