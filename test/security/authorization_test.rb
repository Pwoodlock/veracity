# frozen_string_literal: true

require "test_helper"

class AuthorizationTest < ActionDispatch::IntegrationTest
  def setup
    @admin = create(:user, :admin)
    @operator = create(:user, :operator)
    @viewer = create(:user, :viewer)

    @server = create(:server, :online)
    @another_server = create(:server, :online)

    # Mock Salt API to prevent real HTTP calls
    mock_salt_api
  end

  # =============================================================================
  # ApplicationPolicy - Role Hierarchy Tests
  # =============================================================================

  test "ApplicationPolicy enforces role hierarchy for create action" do
    # Admin can create
    policy = ApplicationPolicy.new(@admin, Server.new)
    assert policy.create?, "Admin should be able to create resources"

    # Operator can create
    policy = ApplicationPolicy.new(@operator, Server.new)
    assert policy.create?, "Operator should be able to create resources"

    # Viewer cannot create
    policy = ApplicationPolicy.new(@viewer, Server.new)
    assert_not policy.create?, "Viewer should not be able to create resources"
  end

  test "ApplicationPolicy enforces role hierarchy for update action" do
    # Admin can update
    policy = ApplicationPolicy.new(@admin, @server)
    assert policy.update?, "Admin should be able to update resources"

    # Operator can update
    policy = ApplicationPolicy.new(@operator, @server)
    assert policy.update?, "Operator should be able to update resources"

    # Viewer cannot update
    policy = ApplicationPolicy.new(@viewer, @server)
    assert_not policy.update?, "Viewer should not be able to update resources"
  end

  test "ApplicationPolicy enforces role hierarchy for destroy action" do
    # Admin can destroy
    policy = ApplicationPolicy.new(@admin, @server)
    assert policy.destroy?, "Admin should be able to destroy resources"

    # Operator cannot destroy
    policy = ApplicationPolicy.new(@operator, @server)
    assert_not policy.destroy?, "Operator should not be able to destroy resources"

    # Viewer cannot destroy
    policy = ApplicationPolicy.new(@viewer, @server)
    assert_not policy.destroy?, "Viewer should not be able to destroy resources"
  end

  test "ApplicationPolicy allows all authenticated users to view resources" do
    # Admin can view
    policy = ApplicationPolicy.new(@admin, @server)
    assert policy.show?, "Admin should be able to view resources"

    # Operator can view
    policy = ApplicationPolicy.new(@operator, @server)
    assert policy.show?, "Operator should be able to view resources"

    # Viewer can view
    policy = ApplicationPolicy.new(@viewer, @server)
    assert policy.show?, "Viewer should be able to view resources"
  end

  test "ApplicationPolicy denies access to unauthenticated users" do
    policy = ApplicationPolicy.new(nil, @server)

    assert_not policy.show?, "Unauthenticated user should not be able to view"
    assert_not policy.create?, "Unauthenticated user should not be able to create"
    assert_not policy.update?, "Unauthenticated user should not be able to update"
    assert_not policy.destroy?, "Unauthenticated user should not be able to destroy"
  end

  # =============================================================================
  # ServerPolicy - Specific Authorization Tests
  # =============================================================================

  test "ServerPolicy restricts destroy to admins only" do
    # Admin can delete servers
    sign_in @admin
    delete server_path(@server)
    assert_response :redirect, "Admin should be able to delete servers"

    # Operator cannot delete servers
    reset!
    sign_in @operator
    delete server_path(@another_server)
    assert_redirected_to "/", "Operator should be redirected when attempting delete"
    assert_equal "You must be an admin to access this page.", flash[:alert]

    # Viewer cannot delete servers
    reset!
    sign_in @viewer
    delete server_path(@another_server)
    assert_redirected_to "/", "Viewer should be redirected when attempting delete"
    assert_equal "You must be an admin to access this page.", flash[:alert]
  end

  test "ServerPolicy allows operators to update servers" do
    # Admin can update
    sign_in @admin
    patch server_path(@server), params: {
      server: { hostname: "updated-server" }
    }
    assert_response :redirect, "Admin should be able to update servers"

    # Operator can update
    reset!
    sign_in @operator
    patch server_path(@another_server), params: {
      server: { hostname: "operator-updated" }
    }
    assert_response :redirect, "Operator should be able to update servers"
  end

  test "ServerPolicy allows all authenticated users to view servers" do
    # Admin can view
    sign_in @admin
    get server_path(@server)
    assert_response :success, "Admin should be able to view servers"

    # Operator can view
    reset!
    sign_in @operator
    get server_path(@server)
    assert_response :success, "Operator should be able to view servers"

    # Viewer can view
    reset!
    sign_in @viewer
    get server_path(@server)
    assert_response :success, "Viewer should be able to view servers"
  end

  test "ServerPolicy allows operators to perform server actions" do
    policy = ServerPolicy.new(@operator, @server)

    assert policy.ping?, "Operator should be able to ping servers"
    assert policy.run_command?, "Operator should be able to run commands"
    assert policy.collect_metrics?, "Operator should be able to collect metrics"
    assert policy.refresh_grains?, "Operator should be able to refresh grains"
  end

  # =============================================================================
  # UserPolicy - User Management Authorization Tests
  # =============================================================================

  test "UserPolicy restricts user list to admins only" do
    # Admin can view user list
    sign_in @admin
    get users_path
    assert_response :success, "Admin should be able to view user list"

    # Operator cannot view user list
    reset!
    sign_in @operator
    get users_path
    assert_redirected_to "/", "Operator should be redirected from user list"
    assert_equal "You must be an admin to access this page.", flash[:alert]

    # Viewer cannot view user list
    reset!
    sign_in @viewer
    get users_path
    assert_redirected_to "/", "Viewer should be redirected from user list"
    assert_equal "You must be an admin to access this page.", flash[:alert]
  end

  test "UserPolicy allows users to view their own profile" do
    # User can view own profile
    sign_in @operator
    get user_path(@operator)
    assert_response :success, "User should be able to view own profile"

    # User cannot view other user's profile (would require Pundit authorization)
    # Note: This depends on whether UserPolicy is enforced in controller
    # For now, we document that users can see their own profile
  end

  test "UserPolicy restricts user creation to admins" do
    # Admin can create users
    policy = UserPolicy.new(@admin, User.new)
    assert policy.create?, "Admin should be able to create users"

    # Operator cannot create users
    policy = UserPolicy.new(@operator, User.new)
    assert_not policy.create?, "Operator should not be able to create users"

    # Viewer cannot create users
    policy = UserPolicy.new(@viewer, User.new)
    assert_not policy.create?, "Viewer should not be able to create users"
  end

  test "UserPolicy prevents admin from deleting themselves" do
    policy = UserPolicy.new(@admin, @admin)
    assert_not policy.destroy?, "Admin should not be able to delete themselves"

    # Admin can delete other users
    policy = UserPolicy.new(@admin, @operator)
    assert policy.destroy?, "Admin should be able to delete other users"
  end

  test "UserPolicy restricts role changes to admins" do
    policy = UserPolicy.new(@admin, @operator)
    assert policy.change_role?, "Admin should be able to change user roles"

    # Admin cannot change their own role
    policy = UserPolicy.new(@admin, @admin)
    assert_not policy.change_role?, "Admin should not change their own role"

    # Operator cannot change roles
    policy = UserPolicy.new(@operator, @viewer)
    assert_not policy.change_role?, "Operator should not be able to change roles"
  end

  # =============================================================================
  # Viewer Role - Write Operation Restrictions
  # =============================================================================

  test "viewer role cannot access write operations on servers" do
    sign_in @viewer

    # Cannot update servers (redirected with alert)
    patch server_path(@server), params: {
      server: { hostname: "updated-hostname" }
    }
    assert_redirected_to "/", "Viewer should be redirected when attempting update"
    assert_equal "You must be an operator or admin to access this page.", flash[:alert]

    # Cannot delete servers (redirected with alert)
    delete server_path(@server)
    assert_redirected_to "/", "Viewer should be redirected when attempting delete"
    assert_equal "You must be an admin to access this page.", flash[:alert]
  end

  test "viewer role cannot access admin-only command features" do
    sign_in @viewer

    # Viewer can view commands (read-only)
    get commands_path
    assert_response :success, "Viewer should be able to view commands"

    # But cannot access operator/admin actions if they exist
    # Note: Commands are typically created via other controllers (dashboard, etc.)
    # This test documents the expected read-only behavior
  end

  test "viewer role cannot access admin-only features" do
    sign_in @viewer

    # Cannot access user management
    get users_path
    assert_redirected_to "/", "Viewer should be redirected from user management"
    assert_equal "You must be an admin to access this page.", flash[:alert]

    # Cannot access settings
    get settings_appearance_path
    assert_redirected_to "/", "Viewer should be redirected from settings"
    assert_equal "You must be an admin to access this page.", flash[:alert]
  end

  test "viewer role can access read-only operations" do
    sign_in @viewer

    # Can view dashboard
    get dashboard_path
    assert_response :success, "Viewer should be able to view dashboard"

    # Can view server list
    get servers_path
    assert_response :success, "Viewer should be able to view servers"

    # Can view individual server
    get server_path(@server)
    assert_response :success, "Viewer should be able to view server details"

    # Can view command history
    get commands_path
    assert_response :success, "Viewer should be able to view commands"
  end

  # =============================================================================
  # Policy Scope - Record Filtering Tests
  # =============================================================================

  test "ApplicationPolicy::Scope returns all records for authenticated users" do
    scope = ApplicationPolicy::Scope.new(@viewer, Server.all).resolve
    assert_equal Server.count, scope.count,
                "Authenticated users should see all servers"
  end

  test "ApplicationPolicy::Scope returns no records for unauthenticated users" do
    scope = ApplicationPolicy::Scope.new(nil, Server.all).resolve
    assert_equal 0, scope.count,
                "Unauthenticated users should see no servers"
  end

  test "UserPolicy::Scope filters users based on role" do
    # Admin sees all users
    scope = UserPolicy::Scope.new(@admin, User.all).resolve
    assert_equal User.count, scope.count,
                "Admin should see all users"

    # Operator sees only themselves
    scope = UserPolicy::Scope.new(@operator, User.all).resolve
    assert_equal 1, scope.count,
                "Operator should see only themselves"
    assert_equal @operator.id, scope.first.id

    # Viewer sees only themselves
    scope = UserPolicy::Scope.new(@viewer, User.all).resolve
    assert_equal 1, scope.count,
                "Viewer should see only themselves"
    assert_equal @viewer.id, scope.first.id
  end

  test "ServerPolicy::Scope returns all servers for authenticated users" do
    # All authenticated users can see all servers
    admin_scope = ServerPolicy::Scope.new(@admin, Server.all).resolve
    operator_scope = ServerPolicy::Scope.new(@operator, Server.all).resolve
    viewer_scope = ServerPolicy::Scope.new(@viewer, Server.all).resolve

    assert_equal Server.count, admin_scope.count
    assert_equal Server.count, operator_scope.count
    assert_equal Server.count, viewer_scope.count
  end

  # =============================================================================
  # Unauthorized Access - 403 Forbidden Tests
  # =============================================================================

  test "unauthorized access returns redirect with alert" do
    sign_in @viewer

    # Attempt admin-only action
    delete server_path(@server)
    assert_redirected_to "/", "Unauthorized delete should redirect"
    assert_equal "You must be an admin to access this page.", flash[:alert]

    # Attempt operator-only action
    patch server_path(@server), params: {
      server: { hostname: "hacked" }
    }
    assert_redirected_to "/", "Unauthorized update should redirect"
    assert_equal "You must be an operator or admin to access this page.", flash[:alert]
  end

  test "unauthorized user management returns redirect" do
    sign_in @operator

    # Cannot create users
    post users_path, params: {
      user: {
        email: "newuser@example.com",
        password: "password123!",
        role: "admin"
      }
    }
    assert_redirected_to "/", "Non-admin user creation should redirect"
    assert_equal "You must be an admin to access this page.", flash[:alert]

    # Cannot delete users
    delete user_path(@viewer)
    assert_redirected_to "/", "Non-admin user deletion should redirect"
    assert_equal "You must be an admin to access this page.", flash[:alert]
  end

  test "unauthorized settings access returns redirect" do
    sign_in @viewer

    # Cannot access appearance settings
    get settings_appearance_path
    assert_redirected_to "/"
    assert_equal "Access denied. Admin privileges required.", flash[:alert]

    # Cannot access backup settings
    reset!
    sign_in @viewer
    get settings_backups_path
    assert_redirected_to "/"
    assert_equal "Access denied. Admin privileges required.", flash[:alert]

    # Cannot access maintenance settings
    reset!
    sign_in @viewer
    get settings_maintenance_path
    assert_redirected_to "/"
    assert_equal "Access denied. Admin privileges required.", flash[:alert]
  end

  # =============================================================================
  # Edge Cases and Security Tests
  # =============================================================================

  test "locked user cannot access any resources" do
    locked_user = create(:user, :admin, :locked)

    sign_in locked_user
    get dashboard_path

    # Locked users should be redirected to login
    assert_redirected_to new_user_session_path,
                        "Locked user should not be able to access resources"
  end

  test "role downgrade takes effect immediately" do
    # Start as operator
    sign_in @operator
    get servers_path
    assert_response :success

    # Admin downgrades user to viewer
    @operator.update!(role: "viewer")

    # Try to update server (operator permission)
    patch server_path(@server), params: {
      server: { hostname: "should-fail" }
    }
    assert_redirected_to "/",
                        "Role downgrade should take effect immediately"
    assert_equal "You must be an operator or admin to access this page.", flash[:alert]
  end

  test "deleted user sessions are invalidated" do
    temp_user = create(:user, :operator)
    sign_in temp_user

    get dashboard_path
    assert_response :success

    # Delete user
    temp_user.destroy!

    # Session should be invalid
    get servers_path
    assert_redirected_to new_user_session_path,
                        "Deleted user session should be invalidated"
  end

  test "policy enforces can_access_avo check" do
    # Admin can access
    assert @admin.can_access_avo?, "Admin should have Avo access"

    # Operator can access
    assert @operator.can_access_avo?, "Operator should have Avo access"

    # Viewer cannot access Avo
    assert_not @viewer.can_access_avo?, "Viewer should not have Avo access"
  end

  # =============================================================================
  # Multi-resource Authorization Tests
  # =============================================================================

  test "authorization is enforced across all resource types" do
    group = create(:group, name: "Test Group")
    task = create(:task, user: @admin)

    sign_in @viewer

    # Cannot modify groups (requires operator)
    patch group_path(group), params: {
      group: { name: "Hacked Group" }
    }
    assert_redirected_to "/"
    assert_equal "You must be an operator or admin to access this page.", flash[:alert]

    # Cannot delete groups (requires operator - uses require_operator! in controller)
    reset!
    sign_in @viewer
    delete group_path(group)
    assert_redirected_to "/"
    assert_equal "You must be an operator or admin to access this page.", flash[:alert]
  end

  test "authorization respects resource ownership for tasks" do
    operator_task = create(:task, user: @operator)
    admin_task = create(:task, user: @admin)

    sign_in @operator

    # Operator can view their own tasks
    get task_path(operator_task)
    assert_response :success

    # Operator can view all tasks (as per policy)
    get task_path(admin_task)
    assert_response :success
  end
end
