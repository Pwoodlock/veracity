# Bulk Accept Minions - Task Handoff

## Problem Summary
The bulk accept/reject minion keys feature on the onboarding page is not working correctly. Multiple attempts have been made to fix it but issues persist.

## Current Status
- **Still broken** - needs further debugging

## What Was Implemented

### Controller Changes (`app/controllers/onboarding_controller.rb`)
1. Added `bulk_accept_keys` action to accept multiple minion keys at once
2. Added `bulk_reject_keys` action to reject multiple minion keys at once
3. Added `register_accepted_minions` private method to register minions after bulk accept
4. Updated `before_action :require_operator!` to include the new actions

### Routes Added (`config/routes.rb`)
```ruby
post "onboarding/bulk_accept_keys" => "onboarding#bulk_accept_keys", as: :bulk_accept_keys_onboarding
post "onboarding/bulk_reject_keys" => "onboarding#bulk_reject_keys", as: :bulk_reject_keys_onboarding
```

### View Changes (`app/views/onboarding/_pending_keys.html.erb`)
- Added checkboxes next to each pending minion key
- Added "Select All" checkbox with badge showing count
- Added "Accept Selected" and "Reject Selected" buttons
- JavaScript to handle checkbox selection and form submission
- Hidden forms for bulk accept/reject that get populated by JavaScript

## Issues Encountered

### Issue 1: CSRF Token Error (422 Unprocessable Entity)
- **Error**: "Can't verify CSRF token authenticity"
- **Cause**: Originally had nested forms (individual accept/reject forms inside the bulk form wrapper)
- **Attempted Fix**: Moved bulk forms outside, used hidden forms populated by JavaScript
- **Status**: May still be occurring

### Issue 2: 500 Internal Server Error
- **Error**: `NoMethodError (undefined method 'size' for an instance of ActionController::Parameters)`
- **Cause**: Rails parses `minion_keys[0][minion_id]` as a hash with string keys ("0", "1"), not an array
- **Fix Applied**:
```ruby
minion_keys = if minion_keys_param.is_a?(ActionController::Parameters)
                minion_keys_param.values.map(&:to_h)
              elsif minion_keys_param.is_a?(Array)
                minion_keys_param
              else
                []
              end
```
- **Status**: Fix was deployed but user reports still not working

## Files Modified
1. `app/controllers/onboarding_controller.rb` - Added bulk actions
2. `app/views/onboarding/_pending_keys.html.erb` - Added checkboxes and JS
3. `config/routes.rb` - Added bulk routes

## Debugging Steps to Try

### 1. Check Server Logs
```bash
sshpass -p '190481**//**' ssh root@46.224.101.253 "tail -100 /opt/veracity/app/log/puma.log"
```

### 2. Check What Error is Actually Occurring
Look for the specific error message after attempting bulk accept.

### 3. Test the Form Submission Manually
Use browser dev tools (Network tab) to see:
- What parameters are being sent
- What response is received
- Is the CSRF token present in the request

### 4. Verify Code on Server Matches Local
```bash
sshpass -p '190481**//**' ssh root@46.224.101.253 "cat /opt/veracity/app/app/controllers/onboarding_controller.rb | head -150"
```

## Server Details
- **IP**: 46.224.101.253
- **SSH User**: root
- **SSH Password**: 190481**//**
- **App Path**: /opt/veracity/app
- **Service**: server-manager.service

## Deploy Commands
```bash
# Pull latest and restart
sshpass -p '190481**//**' ssh root@46.224.101.253 "cd /opt/veracity/app && git pull origin main && systemctl restart server-manager.service && sleep 3 && curl -sS http://127.0.0.1:3000/up"

# With asset recompile
sshpass -p '190481**//**' ssh root@46.224.101.253 "cd /opt/veracity/app && git pull origin main && su - deploy -c 'cd /opt/veracity/app && source ~/.bashrc && RAILS_ENV=production /home/deploy/.local/share/mise/shims/bundle exec rails assets:precompile' && systemctl restart server-manager.service && sleep 3 && curl -sS http://127.0.0.1:3000/up"
```

## Related Optimization Done
- Single `accept_key` action was optimized to use background thread for minion registration (faster response)
- Sleep reduced from 2s to 1.5s

## Original User Request
User wanted:
1. Ability to select multiple pending minion keys with checkboxes
2. "Select All" functionality
3. Bulk accept/reject selected keys
4. Faster response when accepting keys (was slow due to `sleep 2` and discovering all minions)
