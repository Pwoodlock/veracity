# Specification: System Verification & Validation Suite

## Goal
Create a comprehensive verification and validation suite that ensures all existing Veracity features work correctly, GitHub workflows function properly, security tests pass, and runtime health checks monitor production systems.

## User Stories
- As a developer, I want automated tests to verify all features work so that deployments are reliable
- As an operator, I want runtime health checks so that production issues are detected early
- As a security engineer, I want security tests to validate protections so that vulnerabilities are caught before deployment

## Specific Requirements

**Test Infrastructure Setup**
- Extend existing Minitest framework (do not replace)
- Use FactoryBot for test data isolation with database transaction rollback
- Configure tests to run directly on staging server (46.224.101.253)
- Use `n8n` minion as the safe test target for destructive Salt operations
- Add SimpleCov for code coverage reporting (already configured in test_helper.rb)

**Salt Stack Feature Tests**
- Test minion ping via `SaltService.ping_minion`
- Test key management: `list_keys`, `accept_key`, `reject_key`, `delete_key`
- Test grain sync: `get_grains`, `sync_minion_grains`, `discover_all_minions`
- Test command execution: `run_command`, `execute_shell`, `apply_state`
- Test pillar management: `write_minion_pillar`, `delete_minion_pillar`, `refresh_pillar`
- Mock Salt API responses for unit tests, use `n8n` minion for integration tests

**Dashboard and Real-time Features Tests**
- Test dashboard stats calculation (server counts, command counts)
- Test Action Cable connection and Turbo Stream broadcasts
- Verify DashboardChannel subscription and message routing
- Test server status chart data aggregation

**CVE/Vulnerability Monitoring Tests**
- Existing tests in `test/services/cve_monitoring_service_test.rb` cover unit tests
- Existing integration tests in `test/integration/cve_monitoring_integration_test.rb`
- Add tests for `CveWatchlistsController` CRUD operations
- Test alert threshold logic and notification triggers

**Cloud Integration Tests (Proxmox, Hetzner, NetBird)**
- Test `ProxmoxService` VM listing and snapshot operations (mock API)
- Test `HetznerService` server listing and snapshot creation (mock API)
- Test NetBird setup key management and pillar deployment
- Mock external API calls; do not make real API requests in tests

**Gotify Notification Tests**
- Test `GotifyNotificationService` message sending
- Test `GotifyApiService` application and client management
- Mock Gotify API endpoints for isolated testing

**Task System Tests**
- Test task scheduling via `TaskSchedulerJob`
- Test task execution via `TaskExecutionJob`
- Verify task template instantiation
- Test alert threshold triggers on task completion

**User Management and Authentication Tests**
- Test Devise authentication flow
- Test 2FA setup and verification (mock OTP)
- Test role-based access (admin, operator, viewer)
- Test session management and timeout

**CSRF Protection Verification**
- Create tests that submit forms without valid CSRF tokens
- Verify all POST/PATCH/DELETE endpoints reject requests with invalid tokens
- Test exceptions for API endpoints that use token auth instead

**SQL Injection Testing**
- Test dynamic query parameters in `SaltCliController` command input
- Verify ActiveRecord parameterized queries in server filtering
- Test CVE watchlist search inputs for injection resistance

**Command Injection Testing**
- Test Salt CLI command input sanitization in `SaltCliExecutionJob`
- Verify Python script input escaping in `CveMonitoringService`
- Test shell command construction in `SaltService.execute_shell`
- Ensure user input cannot escape command boundaries

**Session Security Testing**
- Verify session cookies have Secure and HttpOnly flags
- Test session invalidation on logout
- Verify session timeout configuration
- Test concurrent session handling

**Authorization Testing (Pundit)**
- Test `ApplicationPolicy` enforces role hierarchy
- Verify `ServerPolicy` restricts destroy to admins
- Test that viewers cannot access write operations
- Verify scope filtering returns only authorized records

**Encrypted Credentials Verification**
- Verify `HetznerApiKey`, `ProxmoxApiKey`, `NetbirdSetupKey` encrypt sensitive fields
- Test that plaintext values never appear in logs
- Verify encrypted fields are not exposed in JSON responses
- Test credential decryption only occurs when needed

**Rate Limiting Verification**
- Test `Rack::Attack` blocks login attempts after 5 failures
- Verify 2FA verification throttling (5 attempts per minute)
- Test password reset throttling (3 attempts per 5 minutes)
- Verify Salt CLI command throttling (30 per minute)

**GitHub Workflow Fixes - ci.yml**
- Replace `github.event.pull_request.changed_files` condition on docs job
- Use `dorny/paths-filter` action to detect docs changes
- Alternative: Add `paths` filter at workflow trigger level
- Ensure docs job only runs when `docs/**` files change

**GitHub Workflow Fixes - claude.yml**
- Add `contents: write` permission for committing changes
- Add `pull-requests: write` permission for PR comments
- Add `issues: write` permission for issue comments
- Keep existing `id-token: write` and `actions: read`

**GitHub Workflow Fixes - claude-code-review.yml**
- Add `pull-requests: write` permission for posting review comments
- Existing `pull-requests: read` is insufficient for commenting
- Verify `gh pr comment` works with updated permissions

**Runtime Health Check Endpoint**
- Create `/health` endpoint for production monitoring
- Use existing `HealthCheckService` for comprehensive checks
- Return JSON with status, checks array, and timestamps
- Include database, Redis, Salt API, and disk space checks

**Docusaurus Local Development Setup**
- Verify Node.js 20+ is available in WSL environment
- Run `npm install` in `/docs` folder
- Verify `npm run build` completes without errors
- Test `npm run start` launches local dev server on port 3000

## Existing Code to Leverage

**test/test_helper.rb**
- Already configures SimpleCov for coverage reporting
- Includes `sign_in` helper for controller tests
- Has `create_test_server` and `create_test_command` helpers
- Uses Mocha for mocking (`require "mocha/minitest"`)
- Configures parallel test execution

**app/services/salt_service.rb**
- Complete Salt API wrapper with authentication
- All Salt operations are class methods for easy testing
- Thread-safe token caching in Rails.cache
- Custom exception classes for error handling

**app/services/health_check_service.rb**
- Comprehensive health check implementation
- Checks connectivity, uptime, disk, memory, load, minion service
- Returns structured hash with status and details
- `format_report` method generates human-readable output

**config/initializers/rack_attack.rb**
- Complete rate limiting configuration
- Throttles for login, 2FA, password reset, Salt CLI
- Custom HTML response for throttled requests
- Logging via ActiveSupport::Notifications

**Existing Test Files**
- `test/controllers/servers_controller_test.rb` - pattern for controller tests
- `test/services/cve_monitoring_service_test.rb` - pattern for service unit tests
- `test/integration/cve_monitoring_integration_test.rb` - pattern for integration tests
- `test/system/*.rb` - Capybara system tests with headless Chrome

## Out of Scope
- Performance benchmarking and load testing
- Frontend visual regression testing (use DaisyUI agent separately)
- Creating new features beyond verification
- Modifying existing feature behavior
- Database migration changes
- Adding new gem dependencies beyond testing utilities
- Changing the existing Minitest framework to RSpec
- Testing third-party APIs with live credentials
- Stress testing or capacity planning
- Mobile or accessibility testing
