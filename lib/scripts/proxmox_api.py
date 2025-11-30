#!/usr/bin/env python3
"""
Proxmox VE Operations Script
Used by ProxmoxService for VM/LXC control and snapshot management
Supports both QEMU VMs and LXC containers

SECURITY: Supports reading credentials from environment variables to avoid
exposing API tokens in command-line arguments (visible via ps aux).

Environment variables (used when --env flag is passed):
  PROXMOX_API_URL      - Proxmox server URL
  PROXMOX_USERNAME     - Username (e.g., user@pam)
  PROXMOX_TOKEN        - API token (tokenname=secret)
  PROXMOX_VERIFY_SSL   - Whether to verify SSL (true/false)
  PROXMOX_NODE         - Node name (for node-specific commands)
  PROXMOX_VMID         - VM/LXC ID (for VM-specific commands)
  PROXMOX_VM_TYPE      - VM type: qemu or lxc
  PROXMOX_SNAP_NAME    - Snapshot name (for snapshot commands)
  PROXMOX_SNAP_DESC    - Snapshot description (optional)
"""

import sys
import os
import json
import time
from datetime import datetime
from proxmoxer import ProxmoxAPI
import urllib3

# Disable SSL warnings if verify_ssl is False
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


def get_env_credentials():
    """Read credentials from environment variables (secure method)"""
    return {
        'api_url': os.environ.get('PROXMOX_API_URL', ''),
        'username': os.environ.get('PROXMOX_USERNAME', ''),
        'token': os.environ.get('PROXMOX_TOKEN', ''),
        'verify_ssl': os.environ.get('PROXMOX_VERIFY_SSL', 'true').lower() == 'true',
        'node': os.environ.get('PROXMOX_NODE', ''),
        'vmid': os.environ.get('PROXMOX_VMID', ''),
        'vm_type': os.environ.get('PROXMOX_VM_TYPE', ''),
        'snap_name': os.environ.get('PROXMOX_SNAP_NAME', ''),
        'snap_desc': os.environ.get('PROXMOX_SNAP_DESC', ''),
    }

def json_response(success, data=None, error=None, message=None):
    """Return standardized JSON response"""
    response = {
        'success': success,
        'timestamp': datetime.now().isoformat()
    }
    if data:
        response['data'] = data
    if error:
        response['error'] = error
    if message:
        response['message'] = message
    return json.dumps(response, indent=2)

def connect_proxmox(api_url, username, token, verify_ssl=True):
    """Establish connection to Proxmox API"""
    # Since this script runs ON the Proxmox server itself via Salt minion,
    # always connect to localhost to avoid SSL certificate issues
    # This bypasses hostname verification problems with self-signed certificates
    host = 'localhost'

    # Connect to Proxmox using token authentication
    # Use 'https' backend with localhost
    proxmox = ProxmoxAPI(
        host,
        user=username,
        token_name=token.split('=')[0] if '=' in token else 'api',
        token_value=token.split('=')[1] if '=' in token else token,
        backend='https',
        verify_ssl=verify_ssl
    )
    return proxmox

def get_vm_status(api_url, username, token, node, vmid, vm_type, verify_ssl=True):
    """Get VM or LXC container status"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        if vm_type == 'qemu':
            vm_info = proxmox.nodes(node).qemu(vmid).status.current.get()
        elif vm_type == 'lxc':
            vm_info = proxmox.nodes(node).lxc(vmid).status.current.get()
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type,
            'status': vm_info['status'],
            'uptime': vm_info.get('uptime', 0),
            'cpus': vm_info.get('cpus', 0),
            'memory': vm_info.get('mem', 0),
            'maxmem': vm_info.get('maxmem', 0),
            'name': vm_info.get('name', f'{vm_type}-{vmid}')
        })
    except Exception as e:
        return json_response(False, error=str(e))

def start_vm(api_url, username, token, node, vmid, vm_type, verify_ssl=True):
    """Start VM or LXC container"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        # Check current status
        if vm_type == 'qemu':
            current = proxmox.nodes(node).qemu(vmid).status.current.get()
            if current['status'] == 'running':
                return json_response(True, data={'status': 'running'}, message=f'{vm_type.upper()} is already running')

            # Start VM
            proxmox.nodes(node).qemu(vmid).status.start.post()
        elif vm_type == 'lxc':
            current = proxmox.nodes(node).lxc(vmid).status.current.get()
            if current['status'] == 'running':
                return json_response(True, data={'status': 'running'}, message=f'{vm_type.upper()} is already running')

            # Start container
            proxmox.nodes(node).lxc(vmid).status.start.post()
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        # Wait a bit and check status
        time.sleep(2)

        if vm_type == 'qemu':
            new_status = proxmox.nodes(node).qemu(vmid).status.current.get()
        else:
            new_status = proxmox.nodes(node).lxc(vmid).status.current.get()

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type,
            'status': new_status['status']
        }, message=f'{vm_type.upper()} start initiated')
    except Exception as e:
        return json_response(False, error=str(e))

def stop_vm(api_url, username, token, node, vmid, vm_type, verify_ssl=True):
    """Force stop VM or LXC container"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        # Check current status
        if vm_type == 'qemu':
            current = proxmox.nodes(node).qemu(vmid).status.current.get()
            if current['status'] == 'stopped':
                return json_response(True, data={'status': 'stopped'}, message=f'{vm_type.upper()} is already stopped')

            # Force stop VM
            proxmox.nodes(node).qemu(vmid).status.stop.post()
        elif vm_type == 'lxc':
            current = proxmox.nodes(node).lxc(vmid).status.current.get()
            if current['status'] == 'stopped':
                return json_response(True, data={'status': 'stopped'}, message=f'{vm_type.upper()} is already stopped')

            # Force stop container
            proxmox.nodes(node).lxc(vmid).status.stop.post()
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        # Wait a bit and check status
        time.sleep(2)

        if vm_type == 'qemu':
            new_status = proxmox.nodes(node).qemu(vmid).status.current.get()
        else:
            new_status = proxmox.nodes(node).lxc(vmid).status.current.get()

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type,
            'status': new_status['status']
        }, message=f'{vm_type.upper()} stop initiated')
    except Exception as e:
        return json_response(False, error=str(e))

def shutdown_vm(api_url, username, token, node, vmid, vm_type, verify_ssl=True):
    """Gracefully shutdown VM or LXC container"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        # Check current status
        if vm_type == 'qemu':
            current = proxmox.nodes(node).qemu(vmid).status.current.get()
            if current['status'] == 'stopped':
                return json_response(True, data={'status': 'stopped'}, message=f'{vm_type.upper()} is already stopped')

            # Graceful shutdown VM
            proxmox.nodes(node).qemu(vmid).status.shutdown.post()
        elif vm_type == 'lxc':
            current = proxmox.nodes(node).lxc(vmid).status.current.get()
            if current['status'] == 'stopped':
                return json_response(True, data={'status': 'stopped'}, message=f'{vm_type.upper()} is already stopped')

            # Graceful shutdown container
            proxmox.nodes(node).lxc(vmid).status.shutdown.post()
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type,
            'status': 'shutting_down'
        }, message=f'{vm_type.upper()} graceful shutdown initiated')
    except Exception as e:
        return json_response(False, error=str(e))

def reboot_vm(api_url, username, token, node, vmid, vm_type, verify_ssl=True):
    """Reboot VM or LXC container"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        if vm_type == 'qemu':
            proxmox.nodes(node).qemu(vmid).status.reboot.post()
        elif vm_type == 'lxc':
            proxmox.nodes(node).lxc(vmid).status.reboot.post()
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type
        }, message=f'{vm_type.upper()} reboot initiated')
    except Exception as e:
        return json_response(False, error=str(e))

def list_snapshots(api_url, username, token, node, vmid, vm_type, verify_ssl=True):
    """List all snapshots for VM or LXC"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        if vm_type == 'qemu':
            snapshots = proxmox.nodes(node).qemu(vmid).snapshot.get()
        elif vm_type == 'lxc':
            snapshots = proxmox.nodes(node).lxc(vmid).snapshot.get()
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        snapshot_list = []
        for snap in snapshots:
            if snap.get('name') not in ['current', None]:
                snapshot_list.append({
                    'name': snap.get('name'),
                    'description': snap.get('description', ''),
                    'snaptime': snap.get('snaptime', 0),
                    'vmstate': snap.get('vmstate', 0)
                })

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type,
            'snapshots': snapshot_list,
            'count': len(snapshot_list)
        })
    except Exception as e:
        return json_response(False, error=str(e))

def create_snapshot(api_url, username, token, node, vmid, vm_type, snap_name, description='', verify_ssl=True):
    """Create snapshot of VM or LXC"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        if vm_type == 'qemu':
            proxmox.nodes(node).qemu(vmid).snapshot.post(
                snapname=snap_name,
                description=description,
                vmstate=0  # Don't include RAM
            )
        elif vm_type == 'lxc':
            proxmox.nodes(node).lxc(vmid).snapshot.post(
                snapname=snap_name,
                description=description
            )
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type,
            'snapshot_name': snap_name
        }, message=f'Snapshot {snap_name} created')
    except Exception as e:
        return json_response(False, error=str(e))

def rollback_snapshot(api_url, username, token, node, vmid, vm_type, snap_name, verify_ssl=True):
    """Rollback VM or LXC to snapshot"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        if vm_type == 'qemu':
            proxmox.nodes(node).qemu(vmid).snapshot(snap_name).rollback.post()
        elif vm_type == 'lxc':
            proxmox.nodes(node).lxc(vmid).snapshot(snap_name).rollback.post()
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type,
            'snapshot_name': snap_name
        }, message=f'Rolled back to snapshot {snap_name}')
    except Exception as e:
        return json_response(False, error=str(e))

def delete_snapshot(api_url, username, token, node, vmid, vm_type, snap_name, verify_ssl=True):
    """Delete snapshot from VM or LXC"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        if vm_type == 'qemu':
            proxmox.nodes(node).qemu(vmid).snapshot(snap_name).delete()
        elif vm_type == 'lxc':
            proxmox.nodes(node).lxc(vmid).snapshot(snap_name).delete()
        else:
            return json_response(False, error=f"Invalid VM type: {vm_type}")

        return json_response(True, data={
            'vmid': vmid,
            'node': node,
            'type': vm_type,
            'snapshot_name': snap_name
        }, message=f'Snapshot {snap_name} deleted')
    except Exception as e:
        return json_response(False, error=str(e))

def list_vms(api_url, username, token, node, verify_ssl=True):
    """List all VMs and containers on a node"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        vms = []

        # Get QEMU VMs
        qemu_vms = proxmox.nodes(node).qemu.get()
        for vm in qemu_vms:
            vms.append({
                'vmid': vm['vmid'],
                'name': vm.get('name', f'vm-{vm["vmid"]}'),
                'type': 'qemu',
                'status': vm.get('status', 'unknown'),
                'cpus': vm.get('cpus', 0),
                'maxmem': vm.get('maxmem', 0)
            })

        # Get LXC containers
        lxc_containers = proxmox.nodes(node).lxc.get()
        for container in lxc_containers:
            vms.append({
                'vmid': container['vmid'],
                'name': container.get('name', f'ct-{container["vmid"]}'),
                'type': 'lxc',
                'status': container.get('status', 'unknown'),
                'cpus': container.get('cpus', 0),
                'maxmem': container.get('maxmem', 0)
            })

        return json_response(True, data={
            'node': node,
            'vms': vms,
            'count': len(vms)
        })
    except Exception as e:
        return json_response(False, error=str(e))

def test_connection(api_url, username, token, verify_ssl=True):
    """Test connection to Proxmox API"""
    try:
        proxmox = connect_proxmox(api_url, username, token, verify_ssl)
        if not proxmox:
            return json_response(False, error="Failed to connect to Proxmox API")

        # Get cluster status or version
        version = proxmox.version.get()
        nodes = proxmox.nodes.get()

        return json_response(True, data={
            'version': version.get('version', 'unknown'),
            'nodes': [node['node'] for node in nodes],
            'node_count': len(nodes)
        }, message='Connection successful')
    except Exception as e:
        return json_response(False, error=str(e))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json_response(False, error="Usage: proxmox_api.py <command> [--env | <args>]"))
        sys.exit(1)

    command = sys.argv[1]

    # Check if using environment variables (secure mode)
    use_env = '--env' in sys.argv

    try:
        if use_env:
            # SECURE MODE: Read credentials from environment variables
            # This prevents tokens from appearing in ps aux or shell history
            env = get_env_credentials()

            if not env['api_url'] or not env['username'] or not env['token']:
                print(json_response(False, error="Missing required environment variables: PROXMOX_API_URL, PROXMOX_USERNAME, PROXMOX_TOKEN"))
                sys.exit(1)

            if command == 'test_connection':
                print(test_connection(env['api_url'], env['username'], env['token'], env['verify_ssl']))

            elif command == 'list_vms':
                if not env['node']:
                    print(json_response(False, error="Missing PROXMOX_NODE environment variable"))
                    sys.exit(1)
                print(list_vms(env['api_url'], env['username'], env['token'], env['node'], env['verify_ssl']))

            elif command in ['get_vm_status', 'start_vm', 'stop_vm', 'shutdown_vm', 'reboot_vm', 'list_snapshots']:
                if not env['node'] or not env['vmid'] or not env['vm_type']:
                    print(json_response(False, error="Missing required environment variables: PROXMOX_NODE, PROXMOX_VMID, PROXMOX_VM_TYPE"))
                    sys.exit(1)

                func = {
                    'get_vm_status': get_vm_status,
                    'start_vm': start_vm,
                    'stop_vm': stop_vm,
                    'shutdown_vm': shutdown_vm,
                    'reboot_vm': reboot_vm,
                    'list_snapshots': list_snapshots,
                }[command]
                print(func(env['api_url'], env['username'], env['token'], env['node'], int(env['vmid']), env['vm_type'], env['verify_ssl']))

            elif command == 'create_snapshot':
                if not env['node'] or not env['vmid'] or not env['vm_type'] or not env['snap_name']:
                    print(json_response(False, error="Missing required environment variables: PROXMOX_NODE, PROXMOX_VMID, PROXMOX_VM_TYPE, PROXMOX_SNAP_NAME"))
                    sys.exit(1)
                print(create_snapshot(env['api_url'], env['username'], env['token'], env['node'], int(env['vmid']), env['vm_type'], env['snap_name'], env['snap_desc'], env['verify_ssl']))

            elif command in ['rollback_snapshot', 'delete_snapshot']:
                if not env['node'] or not env['vmid'] or not env['vm_type'] or not env['snap_name']:
                    print(json_response(False, error="Missing required environment variables: PROXMOX_NODE, PROXMOX_VMID, PROXMOX_VM_TYPE, PROXMOX_SNAP_NAME"))
                    sys.exit(1)

                func = rollback_snapshot if command == 'rollback_snapshot' else delete_snapshot
                print(func(env['api_url'], env['username'], env['token'], env['node'], int(env['vmid']), env['vm_type'], env['snap_name'], env['verify_ssl']))

            else:
                print(json_response(False, error=f"Unknown command: {command}"))
                sys.exit(1)

        else:
            # LEGACY MODE: Read credentials from command-line arguments
            # WARNING: Tokens are visible via ps aux - use --env mode for security
            if command == 'test_connection':
                api_url, username, token = sys.argv[2], sys.argv[3], sys.argv[4]
                verify_ssl = sys.argv[5].lower() == 'true' if len(sys.argv) > 5 else True
                print(test_connection(api_url, username, token, verify_ssl))

            elif command == 'get_vm_status':
                api_url, username, token, node, vmid, vm_type = sys.argv[2:8]
                verify_ssl = sys.argv[8].lower() == 'true' if len(sys.argv) > 8 else True
                print(get_vm_status(api_url, username, token, node, int(vmid), vm_type, verify_ssl))

            elif command == 'start_vm':
                api_url, username, token, node, vmid, vm_type = sys.argv[2:8]
                verify_ssl = sys.argv[8].lower() == 'true' if len(sys.argv) > 8 else True
                print(start_vm(api_url, username, token, node, int(vmid), vm_type, verify_ssl))

            elif command == 'stop_vm':
                api_url, username, token, node, vmid, vm_type = sys.argv[2:8]
                verify_ssl = sys.argv[8].lower() == 'true' if len(sys.argv) > 8 else True
                print(stop_vm(api_url, username, token, node, int(vmid), vm_type, verify_ssl))

            elif command == 'shutdown_vm':
                api_url, username, token, node, vmid, vm_type = sys.argv[2:8]
                verify_ssl = sys.argv[8].lower() == 'true' if len(sys.argv) > 8 else True
                print(shutdown_vm(api_url, username, token, node, int(vmid), vm_type, verify_ssl))

            elif command == 'reboot_vm':
                api_url, username, token, node, vmid, vm_type = sys.argv[2:8]
                verify_ssl = sys.argv[8].lower() == 'true' if len(sys.argv) > 8 else True
                print(reboot_vm(api_url, username, token, node, int(vmid), vm_type, verify_ssl))

            elif command == 'list_snapshots':
                api_url, username, token, node, vmid, vm_type = sys.argv[2:8]
                verify_ssl = sys.argv[8].lower() == 'true' if len(sys.argv) > 8 else True
                print(list_snapshots(api_url, username, token, node, int(vmid), vm_type, verify_ssl))

            elif command == 'create_snapshot':
                api_url, username, token, node, vmid, vm_type, snap_name = sys.argv[2:9]
                description = sys.argv[9] if len(sys.argv) > 9 else ''
                verify_ssl = sys.argv[10].lower() == 'true' if len(sys.argv) > 10 else True
                print(create_snapshot(api_url, username, token, node, int(vmid), vm_type, snap_name, description, verify_ssl))

            elif command == 'rollback_snapshot':
                api_url, username, token, node, vmid, vm_type, snap_name = sys.argv[2:9]
                verify_ssl = sys.argv[9].lower() == 'true' if len(sys.argv) > 9 else True
                print(rollback_snapshot(api_url, username, token, node, int(vmid), vm_type, snap_name, verify_ssl))

            elif command == 'delete_snapshot':
                api_url, username, token, node, vmid, vm_type, snap_name = sys.argv[2:9]
                verify_ssl = sys.argv[9].lower() == 'true' if len(sys.argv) > 9 else True
                print(delete_snapshot(api_url, username, token, node, int(vmid), vm_type, snap_name, verify_ssl))

            elif command == 'list_vms':
                api_url, username, token, node = sys.argv[2:6]
                verify_ssl = sys.argv[6].lower() == 'true' if len(sys.argv) > 6 else True
                print(list_vms(api_url, username, token, node, verify_ssl))

            else:
                print(json_response(False, error=f"Unknown command: {command}"))
                sys.exit(1)

    except IndexError:
        print(json_response(False, error=f"Missing required arguments for command: {command}"))
        sys.exit(1)
    except Exception as e:
        print(json_response(False, error=str(e)))
        sys.exit(1)
