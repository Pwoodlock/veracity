# Spec Requirements: Auto-Seed Salt State Templates

## Initial Description
Automatically seed Salt State templates from db/seeds/salt_templates.rb during both initial installation and system upgrades. The seed file already exists and contains idempotent code to create or update Salt State templates (states, pillars, cloud profiles, and orchestrations) in the PostgreSQL database.

**Current State:**
- Seed file exists at: /mnt/d/Projects/veracity/db/seeds/salt_templates.rb
- Rake task exists: `rails salt:seed_templates`
- Templates are stored in PostgreSQL `salt_states` table, NOT on filesystem
- Templates are only written to /srv/salt/ on Salt Master when deployed

**Goal:**
Ensure templates are automatically loaded into the database during:
1. Fresh installation (rails db:setup / db:seed)
2. System upgrades (when deploying new versions)

## Requirements Discussion

### First Round Questions

**Q1:** When should Salt templates be automatically populated - during installation only, or also during upgrades?
**Answer:** BOTH - during installation via `rails db:seed` AND during upgrades after `rails db:migrate` runs.

**Q2:** Should we use seed hooks (recommended Rails convention) or explicit installer script calls?
**Answer:** Use Rails seed hooks (Option A - add `require Rails.root.join('db', 'seeds', 'salt_templates.rb')` to db/seeds.rb). This is standard Rails convention and runs automatically during installation.

**Q3:** For upgrades, should we create a rake task that can be called in scripts/update.sh?
**Answer:** YES - create `rails db:seed:salt_templates` rake task to be called in scripts/update.sh after line 189 (after db:migrate).

**Q4:** What error handling is needed if a template fails to seed?
**Answer:** Continue processing all templates even if one fails, log detailed error messages, and display summary (e.g., "12/14 templates seeded successfully, 2 failed"). Only fail installation if database is down or critical error occurs.

**Q5:** Should we remove the empty state UI message once templates are populated?
**Answer:** YES - remove the empty state message from templates.html.erb since templates will always be present after seeding.

**Q6:** Is there any concern about the current pillar architecture or robustness?
**Answer:** NO - User currently only uses one pillar file for NetBird deployment and wants to ensure nothing breaks. The current implementation (`SaltService.write_minion_pillar` method) is working fine. This is OUT OF SCOPE for this spec.

**Q7:** Are there plans to integrate Kamal deployment, or should we stick with the custom update.sh script?
**Answer:** NO Kamal integration - The project has Kamal gem present but marked `require: false` with no config files. The custom `scripts/update.sh` script is the deployment method in use and should be enhanced to call the salt templates seeding.

**Q8:** Should toast notifications be added for successful/failed template seeding in the UI?
**Answer:** NO - Create a separate spec for UI improvements. This spec focuses solely on auto-seeding functionality during installation/upgrades.

### Existing Code to Reference

**Similar Features Identified:**
- Feature: TaskTemplate seeding - Path: `/mnt/d/Projects/veracity/db/seeds.rb` (lines 35-215)
- Pattern to follow: Uses `find_or_create_by!` with idempotent logic
- Implementation: Already seeds task templates successfully with similar approach

**Salt Templates Implementation:**
- File: `/mnt/d/Projects/veracity/db/seeds/salt_templates.rb` (807 lines)
- Contains: 14+ templates (states, pillars, cloud profiles, orchestrations)
- Helper method: `seed_template(attrs)` uses `find_or_initialize_by` with `save` error handling
- Categories: base, security, web, database, docker, monitoring, cloud, orchestration
- Already idempotent: Safe to run multiple times

**Deployment Scripts:**
- Installation: `/mnt/d/Projects/veracity/scripts/install/app-setup.sh` line 353 runs `rails db:seed`
- Upgrade: `/mnt/d/Projects/veracity/scripts/update.sh` line 189 runs `rails db:migrate`
- Rake task exists: `/mnt/d/Projects/veracity/lib/tasks/salt.rake` line 5 defines `salt:seed_templates`

**Database Model:**
- Model: `/mnt/d/Projects/veracity/app/models/salt_state.rb`
- Table: `salt_states`
- Key fields: name, state_type, content, description, category, is_template
- Scope: `SaltState.templates` filters templates
- Validations: Presence, uniqueness (name + state_type), format checks

### Follow-up Questions

**Follow-up 1:** Should we include the Toast notification fix (replacing popups with DaisyUI Toast) in THIS spec, or create a separate spec for UI notification improvements?

**Answer:** Option B - Create separate spec for UI improvements. User confirmed popups exist when running commands and wants Toast-type notifications with DaisyUI, but this should be its own spec.

**Follow-up 2:** You mentioned "Pillars need to be made robust too." Can you clarify what specifically needs to be robust?

**Answer:** User only uses one pillar file for NetBird deployment currently. Wants to ensure nothing breaks. Current pillar implementation is working fine. This is OUT OF SCOPE for this spec.

**Follow-up 3:** For error handling - confirm the recommended approach (log individual failures, continue, report summary) is acceptable?

**Answer:** YES to all - continue on failure, log errors, report summary. Do not block installation for individual template failures.

**Follow-up 4:** For upgrades, when should auto-seeding run? What deployment tooling do you use?

**Answer:** User doesn't know deployment details. Research revealed:
- Kamal gem present in Gemfile but marked `require: false`
- NO Kamal config files found
- Custom `scripts/update.sh` script is used for updates
- Update process: stop services → git pull → bundle → yarn → **db:migrate** → assets:precompile → start services
- Solution: Add `rails db:seed:salt_templates` call after db:migrate (line 189)

## Visual Assets

### Files Provided:
No visual assets provided.

### Visual Insights:
No visual insights available - this is a backend/automation feature with no UI changes except removing an empty state message.

## Requirements Summary

### Functional Requirements

**Core Functionality:**
- Auto-populate ALL 14+ Salt templates during fresh installation
- Auto-update templates during system upgrades (when db:migrate runs)
- Idempotent seeding - safe to run multiple times without duplicates
- Update existing templates with latest content from seed file
- Remove empty state UI message from templates view

**Installation Behavior:**
- Templates are seeded automatically via `rails db:seed` during installation
- Installation script (`scripts/install/app-setup.sh` line 353) already calls `rails db:seed`
- Implementation: Add `require Rails.root.join('db', 'seeds', 'salt_templates.rb')` to `db/seeds.rb`
- This runs automatically during installation - no script changes needed

**Upgrade Behavior:**
- Rake task `rails db:seed:salt_templates` already exists at `lib/tasks/salt.rake` line 5
- Call this task in `scripts/update.sh` after line 189 (after `rails db:migrate`)
- Also available for manual invocation by admins who want to refresh templates

**Error Handling:**
- Continue processing all templates even if one fails
- Log failures with detailed error messages (template name, type, error)
- Display summary at end: "X/Y templates seeded successfully, Z failed"
- Only fail installation if database is unreachable or critical system error
- Non-critical template failures should not stop installation/upgrade

**Success Criteria:**
- Fresh installations have all templates pre-loaded in database
- System upgrades refresh templates with latest content
- Existing user-created states are not affected (is_template flag differentiates them)
- Installation/upgrade scripts succeed even if a few templates fail
- Admins can manually re-seed templates via rake task

### Reusability Opportunities

**Existing Patterns to Follow:**
- TaskTemplate seeding in `db/seeds.rb` (lines 35-215) - uses similar find_or_create_by pattern
- Salt rake tasks in `lib/tasks/salt.rake` - follow same output formatting conventions
- Installer logging in `scripts/install/app-setup.sh` - use step/success/error functions

**Code Already Written:**
- `db/seeds/salt_templates.rb` - Complete implementation exists with 14+ templates
- `lib/tasks/salt.rake` line 5 - Rake task already defined as `salt:seed_templates`
- Helper method `seed_template(attrs)` - Already implements idempotent seeding logic

**SaltState Model Features to Use:**
- `SaltState.templates` scope - Filter only templates (is_template: true)
- `find_or_initialize_by(name:, state_type:)` - Ensures uniqueness
- Validations automatically check format and category

### Scope Boundaries

**In Scope:**
1. Add `require Rails.root.join('db', 'seeds', 'salt_templates.rb')` to `db/seeds.rb` (after TaskTemplate seeding, around line 216)
2. Modify `scripts/update.sh` to call `rails db:seed:salt_templates` after db:migrate (after line 189)
3. Update templates view to remove empty state message (since templates will always exist)
4. Verify rake task `salt:seed_templates` works correctly
5. Test idempotent behavior - running multiple times should not create duplicates
6. Ensure error handling allows installation to continue if some templates fail

**Out of Scope:**
- Toast notifications for template seeding (separate UI improvement spec - confirmed by user)
- Pillar architecture changes or robustness improvements (current implementation is fine - confirmed by user)
- Kamal deployment integration (not being used - verified via research)
- Changes to template content itself (db/seeds/salt_templates.rb is already complete)
- UI for managing templates (already exists in templates controller/views)
- Filesystem deployment of templates to /srv/salt/ (separate deployment concern)

**Future Enhancements (Not This Spec):**
- UI toast notifications for seeding success/failure (user wants DaisyUI Toast notifications)
- Dashboard widget showing template count/status
- Admin UI to trigger re-seeding from web interface
- Template versioning or rollback capability
- Import/export templates functionality

### Technical Considerations

**Integration Points:**
- `db/seeds.rb` - Add require statement to auto-load salt_templates.rb during db:seed
- `scripts/update.sh` - Add rake task call after migrations (line 189)
- `app/views/salt_states/templates.html.erb` - Remove empty state message
- Rake task `lib/tasks/salt.rake` - Already exists, just needs to be called from update script

**Deployment Method:**
- Custom `scripts/update.sh` script is used (NOT Kamal)
- Update process flow:
  1. Stop services (systemctl stop server-manager, server-manager-sidekiq)
  2. Git pull from GitHub main branch
  3. Bundle install
  4. Yarn install
  5. **`rails db:migrate`** (line 189)
  6. **INSERT HERE: `rails db:seed:salt_templates`** (NEW)
  7. `rails assets:precompile`
  8. Start services (systemctl start server-manager, server-manager-sidekiq)

**Existing System Constraints:**
- PostgreSQL database stores templates (not filesystem)
- Templates only written to Salt Master filesystem when deployed via UI or API
- Installer uses Mise for Ruby environment management
- Update script runs as root, executes Rails commands as deploy user

**Error Resilience:**
- Database must be available (installer already verifies this at line 299-320)
- Individual template failures should log but not stop seeding
- Summary output should clearly show success/failure counts
- Exit code 0 even if some templates fail (only exit 1 on critical errors)

**Testing Approach:**
- Test fresh installation: verify all templates exist in database after install completes
- Test upgrade: verify templates are refreshed after running update.sh
- Test idempotency: run seeding multiple times, verify no duplicates created
- Test partial failure: simulate one template failing, verify others still seed
- Test empty state removal: verify templates view doesn't show "no templates" message
- Test existing user templates: verify user-created states (is_template: false) are not affected

**Rollback Strategy:**
- Templates are idempotent - re-running seed will restore correct state
- If needed, can delete all templates via Rails console: `SaltState.templates.destroy_all`
- Then re-run: `rails db:seed:salt_templates` to restore
- User-created states are safe (is_template: false) and won't be affected by seeding
- Database backups (if taken) can restore previous state
- Update script creates backup at line 26 before making changes

**Performance Considerations:**
- 14+ templates take ~1-2 seconds to seed (negligible)
- No significant impact on installation/upgrade time
- find_or_initialize_by is efficient (indexed on name + state_type)
- No external API calls or network dependencies
- Templates remain in database until deployed to filesystem

## Implementation Approach

### Option A: Rails Seed Hook (RECOMMENDED)

**Pros:**
- Standard Rails convention
- Runs automatically during `rails db:seed` (installation)
- Minimal code changes (one line in db/seeds.rb)
- Idiomatic and expected behavior

**Cons:**
- None

**Implementation:**
Add to `/mnt/d/Projects/veracity/db/seeds.rb` after line 215 (after TaskTemplate seeding):

```ruby
# ===========================================
# Salt State Templates
# ===========================================

puts "\nSeeding Salt State Templates..."
require Rails.root.join('db', 'seeds', 'salt_templates.rb')
```

### Option B: Explicit Installer Script Call

**Pros:**
- More explicit control
- Could add custom logging

**Cons:**
- Non-standard approach
- Requires modifying installer script
- Maintenance burden

**Not Recommended:** Rails convention is better.

### Option C: Rails Initializer or Post-Migration Hook

**Pros:**
- Runs automatically on every startup/migration

**Cons:**
- Overhead on every boot
- Runs more than necessary
- Not appropriate for seeding data

**Not Recommended:** Initializers should not seed data.

### Upgrade Implementation

**For Upgrades:**
Modify `/mnt/d/Projects/veracity/scripts/update.sh` after line 189:

```bash
# Run database migrations
run_migrations() {
  info "Running database migrations..."

  cd "$APP_DIR"
  sudo -u "$DEPLOY_USER" bash -c "export PATH=/home/${DEPLOY_USER}/.rbenv/shims:\$PATH && RAILS_ENV=production bundle exec rails db:migrate"

  success "Database migrations complete"

  # NEW: Seed Salt templates after migrations
  info "Refreshing Salt State templates..."
  sudo -u "$DEPLOY_USER" bash -c "export PATH=/home/${DEPLOY_USER}/.rbenv/shims:\$PATH && RAILS_ENV=production bundle exec rails db:seed:salt_templates" || warning "Salt template seeding had errors (check logs)"
  success "Salt templates refreshed"
}
```

## Salt Best Practices Context

Since user is learning Salt and wants to comply with best practices:

### Template Storage Philosophy

**Veracity's Approach (Database-First):**
- Templates stored in PostgreSQL `salt_states` table
- Deployed to filesystem only when needed
- Allows version control, validation, multi-tenancy

**Traditional Salt Approach:**
- Files directly in /srv/salt/ directory
- Edited with text editor
- Version control via git

**Why Veracity's Approach is Good:**
- UI-driven template management
- YAML validation before deployment
- Easy backup/restore with application
- Audit trail of changes
- Multi-user safe (no file conflicts)

### Key Salt Concepts

**Salt States (what templates are):**
- Declarative configuration files (YAML + Jinja2)
- Define desired server state (idempotent)
- Examples: install nginx, configure SSH, create users

**Salt Execution Modules (what Tasks use):**
- Ad-hoc commands executed immediately
- Not idempotent (run every time)
- Examples: pkg.upgrade, cmd.run, service.restart

**Salt Grains:**
- Server facts/metadata (OS, CPU, RAM)
- Read-only, collected automatically
- Used in templates for conditionals

**Salt Pillars:**
- Per-minion configuration and secrets
- Stored on Salt Master securely
- Used in templates for sensitive data
- Veracity uses for Proxmox API tokens (good practice)

### Current Templates Follow Best Practices

The seed file already implements Salt best practices:
- Idempotent operations using declarative syntax
- Jinja2 templating with pillar data for secrets
- Grain-based conditionals for OS-specific logic
- State dependencies with require/watch
- Proper file organization by category
