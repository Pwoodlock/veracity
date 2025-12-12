# Hetzner Cloud Integration - UI Enhancement

## Feature: Visual API Key Selection for Cloud Profiles

### Problem Solved
Previously, when creating Hetzner cloud profiles or providers in the Salt Editor, users had to:
- Manually remember/look up the provider name
- Manually type `provider: hetzner-cloud` into the YAML
- No way to see which API keys were available
- Risk of typos and errors

### Solution
Added a **Cloud Provider panel** that appears automatically when creating cloud profiles/providers with:
- ✅ Dropdown selector showing all available Hetzner API keys
- ✅ Live preview of the provider name
- ✅ One-click insertion of properly formatted configuration
- ✅ Links to manage API keys if none exist
- ✅ Visual indication of which API key you're using

---

## How It Works

### 1. Creating a Cloud Profile

**Step 1:** Navigate to **Salt Editor** → **New State**

**Step 2:** Select **Type: Cloud Profile**

**Step 3:** A new "Cloud Provider" panel appears in the sidebar showing:
- Dropdown of all enabled Hetzner API keys
- Each entry shows: `API Key Name (abc...xyz)` with masked token
- Provider name preview below the dropdown
- "Insert Provider Reference" button

**Step 4:** Select your desired API key from the dropdown

**Step 5:** Click "Insert Provider Reference" button

**Step 6:** The editor automatically inserts:
```yaml
# Hetzner Cloud Profile (using API key: Production)
my-server-profile:
  provider: production_hetzner  # Auto-generated from API key name
  size: cx21          # cx11, cx21, cx31, cx41, etc.
  image: ubuntu-22.04
  location: fsn1      # fsn1 (Falkenstein), nbg1 (Nuremberg), hel1 (Helsinki)
  ssh_username: root
  minion:
    master: {{ pillar.get('salt:master_ip', 'salt.example.com') }}
```

**Step 7:** Customize the profile name, size, location, etc.

**Step 8:** Save and deploy!

---

## API Key to Provider Name Mapping

The system automatically converts API key names to valid provider names:

| API Key Name | Provider Name |
|--------------|---------------|
| Production | `production` |
| Staging Environment | `staging_environment` |
| Dev-01 | `dev_01` |
| My-API-Key | `my_api_key` |

**Conversion Rules:**
- Lowercase all characters
- Replace spaces and special chars with underscores
- Remove invalid characters
- Result is safe for YAML

---

## UI Components

### Cloud Provider Panel
**Appears when:** State Type is "Cloud Profile" or "Cloud Provider"

**Contains:**
- **Hetzner API Key dropdown**
  - Shows all enabled API keys
  - Displays: `Name (token preview)`
  - Example: `Production (abc12345...xyz9)`

- **Provider name display**
  - Shows: `Provider name: production`
  - Updates live as you select different keys

- **Insert button**
  - Inserts pre-formatted template
  - Includes helpful comments
  - Adapts based on state type (profile vs provider)

- **Manage link**
  - Opens Settings → Hetzner API Keys in new tab
  - Quick access to add/edit keys

**Empty State:**
If no API keys exist, shows:
```
⚠️ No Hetzner API Keys
Add a Hetzner API key to use cloud profiles.
[Link to Settings]
```

---

## Code Changes

### Backend

**File:** `app/controllers/admin/salt_states_controller.rb`

```ruby
# Added to new and edit actions
def new
  @salt_state = SaltState.new(...)
  load_api_keys  # NEW
end

def edit
  @yaml_error = @salt_state.yaml_error
  load_api_keys  # NEW
end

# New private method
def load_api_keys
  @hetzner_api_keys = HetznerApiKey.enabled.order(:name)
  @proxmox_api_keys = ProxmoxApiKey.order(:name) rescue []
end
```

### Frontend

**File:** `app/views/admin/salt_states/_form.html.erb`

**Added:**
1. Cloud Provider panel (lines 130-185)
2. JavaScript to show/hide panel based on state type
3. JavaScript to update provider name display
4. `insertHetznerProvider()` function to insert templates

---

## Usage Examples

### Example 1: Production Web Server

**Scenario:** Create a cloud profile for production web servers

```yaml
# Name: web-server-prod
# Type: Cloud Profile

# Hetzner Cloud Profile (using API key: Production Hetzner)
web-server-prod:
  provider: production_hetzner
  size: cx31          # 2 vCPU, 8GB RAM
  image: ubuntu-22.04
  location: fsn1
  ssh_username: root
  minion:
    master: {{ pillar.get('salt:master_ip') }}
```

### Example 2: Staging Environment

**Scenario:** Create a smaller profile for staging

```yaml
# Name: staging-server
# Type: Cloud Profile

# Hetzner Cloud Profile (using API key: Staging)
staging-server:
  provider: staging
  size: cx11          # 1 vCPU, 2GB RAM
  image: ubuntu-22.04
  location: nbg1      # Different datacenter
  ssh_username: root
  minion:
    master: {{ pillar.get('salt:master_ip') }}
```

### Example 3: Cloud Provider Configuration

**Scenario:** Explicitly define a provider (usually auto-configured)

```yaml
# Name: my-hetzner-provider
# Type: Cloud Provider

# Hetzner Cloud Provider Configuration
# API key: Production Hetzner
production_hetzner:
  driver: hetzner
  # API key is automatically configured from Settings → Hetzner API Keys
```

---

## Integration with Existing System

### How It Connects

1. **API Keys** are stored in the database (encrypted)
   - Model: `HetznerApiKey`
   - Location: Settings → Hetzner API Keys

2. **Provider Config** is auto-generated on disk
   - File: `/etc/salt/cloud.providers.d/hetzner.conf`
   - Generated by: `HetznerApiKey.update_salt_pillar` callback
   - Contains all enabled API keys

3. **Cloud Profiles** reference providers
   - File: `/etc/salt/cloud.profiles.d/*.conf`
   - Created via: Salt Editor
   - Uses `provider: <name>` to link to API key

4. **Salt Cloud** uses both to provision VMs
   - Command: `salt-cloud -p web-server-prod my-new-vm`
   - Reads profile → Gets provider → Uses API key → Creates VM

### Auto-Configuration

The system automatically:
- ✅ Generates provider config when you add/edit/remove API keys
- ✅ Converts API key names to valid provider identifiers
- ✅ Updates config file at `/etc/salt/cloud.providers.d/hetzner.conf`
- ✅ Maintains proper file permissions

**You only need to:**
1. Add API key via Settings
2. Create cloud profile via Salt Editor (with new UI)
3. Use the profile to provision VMs

---

## Benefits

### Before (Manual)
```yaml
# User has to remember/type everything manually
my-profile:
  provider: hetzner-cloud  # Which API key is this? 🤔
  size: cx21
  # ... rest of config
```

### After (Visual UI)
1. Select API key from dropdown: `Production (abc...xyz)` ✅
2. Click "Insert Provider Reference" ✅
3. Get pre-filled template with correct provider name ✅
4. See which API key you're using in comments ✅

### Improvements
- 🎯 **No more guessing** - See all available API keys
- 🎯 **No typos** - Auto-generated provider names
- 🎯 **Faster** - One click vs manual typing
- 🎯 **Self-documenting** - Comments show which API key is used
- 🎯 **Discoverable** - New users can explore available keys
- 🎯 **Linked** - Direct access to API key management

---

## Future Enhancements

Potential improvements for later:
- [ ] Support for Proxmox API keys in same panel
- [ ] Preview of available VM sizes per API key
- [ ] One-click clone from template profiles
- [ ] Validation of provider name before save
- [ ] Show API key usage stats (how many profiles use each key)
- [ ] Auto-suggest profile names based on size/location

---

## Testing Checklist

- [ ] Navigate to Salt Editor → New State
- [ ] Select Type: Cloud Profile → Cloud panel appears
- [ ] Select Type: State → Cloud panel disappears
- [ ] Select Hetzner API key from dropdown
- [ ] Verify provider name updates below dropdown
- [ ] Click "Insert Provider Reference"
- [ ] Verify correct template is inserted with proper provider name
- [ ] Save the state and verify it deploys correctly
- [ ] Try with no API keys → Should show warning message
- [ ] Click "Manage API Keys" link → Opens settings in new tab

---

## Technical Details

### Provider Name Sanitization

```ruby
# In HetznerApiKey model
provider_name = key.name.downcase.gsub(/[^a-z0-9_-]/, '_')
```

**Examples:**
- `"Production"` → `"production"`
- `"My API Key"` → `"my_api_key"`
- `"Staging-01"` → `"staging_01"`
- `"Dev@2024"` → `"dev_2024"`

### Template Insertion

Uses Monaco Editor API to insert at cursor position:
```javascript
editor.executeEdits('', [{
  range: new monaco.Range(lineNumber, 1, lineNumber, 1),
  text: snippet + '\n\n'
}]);
```

### State Type Detection

Panel visibility controlled by:
```javascript
if (type === 'cloud_profile' || type === 'cloud_provider') {
  cloudPanel.style.display = 'block';
}
```

---

## Troubleshooting

### Panel doesn't appear
- Check that State Type is set to "Cloud Profile" or "Cloud Provider"
- Refresh the page
- Check browser console for JavaScript errors

### No API keys in dropdown
- Go to Settings → Hetzner API Keys
- Add at least one API key
- Make sure it's enabled (toggle switch)
- Return to Salt Editor

### Provider name doesn't update
- Make sure an API key is selected (not blank option)
- Check browser console for errors
- Try refreshing the page

### Insert button doesn't work
- Make sure an API key is selected first
- Check that Monaco editor is loaded (code editor visible)
- Check browser console for errors

---

## Summary

This enhancement transforms the Hetzner cloud integration from a manual, error-prone process into a visual, guided experience. Users can now:
- **See** all available API keys
- **Select** the one they want
- **Insert** properly formatted configuration with one click
- **Avoid** typos and configuration errors
- **Understand** which API key each profile uses

The UI automatically handles provider name generation and keeps everything in sync with the underlying API key management system.
