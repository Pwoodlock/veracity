# Tech-Spec: Salt Key Management UI Enhancements + Auto-Acceptance

**Created:** 2025-12-13
**Updated:** 2025-12-13
**Status:** ✅ Completed
**Complexity:** Medium-High (24 tasks completed)

## Overview

### Problem Statement

The current onboarding page has several limitations:
1. Only displays pending minion keys (no visibility into accepted/rejected/denied)
2. No convenient copy-to-clipboard for the Salt minion installation command
3. Cannot bulk-delete keys or manage accepted keys from the UI
4. No automated key acceptance for mass server deployments
5. Manual workflow doesn't scale when onboarding 20-30 servers simultaneously

### Solution

Implement comprehensive Salt key management with two major feature sets:

**Feature Set A: Enhanced Key Management UI**
1. Copy-to-clipboard button for minion installation command
2. Tabbed interface showing all key types (Pending, Accepted, Rejected, Denied)
3. Server association display for accepted keys (hostname, status)
4. Bulk delete functionality for all key types
5. Individual delete actions with admin permissions
6. Auto-refresh (30-second polling) with URL hash persistence

**Feature Set B: Automated Key Acceptance**
1. Toggle switch for bulk auto-acceptance mode
2. Fingerprint whitelist management
3. Background job polling (conditional - stops when disabled)
4. Gotify notifications for auto-accepted keys
5. Manual minion addition notifications
6. Comprehensive audit logging

### Scope (In/Out)

**In Scope:**
- ✅ Clipboard copy button with visual feedback
- ✅ Tabbed interface for all key types
- ✅ Server association display (hostname, status, last_seen)
- ✅ Bulk delete functionality with confirmation
- ✅ Individual delete actions for all key types
- ✅ Auto-refresh (30-second polling)
- ✅ URL hash persistence for tabs
- ✅ Auto-acceptance toggle on onboarding page
- ✅ Fingerprint whitelist CRUD interface
- ✅ Background job for auto-acceptance (conditional polling)
- ✅ Gotify notifications (auto-accept summary + manual minion addition)
- ✅ Notification type toggles (enable/disable each notification type)
- ✅ Audit logging for all key operations

**Out of Scope:**
- ❌ Real-time Salt event stream (use polling instead)
- ❌ Key re-acceptance workflow (delete and re-register)
- ❌ Advanced fingerprint patterns (regex) - use exact match whitelist
- ❌ Per-user notification preferences (admin-only for now)
- ❌ Key metadata (creation date, last used) - future enhancement

---

## Context for Development

### Codebase Patterns

**Frontend Architecture:**
- **DaisyUI 5 + Tailwind CSS** - Lo-Fi theme with utility-first styling
- **Stimulus 3.2** - JavaScript controllers for interactive elements
- **Turbo Streams** - Real-time UI updates without page reload
- **ViewComponents** - Reusable, testable UI components

**Backend Patterns:**
- **SaltService** - Centralized Salt API client (`app/services/salt_service.rb`)
- **SystemSetting** - Key-value config store with ENV precedence
- **Sidekiq Jobs** - Background processing with sidekiq-cron
- **GotifyNotificationService** - Notification delivery
- **NotificationHistory** - Notification tracking model

**Existing Patterns to Follow:**
- Notification toggles: See `SystemSetting` for Gotify settings
- Background jobs: See `TaskSchedulerJob` for cron-based polling
- Audit logging: Use Rails.logger with structured format

### Files to Reference

**Controllers:**
- `app/controllers/onboarding_controller.rb` - Key management actions
- `app/controllers/settings_controller.rb` - System settings management

**Views:**
- `app/views/onboarding/index.html.erb` - Main onboarding page
- `app/views/onboarding/_pending_keys.html.erb` - Pending keys partial
- `app/views/settings/edit_category.html.erb` - Settings form patterns

**Services:**
- `app/services/salt_service.rb` - Salt API integration (lines 416-505)
- `app/services/gotify_notification_service.rb` - Notification delivery

**Models:**
- `app/models/system_setting.rb` - Key-value configuration
- `app/models/notification_history.rb` - Notification tracking
- `app/models/server.rb` - Server model (for associations)

**Jobs:**
- `app/jobs/task_scheduler_job.rb` - Cron-based polling pattern
- `app/jobs/update_server_status_job.rb` - Server status updates

**JavaScript Controllers (to create):**
- `app/javascript/controllers/clipboard_controller.js` - Copy to clipboard
- `app/javascript/controllers/auto_refresh_controller.js` - Polling refresh

### Technical Decisions

**1. Tab Implementation**
- Use DaisyUI tabs component (semantic HTML + CSS)
- Client-side tab switching (no server round-trip)
- Preserve state with URL hash (`#pending`, `#accepted`, etc.)
- Auto-refresh updates data without losing tab state

**2. Clipboard Copy**
- Stimulus controller with Clipboard API
- Visual feedback: icon change (copy → checkmark for 2 seconds)
- Fallback for older browsers (textarea + execCommand)

**3. Key Type Organization**
```
Pending (minions_pre)       → Green badge, "Accept" + "Reject" actions
Accepted (minions)          → Blue badge, "Delete" (admin), show Server association
Rejected (minions_rejected) → Red badge, "Delete" action
Denied (minions_denied)     → Orange badge, "Delete" action
```

**4. Auto-Acceptance Architecture**

**SystemSettings:**
```ruby
auto_accept_keys_enabled: boolean (default: false)
auto_accept_fingerprint_whitelist: text (JSON array)
notify_on_auto_accept: boolean (default: true)
notify_on_manual_minion_add: boolean (default: false)
```

**Fingerprint Whitelist Format:**
```json
[
  "a1:b2:c3:d4:e5:f6:g7:h8:i9:j0",
  "f1:e2:d3:c4:b5:a6:97:88:79:60"
]
```

**Background Job Logic:**
```ruby
# AutoAcceptMinionKeysJob
# Runs every 30 seconds via sidekiq-cron
# ONLY runs if auto_accept_keys_enabled == true

def perform
  return unless SystemSetting.get('auto_accept_keys_enabled', false)

  pending_keys = SaltService.list_pending_keys
  whitelist = JSON.parse(SystemSetting.get('auto_accept_fingerprint_whitelist', '[]'))

  accepted_keys = []
  pending_keys.each do |key|
    if whitelist.include?(key[:fingerprint])
      result = SaltService.accept_key_with_verification(key[:minion_id], key[:fingerprint])
      accepted_keys << key[:minion_id] if result[:success]

      # Audit log
      Rails.logger.info "[AUTO-ACCEPT] Accepted key: #{key[:minion_id]} (fingerprint: #{key[:fingerprint]})"
    end
  end

  # Send Gotify notification if keys were accepted
  if accepted_keys.any? && SystemSetting.get('notify_on_auto_accept', true)
    send_auto_accept_notification(accepted_keys)
  end

  # Register servers (same as manual acceptance)
  register_accepted_minions(accepted_keys) if accepted_keys.any?
end
```

**5. Notification Types**

**New notification types to add to NotificationHistory:**
- `minion_auto_accepted` - Bulk notification for auto-accepted keys
- `minion_manual_added` - Notification when admin manually accepts a key

**Notification toggles (SystemSettings):**
- `notify_on_auto_accept` - Enable/disable auto-accept notifications
- `notify_on_manual_minion_add` - Enable/disable manual addition notifications

**6. Delete Confirmation**
- Pending keys: Standard confirmation
- Accepted keys: Enhanced warning (server will lose connection)
- Bulk delete: Count-based confirmation message

**7. Auto-Refresh Polling**
- Stimulus controller with `setInterval`
- Polls every 30 seconds when page is active
- Uses `visibilitychange` event to pause when tab hidden
- Updates only the key list containers (Turbo Frame)

**8. URL Hash Persistence**
```javascript
// On tab click
window.location.hash = tabName; // e.g., #accepted

// On page load
const hash = window.location.hash.slice(1);
if (hash) activateTab(hash);
```

---

## Implementation Plan

### Phase 1: Core UI Enhancements (Tasks 1-14)

#### **Task 1:** Create Stimulus clipboard controller
- Create `app/javascript/controllers/clipboard_controller.js`
- Implement copy-to-clipboard with Clipboard API
- Add visual feedback (icon swap: copy → checkmark for 2s)
- Add fallback for older browsers (textarea + execCommand)

#### **Task 2:** Add copy button to installation instructions
- Update `app/views/onboarding/index.html.erb`
- Add button with clipboard icon next to install command
- Wire up Stimulus controller: `data-controller="clipboard"`
- Style with DaisyUI (btn-sm, btn-ghost)

#### **Task 3:** Create `list_all_keys` method in SaltService
- Parse all key types from `key.list_all` response
- Return structured hash:
  ```ruby
  {
    pending: [{ minion_id:, fingerprint:, status: 'pending' }],
    accepted: [{ minion_id:, fingerprint:, status: 'accepted', server: Server }],
    rejected: [{ minion_id:, fingerprint:, status: 'rejected' }],
    denied: [{ minion_id:, fingerprint:, status: 'denied' }]
  }
  ```
- For accepted keys: Join with Server model on minion_id
- Extract fingerprints for all key types (reuse existing `get_key_fingerprint`)

#### **Task 4:** Update OnboardingController index action
- Call `SaltService.list_all_keys` instead of `list_pending_keys`
- Pass `@all_keys` to view
- Load auto-acceptance settings: `@auto_accept_enabled`, `@whitelist`

#### **Task 5:** Create tabbed interface in view
- Create new partial: `app/views/onboarding/_all_keys_tabs.html.erb`
- Implement DaisyUI tabs (4 tabs: Pending, Accepted, Rejected, Denied)
- Add badge with count for each tab (`<span class="badge">12</span>`)
- Add URL hash support for tab persistence
- Replace old `_pending_keys` partial in index.html.erb

#### **Task 6:** Create key list partial for each tab
- Create `app/views/onboarding/_key_list.html.erb`
- Accept params: `keys`, `key_type`, `current_user`
- Display: minion ID, fingerprint, badge (color-coded)
- **For accepted keys:** Show server association (hostname, status badge, last_seen)
- Conditional actions based on key type:
  - Pending: Accept + Reject buttons (existing)
  - Accepted: Delete button (admin only), show Server info
  - Rejected/Denied: Delete button

#### **Task 7:** Add bulk select/delete for all tabs
- Add "Select All" checkbox per tab
- Add "Delete Selected" button (disabled when none selected)
- Update JavaScript for bulk selection (per tab scope)
- Create bulk delete forms for each key type

#### **Task 8:** Implement delete for accepted keys
- Add `delete_accepted_key` action to OnboardingController
- Authorization: `require_admin!`
- Delete key via `SaltService.delete_key(minion_id)`
- Also delete associated `Server` record
- Enhanced confirmation: "This server is managed. Deleting will disconnect it."
- Audit log: `Rails.logger.warn "[ADMIN-DELETE] User #{current_user.email} deleted accepted key: #{minion_id}"`

#### **Task 9:** Implement bulk delete for all key types
- Add `bulk_delete_keys` action to OnboardingController
- Params: `key_type` (string), `minion_ids[]` (array)
- Loop and delete each key
- For accepted keys: also delete Server records
- Return success/failure counts
- Audit log each deletion

#### **Task 10:** Add visual indicators and styling
- Color-coded badges:
  - Pending: `badge-success` (green)
  - Accepted: `badge-info` (blue)
  - Rejected: `badge-error` (red)
  - Denied: `badge-warning` (orange)
- Confirmation dialogs with warnings
- Server status badges for accepted keys (online/offline)

#### **Task 11:** Create auto-refresh Stimulus controller
- Create `app/javascript/controllers/auto_refresh_controller.js`
- Poll every 30 seconds: fetch updated key lists
- Use Turbo Frame for partial updates
- Pause polling when tab hidden (`document.visibilityState`)
- Resume when tab visible

#### **Task 12:** Add Turbo Frame for auto-refresh
- Wrap key list containers in Turbo Frames
- Add refresh endpoint: `GET /onboarding/refresh_keys`
- Return only the key list partial (Turbo Frame response)
- Preserve tab state during refresh

#### **Task 13:** Update routes for Phase 1
```ruby
resource :onboarding, only: [:index] do
  post :accept_key
  post :reject_key
  post :bulk_accept_keys
  post :bulk_reject_keys
  post :refresh
  delete :delete_accepted_key        # NEW
  post :bulk_delete_keys             # NEW
  get :refresh_keys                  # NEW (auto-refresh)
end
```

#### **Task 14:** Add permission checks
- Admin-only: delete accepted keys
- Hide delete buttons for non-admins
- Server-side authorization in controller
- Return 403 Forbidden for unauthorized

---

### Phase 2: Auto-Acceptance Feature (Tasks 15-24)

#### **Task 15:** Create fingerprint whitelist model
- **Option A:** Use SystemSetting (simpler, JSON array)
- **Option B:** Create `FingerprintWhitelist` model (more structured)
- **Decision:** Use SystemSetting for MVP
- Add setting: `auto_accept_fingerprint_whitelist` (text, JSON array)

#### **Task 16:** Add auto-acceptance toggle to onboarding page
- Add toggle switch at top of page
- Label: "Auto-Accept Mode" with badge (ON/OFF)
- Warning banner when enabled: "⚠️ Auto-acceptance is ACTIVE. Pending keys matching whitelist will be accepted automatically."
- Wire up toggle to update SystemSetting via AJAX
- Show current whitelist count in toggle label

#### **Task 17:** Create fingerprint whitelist management UI
- Add modal on onboarding page: "Manage Whitelist"
- List current whitelisted fingerprints
- Add fingerprint: Input field + "Add" button
- Remove fingerprint: X button per entry
- Validate fingerprint format: `XX:XX:XX:...` (SHA256)
- Save to SystemSetting

#### **Task 18:** Create AutoAcceptMinionKeysJob
- Create `app/jobs/auto_accept_minion_keys_job.rb`
- Logic:
  1. Check if `auto_accept_keys_enabled` is true (return early if false)
  2. Fetch pending keys
  3. Load whitelist from SystemSetting
  4. Accept keys where fingerprint matches whitelist
  5. Audit log each acceptance
  6. Track accepted keys for notification
  7. Register servers (call `register_accepted_minions`)
- Add error handling (don't crash on Salt API errors)

#### **Task 19:** Configure sidekiq-cron for auto-accept job
- Add to `config/sidekiq.yml` or initializer:
  ```yaml
  :schedule:
    auto_accept_minion_keys:
      cron: '*/30 * * * * *'  # Every 30 seconds
      class: AutoAcceptMinionKeysJob
  ```
- Job checks enabled flag first, so safe to run continuously

#### **Task 20:** Add notification for auto-accepted keys
- Update `GotifyNotificationService`
- Add method: `send_auto_accept_notification(accepted_minion_ids)`
- Message: "🤖 Auto-accepted 12 minion key(s): server-1, server-2, ..."
- Priority: 5 (normal)
- Type: `minion_auto_accepted`
- Check toggle: `SystemSetting.get('notify_on_auto_accept', true)`

#### **Task 21:** Add notification for manual minion addition
- Update `OnboardingController#accept_key` action
- After successful acceptance, check toggle
- If `notify_on_manual_minion_add` is true, send notification
- Message: "✅ Minion manually accepted: #{minion_id}"
- Type: `minion_manual_added`

#### **Task 22:** Add notification type toggles to Settings
- Add to Settings page under "🔔 Gotify Notifications"
- Checkboxes:
  - ☐ Notify on auto-accepted minions
  - ☐ Notify on manually added minions
- Save to SystemSettings

#### **Task 23:** Add comprehensive audit logging
- Log format: `[AUTO-ACCEPT]`, `[MANUAL-ACCEPT]`, `[ADMIN-DELETE]`
- Include: timestamp, user email, minion_id, fingerprint, action
- Examples:
  ```
  [AUTO-ACCEPT] Accepted key: web-01 (fingerprint: a1:b2:c3:...)
  [MANUAL-ACCEPT] User admin@example.com accepted key: db-01
  [ADMIN-DELETE] User admin@example.com deleted accepted key: old-server
  ```
- Use `Rails.logger.info` for accepts, `Rails.logger.warn` for deletes

#### **Task 24:** Add audit log viewer (optional future)
- Placeholder: `/admin/audit_logs` route
- Filter by action type, date range
- Out of scope for MVP (just log to file for now)

---

### Acceptance Criteria

#### **AC 1:** Copy button functionality
- **Given** I am on the onboarding page
- **When** I click the copy button next to the install command
- **Then** the command is copied to my clipboard
- **And** the button icon changes to a checkmark for 2 seconds
- **And** I can paste the command successfully

#### **AC 2:** Tabbed key display with persistence
- **Given** I am on the onboarding page
- **When** the page loads
- **Then** I see 4 tabs: Pending, Accepted, Rejected, Denied
- **And** each tab shows a badge with the count of keys
- **When** I click the "Accepted" tab
- **Then** the URL updates to `#accepted`
- **When** I refresh the page
- **Then** I remain on the "Accepted" tab

#### **AC 3:** Accepted keys with server association
- **Given** I am viewing the "Accepted" tab
- **When** there are accepted minion keys
- **Then** I see for each key:
  - Minion ID
  - Fingerprint
  - Blue "Accepted" badge
  - **Server hostname** (if associated Server exists)
  - **Server status badge** (online/offline)
  - **Last seen timestamp**
  - Delete button (admin only)

#### **AC 4:** Auto-refresh functionality
- **Given** I am on the onboarding page
- **When** 30 seconds elapse
- **Then** the key lists auto-refresh
- **And** the current tab remains active
- **And** my scroll position is preserved
- **When** I switch to another browser tab
- **Then** auto-refresh pauses
- **When** I return to the onboarding tab
- **Then** auto-refresh resumes

#### **AC 5:** Bulk delete functionality
- **Given** I am viewing any tab with keys
- **When** I select multiple keys using checkboxes
- **Then** the "Delete Selected" button becomes enabled
- **When** I click "Delete Selected"
- **Then** I see a confirmation: "Delete 5 keys? This cannot be undone."
- **And** upon confirmation, all selected keys are deleted
- **And** associated Server records are deleted (for accepted keys)

#### **AC 6:** Auto-acceptance toggle
- **Given** I am an admin on the onboarding page
- **When** I enable the "Auto-Accept Mode" toggle
- **Then** auto-acceptance is activated
- **And** I see a warning banner: "⚠️ Auto-acceptance is ACTIVE"
- **And** the toggle shows "ON" badge
- **When** a new minion key arrives with whitelisted fingerprint
- **Then** it is automatically accepted within 30 seconds
- **When** I disable auto-acceptance
- **Then** the background job stops accepting keys

#### **AC 7:** Fingerprint whitelist management
- **Given** I am on the onboarding page
- **When** I click "Manage Whitelist"
- **Then** I see a modal with current whitelisted fingerprints
- **When** I add a fingerprint: `a1:b2:c3:d4:e5:f6:...`
- **Then** it is saved to the whitelist
- **When** I remove a fingerprint
- **Then** it is deleted from the whitelist
- **And** future keys with that fingerprint will NOT be auto-accepted

#### **AC 8:** Auto-acceptance notifications
- **Given** auto-acceptance is enabled
- **And** "Notify on auto-accepted minions" is enabled
- **When** 5 keys are auto-accepted in a 5-minute period
- **Then** I receive a Gotify notification: "🤖 Auto-accepted 5 minion key(s): ..."
- **When** I disable "Notify on auto-accepted minions"
- **Then** I do NOT receive auto-accept notifications

#### **AC 9:** Manual minion addition notifications
- **Given** "Notify on manually added minions" is enabled
- **When** I manually accept a minion key
- **Then** I receive a Gotify notification: "✅ Minion manually accepted: web-01"
- **When** I disable this notification type
- **Then** I do NOT receive manual addition notifications

#### **AC 10:** Audit logging
- **Given** any key operation occurs (accept, delete, auto-accept)
- **Then** it is logged with structured format
- **And** logs include: timestamp, user, action, minion_id, fingerprint
- **And** logs are written to Rails log file
- **And** I can grep logs for `[AUTO-ACCEPT]`, `[MANUAL-ACCEPT]`, `[ADMIN-DELETE]`

---

## Data Model Changes

### SystemSettings (Key-Value Store)

**New Settings:**
```ruby
auto_accept_keys_enabled: false              # Boolean (toggle)
auto_accept_fingerprint_whitelist: '[]'      # Text (JSON array)
notify_on_auto_accept: true                  # Boolean
notify_on_manual_minion_add: false           # Boolean
```

### NotificationHistory

**New notification_type values:**
- `minion_auto_accepted` - Bulk auto-accept notification
- `minion_manual_added` - Manual acceptance notification

No schema changes needed (notification_type is a string column).

---

## Additional Context

### Dependencies

**Existing:**
- SaltService (Salt API client)
- SystemSetting (config management)
- NotificationHistory + GotifyNotificationService
- Sidekiq + sidekiq-cron
- DaisyUI tabs, Stimulus

**New:**
- Clipboard API (browser native)
- Turbo Frames (already in Rails 7)
- `setInterval` for auto-refresh polling

### Security Considerations

**Auto-Acceptance Risks:**
- Only accept keys with whitelisted fingerprints (exact match)
- Admins must manually add fingerprints to whitelist
- Enhanced audit logging for all auto-accepted keys
- Toggle can be disabled immediately if compromised
- No regex/pattern matching to prevent bypass attacks

**Authorization:**
- Admin-only: delete accepted keys, manage whitelist, toggle auto-accept
- Operators: accept/reject pending keys (existing)
- Viewers: read-only access

**CSRF Protection:**
- All forms use Rails CSRF tokens (default)
- AJAX requests include `X-CSRF-Token` header

### Testing Strategy

**Manual Testing Checklist:**
1. ✅ Copy button (Chrome, Firefox, Safari)
2. ✅ Tab switching with URL hash
3. ✅ Auto-refresh (pause/resume on visibility change)
4. ✅ Bulk selection and delete (all tabs)
5. ✅ Server association display for accepted keys
6. ✅ Auto-acceptance toggle (enable/disable)
7. ✅ Whitelist CRUD operations
8. ✅ Background job acceptance (add 3 keys, wait 30s)
9. ✅ Notifications (auto-accept + manual add)
10. ✅ Notification toggles (enable/disable)
11. ✅ Audit logs (grep for each action type)
12. ✅ Permission checks (admin vs non-admin)

**Edge Cases:**
- Empty whitelist + auto-accept enabled (should not accept any keys)
- Malformed fingerprint in whitelist (validation)
- Salt API timeout during auto-accept (graceful handling)
- 50+ keys pending (performance test)
- Toggle auto-accept rapidly (race conditions)

### Performance Considerations

**Auto-Refresh Polling:**
- 30-second interval (configurable)
- Uses Turbo Frame (only updates affected DOM)
- Pauses when tab hidden (saves bandwidth)

**Background Job:**
- Runs every 30 seconds (lightweight)
- Early return if disabled (no overhead)
- Batch accepts keys (single register call)

**Fingerprint Fetching:**
- Already optimized in existing code
- Cached in SaltService if needed

### UX Considerations

**Auto-Accept Warning:**
- Prominent banner when enabled
- Color: `alert-warning` (orange/yellow)
- Position: Top of page, above tabs

**Whitelist UX:**
- Modal overlay for management
- Copy-paste friendly (monospace font)
- Visual feedback on add/remove
- Show count in toggle label

**Loading States:**
- Skeleton loaders for auto-refresh
- Disabled state for toggle during save
- Spinner for bulk operations

### Migration Plan

**No database migrations needed!**
- All new settings use SystemSetting (already exists)
- NotificationHistory supports new types (string column)
- Server association uses existing foreign key

**Deployment Steps:**
1. Deploy code
2. Seed default SystemSettings (via console or initializer)
3. Configure sidekiq-cron schedule
4. Restart Sidekiq workers
5. Test auto-acceptance in staging
6. Enable in production

---

## Notes for Implementation

**Icon Selection (Heroicons):**
- Copy: `document-duplicate`
- Checkmark: `check`
- Warning: `exclamation-triangle`
- Auto-accept: `bolt` or `sparkles`

**DaisyUI Components Used:**
- Tabs + tab-bordered
- Badge (success, info, error, warning)
- Toggle switch
- Modal
- Alert (warning banner)
- Checkbox

**JavaScript Patterns:**
- Stimulus targets for dynamic elements
- Event delegation for dynamically added rows
- LocalStorage for user preferences (future)

**Audit Log Rotation:**
- Use logrotate for Rails logs
- Compress old logs
- Keep 30 days (configurable)

---

## Success Metrics

**Efficiency Gains:**
- Manual acceptance time: 30s per key → 2s (copy button)
- Bulk onboarding: 20 keys × 30s = 10 minutes → Automated (0 manual time)

**User Satisfaction:**
- Visibility into all key types (not just pending)
- Server association reduces confusion
- Auto-accept eliminates repetitive work

**System Health:**
- Audit logs enable security reviews
- Notification toggles reduce noise
- Background job is lightweight (no performance impact)

---

*Tech-Spec created for intermediate user: Patrick*
*AI-optimized for Claude Code implementation*
*Estimated effort: 2-3 development sessions (6-9 hours)*
