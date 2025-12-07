#!/usr/bin/env python3
"""
Hetzner Cloud Operations Script
Used by HetznerService and HetznerSnapshotService for server control and snapshot management
"""

import sys
import json
import time
from datetime import datetime
from hcloud import Client
from hcloud.images.domain import Image
from hcloud.servers.domain import Server

def json_response(success, data=None, error=None):
    """Return standardized JSON response"""
    response = {
        'success': success,
        'timestamp': datetime.now().isoformat()
    }
    if data:
        response['data'] = data
    if error:
        response['error'] = error
    return json.dumps(response, indent=2)

def start_server(api_token, server_id):
    """Power on a server"""
    try:
        client = Client(token=api_token)
        server = client.servers.get_by_id(server_id)

        if not server:
            return json_response(False, error=f"Server {server_id} not found")

        if server.status == Server.STATUS_RUNNING:
            return json_response(True, data={
                'server_id': server.id,
                'name': server.name,
                'status': 'running',
                'message': 'Server is already running'
            })

        action = server.power_on()
        action.wait_until_finished(max_retries=60)  # Wait up to 5 minutes

        server = client.servers.get_by_id(server_id)  # Refresh

        return json_response(True, data={
            'server_id': server.id,
            'name': server.name,
            'status': server.status,
            'public_ipv4': server.public_net.ipv4.ip if server.public_net.ipv4 else None,
            'message': 'Server started successfully'
        })
    except Exception as e:
        return json_response(False, error=str(e))

def stop_server(api_token, server_id):
    """Gracefully shutdown a server"""
    try:
        client = Client(token=api_token)
        server = client.servers.get_by_id(server_id)

        if not server:
            return json_response(False, error=f"Server {server_id} not found")

        if server.status == Server.STATUS_OFF:
            return json_response(True, data={
                'server_id': server.id,
                'name': server.name,
                'status': 'off',
                'message': 'Server is already stopped'
            })

        action = server.shutdown()
        action.wait_until_finished(max_retries=60)

        server = client.servers.get_by_id(server_id)

        return json_response(True, data={
            'server_id': server.id,
            'name': server.name,
            'status': server.status,
            'message': 'Server stopped successfully'
        })
    except Exception as e:
        return json_response(False, error=str(e))

def reboot_server(api_token, server_id):
    """Reboot a server"""
    try:
        client = Client(token=api_token)
        server = client.servers.get_by_id(server_id)

        if not server:
            return json_response(False, error=f"Server {server_id} not found")

        action = server.reboot()
        action.wait_until_finished(max_retries=60)

        return json_response(True, data={
            'server_id': server.id,
            'name': server.name,
            'status': 'rebooting',
            'message': 'Server rebooted successfully'
        })
    except Exception as e:
        return json_response(False, error=str(e))

def get_server_status(api_token, server_id):
    """Get current server status and details"""
    try:
        client = Client(token=api_token)
        server = client.servers.get_by_id(server_id)

        if not server:
            return json_response(False, error=f"Server {server_id} not found")

        return json_response(True, data={
            'server_id': server.id,
            'name': server.name,
            'status': server.status,
            'server_type': server.server_type.name,
            'datacenter': server.datacenter.name if server.datacenter else None,
            'location': server.datacenter.location.name if server.datacenter else None,
            'public_ipv4': server.public_net.ipv4.ip if server.public_net.ipv4 else None,
            'public_ipv6': server.public_net.ipv6.ip if server.public_net.ipv6 else None,
            'created': server.created.isoformat() if server.created else None,
            'backup_window': server.backup_window,
            'locked': server.locked
        })
    except Exception as e:
        return json_response(False, error=str(e))

def check_snapshot_in_progress(api_token, server_id):
    """Check if server has a snapshot currently being created"""
    try:
        client = Client(token=api_token)

        # Get all snapshots (images of type snapshot)
        images = client.images.get_all(type="snapshot")

        # Filter for this server's snapshots that are in 'creating' status
        for img in images:
            # Check if snapshot is for this server (by created_from metadata)
            if img.created_from and img.created_from.id == server_id:
                if img.status == "creating":
                    return {
                        'in_progress': True,
                        'snapshot_id': img.id,
                        'description': img.description,
                        'status': img.status
                    }

        return {'in_progress': False}
    except Exception as e:
        # If check fails, allow creation attempt to proceed
        return {'in_progress': False, 'error': str(e)}

def create_snapshot(api_token, server_id, description):
    """Create a snapshot (image) of a server"""
    try:
        client = Client(token=api_token)
        server = client.servers.get_by_id(server_id)

        if not server:
            return json_response(False, error=f"Server {server_id} not found")

        # Check if a snapshot is already being created for this server
        check_result = check_snapshot_in_progress(api_token, server_id)

        if check_result['in_progress']:
            # Return success with the existing snapshot ID to wait for it
            return json_response(True, data={
                'snapshot_id': check_result['snapshot_id'],
                'description': check_result['description'],
                'status': check_result['status'],
                'already_in_progress': True,
                'message': f"Snapshot already in progress: {check_result['description']}. Will wait for it to complete."
            })

        # No snapshot in progress, create a new one
        response = server.create_image(description=description, type="snapshot")
        image = response.image
        action = response.action

        return json_response(True, data={
            'snapshot_id': image.id,
            'description': image.description,
            'status': image.status,
            'created': image.created.isoformat() if image.created else None,
            'disk_size': image.disk_size,
            'image_size': image.image_size,
            'action_id': action.id,
            'already_in_progress': False,
            'message': 'Snapshot creation initiated'
        })
    except Exception as e:
        return json_response(False, error=str(e))

def wait_for_snapshot(api_token, snapshot_id, timeout=900):
    """Wait for snapshot to complete (max timeout in seconds)"""
    try:
        client = Client(token=api_token)
        start_time = time.time()

        while (time.time() - start_time) < timeout:
            image = client.images.get_by_id(snapshot_id)

            if not image:
                return json_response(False, error=f"Snapshot {snapshot_id} not found")

            if image.status == "available":
                return json_response(True, data={
                    'snapshot_id': image.id,
                    'description': image.description,
                    'status': 'available',
                    'disk_size': image.disk_size,
                    'image_size': image.image_size,
                    'duration_seconds': int(time.time() - start_time),
                    'message': 'Snapshot completed successfully'
                })
            elif image.status == "creating":
                time.sleep(10)  # Check every 10 seconds
            else:
                return json_response(False, error=f"Unexpected snapshot status: {image.status}")

        return json_response(False, error=f"Snapshot creation timed out after {timeout} seconds")
    except Exception as e:
        return json_response(False, error=str(e))

def list_snapshots(api_token, server_name=None, server_id=None):
    """List all snapshots, optionally filtered by server name or ID"""
    try:
        client = Client(token=api_token)

        # Get all images of type snapshot
        images = client.images.get_all(type="snapshot")

        snapshots = []
        snapshots_with_prefix = []
        snapshots_for_server = []
        all_snapshots_for_project = []

        for img in images:
            # Build snapshot info
            snapshot_info = {
                'snapshot_id': img.id,
                'description': img.description,
                'status': img.status,
                'created': img.created.isoformat() if img.created else None,
                'disk_size': img.disk_size,
                'image_size': img.image_size,
                'created_from_id': img.created_from.id if img.created_from else None
            }

            all_snapshots_for_project.append(snapshot_info)

            # If filtering requested, try multiple matching strategies
            if server_name or server_id:
                # Strategy 1: Match by created_from server ID (most reliable)
                if server_id and img.created_from and img.created_from.id == int(server_id):
                    snapshots_for_server.append(snapshot_info)

                # Strategy 2: Match by description prefix (for new snapshots with hostname)
                if server_name and img.description.startswith(f"{server_name}-"):
                    snapshots_with_prefix.append(snapshot_info)
            else:
                # No filter - include all
                snapshots.append(snapshot_info)

        # Prioritize filtering strategies
        if server_id and snapshots_for_server:
            # Best: Found snapshots for this specific server by ID
            snapshots = snapshots_for_server
        elif server_name and snapshots_with_prefix:
            # Good: Found snapshots with hostname prefix
            snapshots = snapshots_with_prefix
        elif server_name or server_id:
            # Fallback: Show all project snapshots (better than showing none)
            # This helps with old snapshots that don't have proper naming
            snapshots = all_snapshots_for_project
        # else: already set to all_snapshots_for_project if no filter

        return json_response(True, data={
            'snapshots': snapshots,
            'count': len(snapshots),
            'filter_used': 'server_id' if (server_id and snapshots_for_server) else 'hostname_prefix' if (server_name and snapshots_with_prefix) else 'all_project'
        })
    except Exception as e:
        return json_response(False, error=str(e))

def delete_snapshot(api_token, snapshot_id):
    """Delete a snapshot"""
    try:
        client = Client(token=api_token)
        image = client.images.get_by_id(snapshot_id)

        if not image:
            return json_response(False, error=f"Snapshot {snapshot_id} not found")

        image.delete()

        return json_response(True, data={
            'snapshot_id': snapshot_id,
            'message': 'Snapshot deleted successfully'
        })
    except Exception as e:
        return json_response(False, error=str(e))

def main():
    """Main entry point for command-line usage"""
    if len(sys.argv) < 3:
        print(json_response(False, error="Usage: hetzner_cloud.py <command> <api_token> [args...]"))
        sys.exit(1)

    command = sys.argv[1]
    api_token = sys.argv[2]

    if command == "start":
        if len(sys.argv) < 4:
            print(json_response(False, error="Usage: hetzner_cloud.py start <api_token> <server_id>"))
            sys.exit(1)
        print(start_server(api_token, int(sys.argv[3])))

    elif command == "stop":
        if len(sys.argv) < 4:
            print(json_response(False, error="Usage: hetzner_cloud.py stop <api_token> <server_id>"))
            sys.exit(1)
        print(stop_server(api_token, int(sys.argv[3])))

    elif command == "reboot":
        if len(sys.argv) < 4:
            print(json_response(False, error="Usage: hetzner_cloud.py reboot <api_token> <server_id>"))
            sys.exit(1)
        print(reboot_server(api_token, int(sys.argv[3])))

    elif command == "status":
        if len(sys.argv) < 4:
            print(json_response(False, error="Usage: hetzner_cloud.py status <api_token> <server_id>"))
            sys.exit(1)
        print(get_server_status(api_token, int(sys.argv[3])))

    elif command == "create_snapshot":
        if len(sys.argv) < 5:
            print(json_response(False, error="Usage: hetzner_cloud.py create_snapshot <api_token> <server_id> <description>"))
            sys.exit(1)
        print(create_snapshot(api_token, int(sys.argv[3]), sys.argv[4]))

    elif command == "wait_snapshot":
        if len(sys.argv) < 4:
            print(json_response(False, error="Usage: hetzner_cloud.py wait_snapshot <api_token> <snapshot_id> [timeout]"))
            sys.exit(1)
        timeout = int(sys.argv[4]) if len(sys.argv) > 4 else 900
        print(wait_for_snapshot(api_token, int(sys.argv[3]), timeout))

    elif command == "list_snapshots":
        server_name = sys.argv[3] if len(sys.argv) > 3 else None
        print(list_snapshots(api_token, server_name))

    elif command == "delete_snapshot":
        if len(sys.argv) < 4:
            print(json_response(False, error="Usage: hetzner_cloud.py delete_snapshot <api_token> <snapshot_id>"))
            sys.exit(1)
        print(delete_snapshot(api_token, int(sys.argv[3])))

    else:
        print(json_response(False, error=f"Unknown command: {command}"))
        sys.exit(1)

if __name__ == "__main__":
    main()
