---
sidebar_position: 2
---

# Proxmox Integration

Veracity integrates with [Proxmox VE](https://www.proxmox.com/en/proxmox-ve) to manage virtual machines and LXC containers across your infrastructure. This allows you to control VMs, manage snapshots, and monitor status directly from the Veracity dashboard.

## Overview

The Proxmox integration allows you to:

- **Power Management** - Start, stop, shutdown, and reboot VMs/LXCs
- **Snapshot Management** - Create, rollback, and delete snapshots
- **Status Monitoring** - View real-time VM/LXC status and resource usage
- **VM Discovery** - Automatically discover VMs and containers on Proxmox nodes

## How It Works

Veracity uses the [Proxmoxer](https://github.com/proxmoxer/proxmoxer) Python library to interact with the Proxmox VE API. Commands are executed via Salt on your Proxmox hosts.

```
┌─────────────┐      Salt API      ┌─────────────┐     Proxmoxer     ┌─────────────┐
│   Veracity  │ ─────────────────► │   Proxmox   │ ────────────────► │ Proxmox API │
│   (Rails)   │                    │   (Minion)  │                   │  (REST)     │
└─────────────┘                    └─────────────┘                   └─────────────┘
```

The Python script (`proxmox_api.py`) runs directly on your Proxmox hosts, connecting to `localhost` to avoid SSL certificate issues with self-signed certificates.

## Prerequisites

Before using the Proxmox integration:

1. **Proxmox VE 7.0+** - Tested with Proxmox VE 7.x and 8.x
2. **Salt Minion** - Installed on each Proxmox host
3. **API Token** - Created in Proxmox with appropriate permissions
4. **Python 3** - With `proxmoxer` and `requests` packages

### Installing Dependencies on Proxmox

```bash
# Install Python packages
apt update
apt install python3-pip
pip3 install proxmoxer requests
```

### Creating an API Token

1. Log into your Proxmox web interface
2. Navigate to **Datacenter → Permissions → API Tokens**
3. Click **Add** and configure:
   - **User**: Select an existing user (e.g., `root@pam`)
   - **Token ID**: A name for the token (e.g., `veracity`)
   - **Privilege Separation**: Uncheck for full user permissions
4. Click **Add** and **copy the token value** (shown only once!)

### Required Permissions

The API token needs these permissions:

| Permission | Purpose |
|------------|---------|
| `VM.PowerMgmt` | Start, stop, shutdown, reboot |
| `VM.Snapshot` | Create, rollback, delete snapshots |
| `VM.Audit` | View VM status and configuration |
| `Datastore.Audit` | View storage information |

For full access, assign the `Administrator` role to your API token user.

## Configuration

Access Proxmox settings at **Administration → Integrations → Proxmox**.

### Adding an API Key

1. Navigate to **Administration → Integrations → Proxmox**
2. Fill in the API key form:

| Field | Description | Example |
|-------|-------------|---------|
| **Name** | Descriptive name | `PVE-Cluster-1` |
| **Proxmox URL** | Server URL (without port) | `https://pve.example.com` |
| **Minion ID** | Salt minion ID of Proxmox host | `pve-1.example.com` |
| **Username** | Proxmox username | `root` |
| **Realm** | Authentication realm | `pam` |
| **Token Name** | API token name | `veracity` |
| **API Token** | Token secret value | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| **Verify SSL** | Validate SSL certificate | Usually disabled for self-signed |

3. Click **Add API Key**

### Token Format

Proxmox API tokens have the format: `user@realm!tokenname=secret`

Veracity constructs this automatically from the fields you provide:
- Username: `root`
- Realm: `pam`
- Token Name: `veracity`
- Token Value: `abc123...`

Results in: `root@pam!veracity=abc123...`

## Security

Veracity uses multiple layers of security for Proxmox API tokens:

### At Rest (Database)

API tokens are encrypted using AES-256 via the `attr_encrypted` gem. The encryption key is derived from your Rails application's `SECRET_KEY_BASE`.

### In Transit (Salt Pillar)

When executing commands, Veracity uses **Salt Pillar** to pass credentials securely:

```
┌─────────────────┐     AES Encrypted      ┌─────────────────┐
│   Salt Master   │ ─────────────────────► │  Proxmox Host   │
│                 │                        │  (Salt Minion)  │
│  Pillar Data:   │   Only THIS minion     │                 │
│  - api_url      │   can decrypt          │  Receives:      │
│  - token        │                        │  - Credentials  │
└─────────────────┘                        └─────────────────┘
```

**Why Pillar instead of command-line arguments?**

| Method | `ps aux` | Salt Job Cache | Security |
|--------|----------|----------------|----------|
| Command-line args | **Visible** | Stored | Insecure |
| Environment vars (Pillar) | **Hidden** | Not stored | Secure |

The API token **never appears** in:
- Process listings (`ps aux`)
- Salt's job cache on the master
- Log files
- Shell history

### Execution Flow

1. **Write Pillar** - Credentials written to `/srv/pillar/minions/<minion_id>/proxmox.sls`
2. **Refresh Pillar** - Minion fetches encrypted pillar data
3. **Execute** - Python script reads credentials from environment variables
4. **Cleanup** - Pillar file deleted immediately after execution

## Managing Proxmox Servers

### Linking a Server to Proxmox

1. Navigate to the server's edit page
2. In the **Proxmox Configuration** section:
   - Select the **Proxmox API Key** to use
   - Enter the **Proxmox Node** name (e.g., `pve-1`)
   - Enter the **VM ID** (e.g., `100`)
   - Select the **VM Type** (QEMU or LXC)
3. Save the server

### Power Management

Once linked, you can control the VM/LXC from the server detail page:

| Action | Description |
|--------|-------------|
| **Start** | Power on the VM/LXC |
| **Stop** | Force power off (like pulling the plug) |
| **Shutdown** | Graceful shutdown via ACPI/agent |
| **Reboot** | Restart the VM/LXC |
| **Refresh Status** | Update status from Proxmox |

### Snapshot Management

Create and manage snapshots:

1. Navigate to the server detail page
2. Click **Snapshots** tab
3. Available actions:
   - **Create Snapshot** - Enter name and optional description
   - **Rollback** - Restore VM to snapshot state
   - **Delete** - Remove a snapshot

:::warning
Rolling back a snapshot will restore the VM to its previous state. Any changes made after the snapshot will be lost!
:::

## Discovering VMs

To discover VMs on a Proxmox node:

1. Go to **Administration → Integrations → Proxmox**
2. Find the API key for your Proxmox host
3. Click **Discover VMs**
4. Select VMs to import as managed servers

## Troubleshooting

### Connection Test Fails

**Symptom:** "Connection test failed" error

**Solutions:**
1. Verify the Proxmox host is reachable from the Salt master
2. Check the Salt minion is running on the Proxmox host:
   ```bash
   systemctl status salt-minion
   ```
3. Test Salt connectivity:
   ```bash
   salt 'pve-1*' test.ping
   ```
4. Verify Python dependencies are installed:
   ```bash
   python3 -c "import proxmoxer; print('OK')"
   ```

### Permission Denied

**Symptom:** API returns 403 or permission errors

**Solutions:**
1. Check the API token has required permissions
2. Verify privilege separation is disabled (or permissions are correctly assigned)
3. Test the token directly:
   ```bash
   curl -k -H "Authorization: PVEAPIToken=user@realm!token=secret" \
     https://localhost:8006/api2/json/version
   ```

### SSL Certificate Errors

**Symptom:** SSL verification fails

**Solutions:**
1. Disable SSL verification in the API key settings
2. Or install a valid certificate on your Proxmox host
3. The Python script connects to `localhost` to bypass hostname verification

### State Execution Fails

**Symptom:** "State execution failed" error

**Solutions:**
1. Verify the `proxmox_api.sls` state file exists on the Salt master:
   ```bash
   ls -la /srv/salt/proxmox_api.sls
   ```
2. Check the Python script is deployed:
   ```bash
   salt 'pve-1*' cmd.run 'ls -la /usr/local/bin/proxmox_api.py'
   ```
3. Check Salt master logs:
   ```bash
   tail -f /var/log/salt/master
   ```

### VM Operations Timeout

**Symptom:** Operations timeout before completing

**Solutions:**
1. Increase the timeout in ProxmoxService (default: 60 seconds)
2. Check if the VM is responding to ACPI commands (for shutdown)
3. Use "Stop" instead of "Shutdown" for unresponsive VMs

## Python Script Reference

The `proxmox_api.py` script supports these commands:

| Command | Description | Required Params |
|---------|-------------|-----------------|
| `test_connection` | Verify API connectivity | - |
| `list_vms` | List all VMs/LXCs on a node | node |
| `get_vm_status` | Get VM/LXC status | node, vmid, vm_type |
| `start_vm` | Start VM/LXC | node, vmid, vm_type |
| `stop_vm` | Force stop VM/LXC | node, vmid, vm_type |
| `shutdown_vm` | Graceful shutdown | node, vmid, vm_type |
| `reboot_vm` | Reboot VM/LXC | node, vmid, vm_type |
| `list_snapshots` | List snapshots | node, vmid, vm_type |
| `create_snapshot` | Create snapshot | node, vmid, vm_type, snap_name |
| `rollback_snapshot` | Rollback to snapshot | node, vmid, vm_type, snap_name |
| `delete_snapshot` | Delete snapshot | node, vmid, vm_type, snap_name |

### Secure Mode (--env flag)

When using the `--env` flag, credentials are read from environment variables:

```bash
export PROXMOX_API_URL="https://pve:8006"
export PROXMOX_USERNAME="root@pam"
export PROXMOX_TOKEN="veracity=secret"
export PROXMOX_VERIFY_SSL="false"
export PROXMOX_NODE="pve-1"
export PROXMOX_VMID="100"
export PROXMOX_VM_TYPE="qemu"

python3 /usr/local/bin/proxmox_api.py start_vm --env
```

This is the default mode used by Veracity for security.

## Understanding Salt Integration

### Why Salt?

Veracity uses Salt to execute commands on Proxmox hosts because:

1. **Secure Communication** - Salt uses AES encryption between master and minions
2. **Centralized Management** - All Proxmox hosts managed from one place
3. **Credential Security** - Pillar data keeps secrets encrypted
4. **Reliable Execution** - Salt handles retries and error reporting

### Pillar Data Structure

When executing a Proxmox command, Veracity creates temporary pillar data:

```yaml
# /srv/pillar/minions/pve-1.example.com/proxmox.sls
proxmox:
  api_url: https://pve.example.com:8006
  username: root@pam
  token: veracity=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  verify_ssl: "false"
  command: start_vm
  node: pve-1
  vmid: "100"
  vm_type: qemu
```

This file is:
- Written before command execution
- Encrypted in transit to the minion
- Deleted immediately after execution

### Salt State

The `proxmox_api.sls` state file sets environment variables from pillar and executes the script:

```yaml
proxmox_api_execute:
  cmd.run:
    - name: python3 /usr/local/bin/proxmox_api.py {{ pillar['proxmox']['command'] }} --env
    - env:
      - PROXMOX_API_URL: '{{ pillar["proxmox"]["api_url"] }}'
      - PROXMOX_USERNAME: '{{ pillar["proxmox"]["username"] }}'
      - PROXMOX_TOKEN: '{{ pillar["proxmox"]["token"] }}'
      # ... additional environment variables
```

## Related Resources

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
- [Proxmoxer Python Library](https://github.com/proxmoxer/proxmoxer)
- [Salt Pillar Documentation](https://docs.saltproject.io/en/latest/topics/pillar/)
