# Specification: Auto-Seed Salt State Templates

## Goal
Automatically populate Salt State templates from the existing seed file during both fresh installations and system upgrades, eliminating manual seeding steps and ensuring templates are always available out-of-the-box.

## User Stories
- As a system administrator, I want Salt templates to be automatically available after installation so that I can immediately start using the Salt Editor without running manual commands
- As a developer, I want templates to be automatically refreshed during upgrades so that users always have the latest template versions without manual intervention

## Specific Requirements

**Auto-seed during fresh installation**
- Add require statement to `/mnt/d/Projects/veracity/db/seeds.rb` after line 215 (after TaskTemplate seeding)
- Load salt_templates.rb using `require Rails.root.join('db', 'seeds', 'salt_templates.rb')`
- Installer script at `/mnt/d/Projects/veracity/scripts/install/app-setup.sh` line 353 already calls `rails db:seed` (no changes needed)
- All 15 templates must be seeded into PostgreSQL `salt_states` table with `is_template: true`
- Follow same output pattern as TaskTemplate seeding with count summary

**Auto-update during system upgrades**
- Add new function `seed_salt_templates()` to `/mnt/d/Projects/veracity/scripts/update.sh` after line 191 (after run_migrations function)
- Function executes as deploy user with proper rbenv PATH: `sudo -u "$DEPLOY_USER" bash -c "export PATH=/home/${DEPLOY_USER}/.rbenv/shims:\$PATH && RAILS_ENV=production bundle exec rails db:seed:salt_templates"`
- Use `|| warning` pattern to continue update process even if seeding encounters non-critical errors
- Call `seed_salt_templates` in main() function after `run_migrations` (after line 280)
- Display info/success messages using existing script functions for consistency

**Idempotent seeding behavior**
- Existing `seed_template` helper in `/mnt/d/Projects/veracity/db/seeds/salt_templates.rb` uses `find_or_initialize_by(name:, state_type:)` for idempotency
- Running seed multiple times must not create duplicate templates
- Existing templates are updated with latest content from seed file
- User-created states (is_template: false) are never affected by seeding process

**Error handling and resilience**
- Continue processing all 15 templates even if individual template fails validation or save
- Log each template status: "✓ state_type: name" for success, "✗ state_type: name - error" for failures
- Display summary at end showing success/failure counts
- Non-critical template failures must not block installation or upgrade process
- Only database connection failures or critical system errors should stop the process

**Remove empty state UI message**
- Remove lines 86-99 from `/mnt/d/Projects/veracity/app/views/admin/salt_states/templates.html.erb` (empty state block)
- Templates will always be present after installation, making empty state unnecessary
- Users who manually delete all templates can re-run `rails db:seed:salt_templates` to restore

**Logging and output**
- Add "Seeding Salt State Templates..." message before require statement in db/seeds.rb
- Use existing Salt rake task output format with checkmarks and error symbols
- Update script should display "Refreshing Salt State templates..." before seeding
- Display final count: "Created X salt state templates" or similar summary message

## Visual Design

No visual assets provided - this is primarily a backend automation feature with minimal UI impact (removal of empty state message).

## Existing Code to Leverage

**TaskTemplate seeding pattern (db/seeds.rb lines 35-215)**
- Uses `find_or_create_by!` with idempotent logic for seeding default data
- Displays count summary: "Created #{TaskTemplate.count} task templates"
- Follow similar structure for Salt templates: add require statement and puts message
- Already proven to work reliably during installation process

**Salt template seed file (db/seeds/salt_templates.rb)**
- Complete implementation exists with 15 templates across 8 categories (base, security, web, database, docker, monitoring, cloud, orchestration)
- Helper method `seed_template(attrs)` handles find_or_initialize_by logic with error handling
- Uses SaltState model with proper validations and `is_template: true` flag
- Outputs status for each template with checkmark/error symbols
- Can be required directly via Rails.root.join pattern

**Existing Salt rake task (lib/tasks/salt.rake lines 4-7)**
- Task `salt:seed_templates` already defined and requires the seed file
- Used for manual template refresh by administrators
- Will be called by update.sh script during upgrades
- Follows consistent output formatting with other Salt rake tasks

**Update script migration pattern (scripts/update.sh lines 185-192)**
- Function `run_migrations()` shows pattern for running Rails commands during updates
- Uses sudo with deploy user and rbenv PATH export for proper environment
- Displays info/success messages using script helper functions
- Follow same pattern for seed_salt_templates function

**SaltState model scopes and validations (app/models/salt_state.rb)**
- Scope `SaltState.templates` filters templates (is_template: true)
- Validations ensure name format, uniqueness on name+state_type, and category inclusion
- Find_or_initialize_by on name+state_type prevents duplicates across multiple seeding runs
- Categories array defines valid categories: base, security, web, database, docker, monitoring, cloud, orchestration, other

## Out of Scope
- Toast notification improvements for seeding success/failure (separate UI improvement spec)
- Pillar architecture changes or robustness improvements (current implementation works fine)
- Kamal deployment integration (not being used - project uses custom update.sh)
- Changes to template content in db/seeds/salt_templates.rb (templates are already complete)
- UI for managing templates from web interface (already exists in templates controller/views)
- Filesystem deployment of templates to /srv/salt/ (separate deployment concern handled by SaltService)
- Template versioning or rollback capability (future enhancement)
- Selective template seeding by category (all templates should be seeded)
- Dashboard widget showing template count/status (UI enhancement for future)
- Manual re-seeding trigger from web interface (rake task available for CLI use)
