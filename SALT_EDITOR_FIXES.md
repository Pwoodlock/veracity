# Salt Editor Fixes - Summary

## Issues Identified and Resolved

### 1. ✅ YAML Syntax Errors in Templates

**Problem**: Salt templates were showing YAML syntax errors because they contain Jinja2 templating syntax (`{% %}`, `{{ }}`), which is not valid YAML. Salt works by rendering Jinja2 templates first, then parsing the result as YAML.

**Solution**:
- **Updated `app/services/salt_editor_service.rb`**:
  - Added `contains_jinja2?()` method to detect Jinja2 syntax
  - Modified `validate_yaml()` to recognize Jinja2 templates as valid
  - Returns `{ valid: true, is_jinja2_template: true }` for Jinja2 content

- **Updated `app/models/salt_state.rb`**:
  - Added `contains_jinja2?()` method
  - Updated `valid_yaml?()` to return true for Jinja2 templates
  - Updated `yaml_error()` to return nil for Jinja2 templates
  - Added `jinja2_template?()` helper method

- **Updated `app/views/admin/salt_states/_form.html.erb`**:
  - Shows "Jinja2 Template" badge (blue) for templates with Jinja2 syntax
  - Shows "Valid YAML" badge (green) for pure YAML
  - Shows "Error" badge (red) only for actual YAML syntax errors

- **Updated `app/views/admin/salt_states/show.html.erb`**:
  - Displays appropriate status badge based on content type

**Result**: Templates with Jinja2 syntax (like `{% if grains['os'] == 'Ubuntu' %}`) are now correctly recognized as valid Salt states.

---

### 2. ✅ Duplicate Task Templates

**Problem**: Task templates (like `pkg.upgrade`, `pkg.list_upgrades`, `service.restart`) were being created multiple times from different sources:
- `db/seeds.rb`
- `db/migrate/20251110140100_create_new_task_system.rb`
- `db/migrate/20251111000001_fix_security_updates_template.rb`

**Duplicates Found**:
- `pkg.upgrade` - 3 instances
- `pkg.list_upgrades` - 2 instances
- `service.restart` - 2 instances

**Solution**:
- **Created `db/migrate/20251212000001_remove_duplicate_task_templates.rb`**:
  - Removes duplicate task templates (keeps only the first instance of each)
  - Adds unique constraint on `command_template` column to prevent future duplicates

- **Updated `db/seeds.rb`**:
  - Changed from `find_or_create_by!(name: ...)` to `find_or_create_by!(command_template: ...)`
  - Ensures templates are unique based on the actual Salt command, not just the name

**Result**: No more duplicate commands in the task templates list. Database will prevent future duplicates.

---

## Files Modified

### Backend
1. `app/services/salt_editor_service.rb` - Added Jinja2 detection and validation
2. `app/models/salt_state.rb` - Added Jinja2 template handling
3. `db/seeds.rb` - Updated to prevent duplicate task templates
4. `db/migrate/20251212000001_remove_duplicate_task_templates.rb` - NEW migration to clean up duplicates

### Frontend
1. `app/views/admin/salt_states/_form.html.erb` - Updated validation status display
2. `app/views/admin/salt_states/show.html.erb` - Updated status badge display

---

## How to Apply These Fixes

1. **Run the new migration** to remove duplicates:
   ```bash
   rails db:migrate
   ```

2. **Restart your Rails server** to load the updated code

3. **Test the fixes**:
   - Open Salt Editor → Templates
   - Click on any template with Jinja2 syntax (e.g., "base/init", "security/ssh")
   - You should now see "Jinja2 Template" badge instead of "YAML Error"
   - Check the Tasks section - duplicates should be removed

---

## UI Changes

### Before
- Templates with `{% %}` or `{{ }}` showed "YAML Error" (red badge)
- Task templates appeared multiple times in listings

### After
- Templates with Jinja2 syntax show "Jinja2 Template" (blue info badge)
- Pure YAML files show "Valid YAML" (green badge)
- Actual errors show "Error" (red badge)
- Each task template appears only once

---

## Technical Details

### Jinja2 Detection Pattern
The system now recognizes these patterns as Jinja2:
- `{% ... %}` - Statements (if, for, set, etc.)
- `{{ ... }}` - Expressions/variables
- `{# ... #}` - Comments

### Database Constraint
A unique index has been added to prevent duplicate task templates:
```sql
CREATE UNIQUE INDEX index_task_templates_on_command_template_unique
ON task_templates (command_template);
```

---

## Notes

- All Salt state templates in the seed file use Jinja2, which is **correct and expected**
- The validation now properly understands that Jinja2 is valid for Salt (it gets rendered before YAML parsing)
- Future task template additions will automatically prevent duplicates via database constraint
- No functionality was removed - this is purely a fix for false error messages and duplicate data

---

## Testing Checklist

- [ ] Open Salt Editor and view templates
- [ ] Check that Jinja2 templates show "Jinja2 Template" badge
- [ ] Create a new Salt state with Jinja2 syntax - should validate correctly
- [ ] Check Tasks section for no duplicates
- [ ] Try creating a duplicate task template - should be prevented by database constraint
