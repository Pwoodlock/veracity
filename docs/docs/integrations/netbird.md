---
sidebar_position: 1
---

# NetBird Integration

Veracity integrates with [NetBird](https://netbird.io) to deploy zero-trust network agents across your infrastructure. This allows you to create secure, peer-to-peer connections between your servers without complex VPN configurations.

## Overview

The NetBird integration allows you to:

- **Store Setup Keys** - Securely store NetBird setup keys with encryption
- **Deploy Agents** - Push NetBird agent installation to servers via Salt
- **Target Selection** - Deploy to individual servers, groups, or all online servers
- **Track Usage** - Monitor which keys have been used and how many times

## What is NetBird?

NetBird is an open-source zero-trust network solution that creates secure WireGuard-based connections between your devices. Key features include:

- **Zero Configuration** - No manual IP management or firewall rules
- **Peer-to-Peer** - Direct connections between devices when possible
- **NAT Traversal** - Works behind firewalls and NAT without port forwarding
- **Identity-Based** - Access based on device identity, not network location

## Prerequisites

Before using the NetBird integration:

1. **NetBird Account** - Self-hosted or [NetBird Cloud](https://app.netbird.io) account
2. **Setup Key** - Generated from your NetBird management console
3. **Salt Connectivity** - Target servers must be online Salt minions

## Configuration

Access NetBird settings at **Administration → Integrations → NetBird**.

### Adding a Setup Key

1. Navigate to **Administration → Integrations → NetBird**
2. Fill in the setup key form:

| Field | Description | Required |
|-------|-------------|----------|
| **Name** | Descriptive name for this key | Yes |
| **Management URL** | Your NetBird management server URL | Yes |
| **Port** | Management server port (default: 443) | No |
| **Setup Key** | UUID setup key from NetBird console | Yes |
| **NetBird Group** | Group to assign connected devices | No |
| **Notes** | Additional notes or documentation | No |

3. Click **Add Setup Key**

### Setup Key Format

Setup keys must be valid UUIDs in the format:

```
XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

Example: `4F0F9A28-C7F6-4E87-B855-015FC929FC63`

:::tip Generating Setup Keys
In your NetBird management console, go to **Setup Keys** and create a new key. Choose between:
- **One-off** - Single use, expires after first connection
- **Reusable** - Can be used multiple times
:::

### Security

Veracity uses multiple layers of security for NetBird setup keys:

#### At Rest (Database)
Setup keys are encrypted using AES-256 via the `attr_encrypted` gem. The encryption key is derived from your Rails application's `SECRET_KEY_BASE`.

#### In Transit (Salt Pillar)
When deploying to minions, Veracity uses **Salt Pillar** to pass the setup key securely:

```
┌─────────────────┐     AES Encrypted      ┌─────────────────┐
│   Salt Master   │ ─────────────────────► │   Salt Minion   │
│                 │                        │                 │
│  Pillar Data:   │   Only THIS minion     │  Receives:      │
│  - setup_key    │   can decrypt          │  - setup_key    │
│  - mgmt_url     │                        │  - mgmt_url     │
└─────────────────┘                        └─────────────────┘
```

**Why Pillar instead of command-line arguments?**

| Method | `ps aux` | Shell History | Salt Job Cache | Security |
|--------|----------|---------------|----------------|----------|
| Command-line args | Visible | Logged | Stored | **Insecure** |
| Salt Pillar | Hidden | Not logged | Not stored | **Secure** |

The setup key **never appears** in:
- Process listings (`ps aux`)
- Shell history files
- Salt's job cache on the master
- Log files

#### Temporary File Handling
On the minion, the key is:
1. Written to a temporary file (`/tmp/.netbird_setup_key`) with mode `0600`
2. Read by the NetBird connection command
3. **Immediately deleted** after use

#### Automatic Cleanup
Pillar data is deleted from the Salt master immediately after deployment completes (success or failure).

## Deploying Agents

### Target Selection

When deploying NetBird agents, you can target:

| Target Type | Description |
|-------------|-------------|
| **All Servers** | Deploy to all online Salt minions |
| **By Group** | Deploy to servers in selected groups |
| **Individual** | Deploy to specific servers |

### Deployment Process

1. Navigate to **Administration → Integrations → NetBird**
2. Find the setup key you want to use
3. Click the **Deploy** button (rocket icon)
4. Select your deployment targets:
   - Choose target type (All, Group, or Individual)
   - Select specific groups or servers if applicable
5. Click **Deploy NetBird**
6. Monitor the deployment progress

### What Happens During Deployment

When you deploy, Veracity performs these steps securely:

```
1. Write Pillar    2. Refresh Pillar    3. Apply State    4. Cleanup
   ┌─────────┐        ┌─────────┐        ┌─────────┐       ┌─────────┐
   │ Master  │───────►│ Minion  │───────►│ Install │──────►│ Delete  │
   │ writes  │        │ fetches │        │ NetBird │       │ pillar  │
   │ secret  │        │ secret  │        │         │       │ file    │
   └─────────┘        └─────────┘        └─────────┘       └─────────┘
```

**Step 1: Write Pillar Data**
Veracity creates a per-minion pillar file containing the encrypted setup key:
```yaml
# /srv/pillar/minions/<minion_id>/netbird.sls
netbird:
  management_url: https://your-server:443
  setup_key: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

**Step 2: Refresh Pillar**
The minion fetches its updated pillar data from the master (encrypted in transit).

**Step 3: Apply NetBird State**
The Salt state installs NetBird and connects using the pillar data:
```yaml
# The setup key is read from pillar, not command line
netbird_connect:
  cmd.run:
    - name: |
        SETUP_KEY=$(cat /tmp/.netbird_setup_key)
        netbird up --management-url {{ pillar['netbird']['management_url'] }} --setup-key "$SETUP_KEY"
```

**Step 4: Cleanup**
Both the temporary key file and pillar data are deleted immediately.

The deployment uses a **5-minute timeout** to accommodate:
- Package download from NetBird repositories
- Installation of WireGuard kernel module
- Initial connection setup

### Deployment Results

After deployment, you'll see results for each server:

| Status | Meaning |
|--------|---------|
| **Success** | NetBird installed and connected |
| **Error** | Installation failed (check error message) |
| **Timeout** | Command exceeded 5-minute timeout |

## Managing Setup Keys

### Enable/Disable Keys

Toggle keys on/off without deleting them:
- Click the **toggle icon** on any key
- Disabled keys cannot be used for deployment

### Usage Tracking

Each key displays:
- **Last Used** - When the key was last used for deployment
- **Usage Count** - Total number of deployment operations

### Deleting Keys

1. Click the **trash icon** on the key
2. Confirm deletion

:::warning
Deleting a setup key from Veracity does **not** disconnect servers already using it. To fully remove NetBird from a server, run:
```bash
netbird down
apt remove netbird  # or yum remove netbird
```
:::

## Troubleshooting

### Deployment Times Out

**Symptom:** Deployment fails with timeout error

**Solutions:**
1. Check server has internet access to `pkgs.netbird.io`
2. Verify Salt minion is online and responding
3. Check server has sufficient disk space
4. Review Salt logs on the target server:
   ```bash
   tail -f /var/log/salt/minion
   ```

### Connection Refused

**Symptom:** "Connection refused" error during deployment

**Solutions:**
1. Verify management URL is correct and accessible
2. Check firewall allows outbound connections on port 443 (or custom port)
3. Test connectivity from the server:
   ```bash
   curl -sS https://your-netbird-server/api/status
   ```

### Invalid Setup Key

**Symptom:** "Invalid setup key" or authentication errors

**Solutions:**
1. Verify setup key is in correct UUID format
2. Check key hasn't expired in NetBird console
3. Verify key hasn't reached usage limit (for limited-use keys)
4. Generate a new setup key if needed

### NetBird Not Starting

**Symptom:** Installation succeeds but NetBird doesn't connect

**Solutions:**
1. Check NetBird service status:
   ```bash
   systemctl status netbird
   ```
2. View NetBird logs:
   ```bash
   journalctl -u netbird -f
   ```
3. Manually test connection:
   ```bash
   netbird status
   netbird up --management-url https://your-server --setup-key YOUR-KEY
   ```

### WireGuard Module Missing

**Symptom:** "WireGuard kernel module not found" error

**Solutions:**
1. Install WireGuard module:
   ```bash
   # Ubuntu/Debian
   apt update && apt install wireguard-tools

   # RHEL/CentOS
   yum install epel-release
   yum install wireguard-tools
   ```
2. Load the module:
   ```bash
   modprobe wireguard
   ```

## Best Practices

### Setup Key Management

- **Use descriptive names** - Include purpose, environment, or team
- **Rotate keys regularly** - Create new keys and deprecate old ones
- **Use groups** - Assign NetBird groups for access control
- **Document usage** - Use the notes field to track key purpose

### Deployment Strategy

- **Test first** - Deploy to a single server before mass rollout
- **Group by environment** - Separate dev, staging, production keys
- **Monitor results** - Review deployment results for errors

### Security Considerations

- **Limit key scope** - Use setup keys with appropriate group assignments
- **Set expiration** - Configure key expiration in NetBird console
- **Audit usage** - Review usage counts for unexpected activity
- **Remove unused keys** - Delete keys that are no longer needed

## API Reference

### Salt Command

The deployment executes this Salt command on target minions:

```python
salt 'minion_id' cmd.run 'curl -fsSL https://pkgs.netbird.io/install.sh | sh && netbird up --management-url URL --setup-key KEY' timeout=300
```

### Model Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `name` | String | Unique identifier for the key |
| `management_url` | String | NetBird management server URL |
| `port` | Integer | Server port (default: 443) |
| `setup_key` | String (encrypted) | NetBird setup key UUID |
| `netbird_group` | String | NetBird group assignment |
| `enabled` | Boolean | Whether key is active |
| `notes` | Text | Additional documentation |
| `last_used_at` | DateTime | Last deployment timestamp |
| `usage_count` | Integer | Total deployments |

## Understanding Salt Pillar

Salt has two main data systems for managing minions:

| System | Purpose | Storage | Security |
|--------|---------|---------|----------|
| **Grains** | Data *about* minions (OS, CPU, RAM) | On minion | Visible to all |
| **Pillar** | Data *for* minions (secrets, configs) | On master | Encrypted per-minion |

### Why Pillar for Secrets?

Pillar is designed specifically for sensitive data:

1. **Encrypted Transit** - Data is AES-encrypted between master and minion
2. **Per-Minion Isolation** - Each minion only receives its own pillar data
3. **No Command-Line Exposure** - Secrets never appear in `ps aux` or logs
4. **No Job Cache** - Unlike `cmd.run` args, pillar data isn't cached

### Pillar File Structure

```
/srv/pillar/
├── top.sls              # Maps pillar files to minions
├── common.sls           # Shared (non-secret) data
└── minions/
    ├── web-server-1/
    │   └── netbird.sls  # Secrets for web-server-1
    └── db-server-1/
        └── netbird.sls  # Secrets for db-server-1
```

### How Veracity Uses Pillar

1. **Temporary Creation** - Pillar file created just before deployment
2. **Minion Refresh** - `saltutil.refresh_pillar` pushes data to minion
3. **State Execution** - State reads secrets from `pillar['key']`
4. **Immediate Deletion** - Pillar file removed after deployment

This ensures secrets exist on disk for the minimum time necessary.

### Learn More About Salt

- [Salt Pillar Documentation](https://docs.saltproject.io/en/latest/topics/pillar/)
- [Salt States Tutorial](https://docs.saltproject.io/en/latest/topics/tutorials/starting_states.html)
- [Salt Security Best Practices](https://docs.saltproject.io/en/latest/topics/hardening.html)

## Related Resources

- [NetBird Documentation](https://docs.netbird.io)
- [NetBird GitHub](https://github.com/netbirdio/netbird)
- [WireGuard Documentation](https://www.wireguard.com)
