# Task Breakdown: Auto-Seed Salt State Templates

## Overview

**Feature:** Automatically populate 15 Salt State templates during installation and upgrades

**Total Tasks:** 12 grouped into 4 task groups

**Estimated Complexity:** Low (leveraging existing code, no schema changes)

**Files Modified:**
- `/mnt/d/Projects/veracity/db/seeds.rb` (add require statement)
- `/mnt/d/Projects/veracity/scripts/update.sh` (add seeding function)
- `/mnt/d/Projects/veracity/app/views/admin/salt_states/templates.html.erb` (remove empty state)

**Existing Code Leveraged:**
- `db/seeds/salt_templates.rb` (complete implementation exists)
- `lib/tasks/salt.rake` (rake task already defined)
- `seed_template` helper (idempotent with find_or_initialize_by)

## Task List

### Installation Integration

#### Task Group 1: Auto-seed during fresh installation
**Dependencies:** None

- [x] 1.0 Complete installation integration
  - [x] 1.1 Write 2-4 focused tests for seed file loading
    - Test: `rails db:seed` loads salt_templates.rb successfully
    - Test: Templates are created in database with is_template flag
    - Test: Running seed twice doesn't create duplicates (idempotency)
    - Test: Seed output displays template count summary
    - Limit to 4 tests maximum - focus only on critical seeding behaviors
  - [x] 1.2 Modify db/seeds.rb to require salt_templates
    - Add after line 215 (after TaskTemplate seeding)
    - Add separator comment: "# ==========================================="
    - Add info message: `puts "\nSeeding Salt State Templates..."`
    - Add require: `require Rails.root.join('db', 'seeds', 'salt_templates.rb')`
    - Follow pattern from TaskTemplate seeding (lines 35-215)
  - [x] 1.3 Verify seed file output formatting
    - Ensure seed_template helper outputs checkmarks/errors consistently
    - Verify final summary shows total template count
    - Confirm output matches existing Salt rake task formatting
    - Check that categories breakdown is displayed
  - [x] 1.4 Ensure installation integration tests pass
    - Run ONLY the 2-4 tests written in 1.1
    - Verify `rails db:seed` completes without errors
    - Confirm all 15 templates are created in database
    - Do NOT run the entire test suite at this stage

**Acceptance Criteria:**
- The 2-4 tests written in 1.1 pass
- `rails db:seed` automatically loads all 15 templates
- Templates have `is_template: true` flag set
- Running seed multiple times is idempotent (no duplicates)
- Output displays clear summary with template counts
- Installation script already calls `rails db:seed` (no changes needed)

### Upgrade Integration

#### Task Group 2: Auto-refresh during system upgrades
**Dependencies:** Task Group 1

- [x] 2.0 Complete upgrade integration
  - [x] 2.1 Write 2-4 focused tests for upgrade seeding
    - Test: update.sh calls seed_salt_templates function after migrations
    - Test: Seeding function executes as deploy user with proper environment
    - Test: Non-critical template failures don't stop update process
    - Test: Function displays info/success messages consistently
    - Limit to 4 tests maximum - focus only on critical upgrade behaviors
  - [x] 2.2 Add seed_salt_templates function to update.sh
    - Add function definition after line 191 (after run_migrations function)
    - Function name: `seed_salt_templates()`
    - Execute command: `sudo -u "$DEPLOY_USER" bash -c "export PATH=/home/${DEPLOY_USER}/.rbenv/shims:\$PATH && RAILS_ENV=production bundle exec rails db:seed:salt_templates"`
    - Use `|| warning "Salt template seeding had errors (check logs)"` pattern for resilience
    - Follow existing script conventions for info/success messages
  - [x] 2.3 Call seed_salt_templates in main() function
    - Add call after run_migrations (after line 280)
    - Order: `run_migrations` -> `seed_salt_templates` -> `precompile_assets`
    - Display info message: "Refreshing Salt State templates..."
    - Display success message after completion
  - [x] 2.4 Verify rake task compatibility
    - Confirm `lib/tasks/salt.rake` line 5 task exists
    - Test manual invocation: `rails db:seed:salt_templates`
    - Verify task uses same seed file as db:seed integration
    - Ensure output formatting is consistent
  - [x] 2.5 Ensure upgrade integration tests pass
    - Run ONLY the 2-4 tests written in 2.1
    - Verify update.sh calls seeding after migrations
    - Test that seeding failures don't block updates
    - Do NOT run the entire test suite at this stage

**Acceptance Criteria:**
- The 2-4 tests written in 2.1 pass
- `seed_salt_templates()` function added to update.sh
- Function executes as deploy user with proper rbenv PATH
- Seeding runs automatically after migrations during upgrades
- Non-critical failures log warnings but don't stop update
- Success/error messages follow existing script conventions

### UI Update

#### Task Group 3: Remove empty state message
**Dependencies:** Task Group 1

- [x] 3.0 Complete UI updates
  - [x] 3.1 Write 2-3 focused tests for templates view
    - Test: Templates page displays templates grouped by category
    - Test: Empty state message is NOT displayed when templates exist
    - Test: Template cards display with "Use Template" button
    - Limit to 3 tests maximum - focus only on critical UI behaviors
  - [x] 3.2 Remove empty state block from templates view
    - File: `/mnt/d/Projects/veracity/app/views/admin/salt_states/templates.html.erb`
    - Remove lines 86-99 (empty state div)
    - Keep the `<% if @templates.any? %>` conditional structure
    - Preserve template card layout (lines 33-85)
  - [x] 3.3 Verify templates view functionality
    - Confirm templates display grouped by category
    - Check that "Use Template" button clones templates correctly
    - Verify template cards show preview, type badge, and description
    - Test responsive layout (desktop/tablet/mobile)
  - [x] 3.4 Ensure UI tests pass
    - Run ONLY the 2-3 tests written in 3.1
    - Verify templates page renders without empty state
    - Confirm template cards display correctly
    - Do NOT run the entire test suite at this stage

**Acceptance Criteria:**
- The 2-3 tests written in 3.1 pass
- Empty state message removed from templates view
- Templates page always shows templates (seeded automatically)
- UI displays templates grouped by category with proper styling
- "Use Template" functionality works correctly
- No visual regressions in template cards or layout

### Testing & Verification

#### Task Group 4: Integration testing and gap analysis
**Dependencies:** Task Groups 1-3

- [x] 4.0 Review and fill critical testing gaps
  - [x] 4.1 Review existing tests from previous task groups
    - Review the 2-4 tests from installation integration (Task 1.1)
    - Review the 2-4 tests from upgrade integration (Task 2.1)
    - Review the 2-3 tests from UI updates (Task 3.1)
    - Total existing tests: approximately 6-11 tests
  - [x] 4.2 Analyze test coverage gaps for THIS feature only
    - Identify critical workflows lacking test coverage
    - Focus ONLY on gaps related to auto-seeding feature
    - Prioritize end-to-end workflows over unit test gaps
    - Check: Fresh install workflow (db:setup -> templates exist)
    - Check: Upgrade workflow (update.sh -> templates refreshed)
    - Check: Idempotency (multiple seed runs -> no duplicates)
    - Check: Error resilience (partial failures -> process continues)
  - [x] 4.3 Write up to 6 additional strategic tests maximum
    - Add maximum of 6 new tests to fill identified critical gaps
    - Test: Fresh installation end-to-end (db:setup populates templates)
    - Test: Upgrade end-to-end (update.sh refreshes templates)
    - Test: Individual template failure doesn't stop batch
    - Test: Template content updates when seed runs again
    - Test: User-created states (is_template: false) are not affected
    - Test: Seed summary output shows correct success/failure counts
    - Do NOT write comprehensive coverage for all scenarios
    - Skip edge cases unless business-critical
  - [x] 4.4 Run feature-specific tests only
    - Run ONLY tests related to auto-seeding feature
    - Expected total: approximately 12-17 tests maximum
    - Verify installation workflow: `rails db:seed` creates templates
    - Verify upgrade workflow: update.sh refreshes templates
    - Verify idempotency: running multiple times safe
    - Verify error handling: non-critical failures don't block
    - Do NOT run the entire application test suite

**Acceptance Criteria:**
- All feature-specific tests pass (approximately 12-17 tests total)
- Critical auto-seeding workflows are covered
- No more than 6 additional tests added when filling gaps
- Testing focused exclusively on this feature's requirements
- Fresh installation workflow verified
- Upgrade workflow verified
- Idempotent behavior confirmed
- Error resilience validated

## Execution Order

Recommended implementation sequence:

1. **Installation Integration** (Task Group 1)
   - Modify db/seeds.rb to auto-load templates
   - Test with `rails db:seed`
   - Verify templates created in database

2. **Upgrade Integration** (Task Group 2)
   - Add seed_salt_templates() function to update.sh
   - Call function after migrations in main()
   - Test with manual update.sh run (or dry-run)

3. **UI Update** (Task Group 3)
   - Remove empty state from templates view
   - Verify templates display correctly
   - Test "Use Template" functionality

4. **Testing & Verification** (Task Group 4)
   - Review all tests from previous groups
   - Fill critical gaps (max 6 additional tests)
   - Run feature-specific test suite

## Implementation Notes

### Idempotency Strategy

The existing `seed_template` helper in `db/seeds/salt_templates.rb` already implements idempotency:

```ruby
def seed_template(attrs)
  state = SaltState.find_or_initialize_by(name: attrs[:name], state_type: attrs[:state_type])
  state.assign_attributes(attrs.merge(is_template: true))
  if state.save
    puts "  ✓ #{attrs[:state_type]}: #{attrs[:name]}"
  else
    puts "  ✗ #{attrs[:state_type]}: #{attrs[:name]} - #{state.errors.full_messages.join(', ')}"
  end
end
```

Key points:
- `find_or_initialize_by(name:, state_type:)` prevents duplicates
- Running seed multiple times updates existing templates
- User-created states (is_template: false) are never affected
- Individual failures are logged but don't stop the batch

### Error Handling

Both installation and upgrade seeding should be resilient:

**Installation (db/seeds.rb):**
- Individual template failures are logged with ✗ symbol
- Batch continues processing all 15 templates
- Summary shows success/failure counts
- Only critical errors (DB down) should stop installation

**Upgrade (update.sh):**
- Use `|| warning` pattern for non-critical failures
- Display warning message if some templates fail
- Continue with asset precompilation and service restart
- Admin can manually re-run: `rails db:seed:salt_templates`

### Testing Strategy

Follow minimal testing approach:

**During Development (Groups 1-3):**
- Write 2-4 focused tests per group (total ~8 tests)
- Test only critical behaviors (seeding, idempotency, UI rendering)
- Run only newly written tests, not entire suite
- Focus on "does it work" rather than exhaustive coverage

**Gap Analysis (Group 4):**
- Review all previous tests (~8 tests)
- Add maximum 6 strategic tests for critical gaps
- Focus on end-to-end workflows
- Total expected: ~14 tests maximum

**What NOT to test:**
- Individual template content (already validated by SaltState model)
- All edge cases for YAML parsing (out of scope)
- Performance under load (15 templates is trivial)
- All possible error scenarios (focus on critical path)

### Rollback Approach

If issues occur after deployment:

**Option 1: Re-run seeding**
```bash
# Restore templates to correct state
sudo -u deploy bash -c "cd /opt/veracity/app && RAILS_ENV=production bundle exec rails db:seed:salt_templates"
```

**Option 2: Delete and re-seed**
```ruby
# In Rails console
SaltState.templates.destroy_all
# Then re-run seed
```

**Option 3: Restore from backup**
- update.sh creates backup at `/opt/backups/veracity-YYYYMMDD-HHMMSS/`
- Restore database from backup if needed
- User-created states are safe (different is_template flag)

### Performance Considerations

**Seeding Speed:**
- 15 templates take ~1-2 seconds to seed
- Negligible impact on installation/upgrade time
- `find_or_initialize_by` is efficient (indexed)
- No external API calls or network dependencies

**Installation Time:**
- Fresh install already runs db:seed
- Adding salt_templates adds <5 seconds
- Total install time: still under 10 minutes

**Upgrade Time:**
- Upgrade already runs db:migrate
- Adding template refresh adds <5 seconds
- Total update time: still under 5 minutes

## Success Metrics

**Functional Success:**
- [x] Fresh installations have all 15 templates pre-loaded
- [x] System upgrades refresh templates with latest content
- [x] Templates view never shows empty state
- [x] Idempotent - safe to run multiple times
- [x] Error resilient - continues on individual failures

**Testing Success:**
- [x] 12-17 focused tests cover critical workflows
- [x] All feature tests pass
- [x] No regressions in existing functionality

**User Experience:**
- [x] Admins can immediately use Salt Editor after installation
- [x] Templates automatically updated during upgrades
- [x] No manual seeding required
- [x] Clear output messages during seeding process

## Files Reference

**Files Modified:**
- `/mnt/d/Projects/veracity/db/seeds.rb` (line 216: add require) - COMPLETED
- `/mnt/d/Projects/veracity/scripts/update.sh` (line 191: add function, line 280: call function) - COMPLETED
- `/mnt/d/Projects/veracity/app/views/admin/salt_states/templates.html.erb` (lines 86-99: remove) - COMPLETED

**Files to Reference (no changes):**
- `/mnt/d/Projects/veracity/db/seeds/salt_templates.rb` (complete implementation)
- `/mnt/d/Projects/veracity/lib/tasks/salt.rake` (rake task exists)
- `/mnt/d/Projects/veracity/app/models/salt_state.rb` (validations and scopes)
- `/mnt/d/Projects/veracity/scripts/install/app-setup.sh` (already calls db:seed at line 353)

**Test Files Created:**
- `/mnt/d/Projects/veracity/test/integration/salt_templates_seed_test.rb` - COMPLETED
- `/mnt/d/Projects/veracity/test/integration/salt_templates_upgrade_test.rb` - COMPLETED
- `/mnt/d/Projects/veracity/test/integration/salt_templates_ui_test.rb` - COMPLETED
- `/mnt/d/Projects/veracity/test/integration/salt_templates_end_to_end_test.rb` - COMPLETED

## Standards Compliance

This task breakdown aligns with project standards:

**Testing Standards:**
- Minimal tests during development (2-4 per group)
- Focus on core user flows only
- Test behavior, not implementation
- Defer edge case testing
- Maximum 6 additional tests in gap analysis

**Coding Style:**
- Follow existing patterns (TaskTemplate seeding, update.sh functions)
- Consistent naming conventions
- Remove dead code (empty state UI)
- DRY principle (leverage existing seed_template helper)

**Migration Standards:**
- No database migrations needed
- Existing schema supports templates
- Idempotent operations (safe to run multiple times)

**Backward Compatibility:**
- No breaking changes
- Existing user states unaffected
- Templates can still be manually seeded if needed
