# Salt State for Secure Proxmox API Execution
# This state executes the proxmox_api.py script using PILLAR DATA for credentials
# The API token is NEVER passed as a command-line argument
#
# Pillar data expected:
#   proxmox:
#     api_url: https://proxmox-server:8006
#     username: user@pam
#     token: tokenname=secret
#     verify_ssl: true
#     command: test_connection | list_vms | start_vm | stop_vm | etc.
#     node: pve-1 (optional, for node-specific commands)
#     vmid: 100 (optional, for VM-specific commands)
#     vm_type: qemu | lxc (optional)
#     snap_name: snapshot-name (optional)
#     snap_desc: description (optional)
#
# Security: Credentials are read from environment variables set from pillar,
# never appearing in command-line arguments or ps aux output.
#
# Deploy this file to: /srv/salt/proxmox_api.sls

# Execute proxmox_api.py with credentials from environment variables
proxmox_api_execute:
  cmd.run:
    - name: python3 /usr/local/bin/proxmox_api.py {{ pillar['proxmox']['command'] }} --env
    - env:
      - PROXMOX_API_URL: '{{ pillar["proxmox"]["api_url"] }}'
      - PROXMOX_USERNAME: '{{ pillar["proxmox"]["username"] }}'
      - PROXMOX_TOKEN: '{{ pillar["proxmox"]["token"] }}'
      - PROXMOX_VERIFY_SSL: '{{ pillar["proxmox"].get("verify_ssl", "true") }}'
      {% if pillar['proxmox'].get('node') %}
      - PROXMOX_NODE: '{{ pillar["proxmox"]["node"] }}'
      {% endif %}
      {% if pillar['proxmox'].get('vmid') %}
      - PROXMOX_VMID: '{{ pillar["proxmox"]["vmid"] }}'
      {% endif %}
      {% if pillar['proxmox'].get('vm_type') %}
      - PROXMOX_VM_TYPE: '{{ pillar["proxmox"]["vm_type"] }}'
      {% endif %}
      {% if pillar['proxmox'].get('snap_name') %}
      - PROXMOX_SNAP_NAME: '{{ pillar["proxmox"]["snap_name"] }}'
      {% endif %}
      {% if pillar['proxmox'].get('snap_desc') %}
      - PROXMOX_SNAP_DESC: '{{ pillar["proxmox"]["snap_desc"] }}'
      {% endif %}
    - timeout: 60
