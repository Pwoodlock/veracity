# Salt States for Veracity

This directory contains Salt state files used by Veracity for secure deployments.

## Deployment

These files need to be deployed to the Salt master's file server root:

```bash
# Copy state files to Salt master
sudo cp *.sls /srv/salt/

# Set proper permissions
sudo chown root:root /srv/salt/*.sls
sudo chmod 644 /srv/salt/*.sls
```

## State Files

### netbird.sls

Installs and configures NetBird agent using **pillar data** for secrets.

**Pillar data required:**
```yaml
netbird:
  management_url: https://your-server:443
  setup_key: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

### proxmox_api.sls

Executes Proxmox API commands using **pillar data** for credentials.

**Pillar data required:**
```yaml
proxmox:
  api_url: https://proxmox-server:8006
  username: user@pam
  token: tokenname=secret
  verify_ssl: true
  command: test_connection | list_vms | start_vm | stop_vm | etc.
  node: pve-1 (optional)
  vmid: 100 (optional)
  vm_type: qemu | lxc (optional)
  snap_name: snapshot-name (optional)
```

## Why Pillar for Secrets?

Sensitive data like API tokens should never appear in:
- Command-line arguments (visible via `ps aux`)
- Salt job cache
- Shell history

Salt Pillar provides:
- **Encrypted transit** - AES encryption between master and minion
- **Per-minion isolation** - Each minion only sees its own data
- **No command-line exposure** - Credentials passed via environment variables

## Security Flow

1. Veracity writes pillar data to `/srv/pillar/minions/<minion_id>/<name>.sls`
2. Minion fetches pillar data (encrypted in transit)
3. State uses credentials (via env vars or temp files)
4. Pillar file is deleted from master immediately after

## Pillar Configuration

Ensure your Salt master's pillar configuration includes per-minion pillar data:

```yaml
# /srv/pillar/top.sls
base:
  '*':
    - common
```

Veracity dynamically creates per-minion pillar files in `/srv/pillar/minions/`.
