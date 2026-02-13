#!/usr/bin/env python3
"""
Force reset VMs in 'BUILD' status to 'ERROR' and/or delete ERROR VMs along with their attached volumes.
Uses openstack.connect() for authentication (environment variables or clouds.yaml).
Requires admin privileges for force delete and reset actions.

Behavior:
- No flags    → list all VMs sorted by status (ERROR first), show attached volumes
- --reset-build → reset ALL VMs in 'BUILD' status to 'ERROR'
- --force-delete → reset volumes attached to ERROR VMs to 'ERROR', delete them, then delete the ERROR VMs
"""

import argparse
import sys
import time
import logging

import openstack
from openstack import exceptions


def parse_args():
    parser = argparse.ArgumentParser(
        description="Reset BUILD VMs to ERROR and/or force-delete ERROR VMs with volumes"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Reset volumes attached to ERROR VMs to 'ERROR', delete them, then delete the VMs"
    )
    parser.add_argument(
        "--reset-build",
        action="store_true",
        help="Reset all VMs in BUILD status to ERROR"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show planned actions without executing any changes"
    )
    parser.add_argument(
        "--wait",
        type=int,
        default=3,
        help="Seconds to wait between operations (default: 3)"
    )
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level"
    )
    return parser.parse_args()


def setup_logging(level_str: str):
    logging.basicConfig(
        level=getattr(logging, level_str.upper()),
        format="%(asctime)s | %(levelname)-7s | %(message)s",
        datefmt="%H:%M:%S"
    )


def get_attached_volumes(conn, server):
    """Get list of volume IDs attached to the server"""
    volumes = []

    # From Nova extended volumes attribute
    for attachment in getattr(server, 'os-extended-volumes:volumes_attached', []):
        vol_id = attachment.get('id')
        if vol_id:
            volumes.append(vol_id)

    # Fallback: search volumes by instance_uuid
    if not volumes:
        logging.debug(f"Fallback: searching volumes attached to server {server.id}")
        try:
            all_vols = conn.block_storage.volumes(all_projects=True)
            for vol in all_vols:
                for att in getattr(vol, 'attachments', []):
                    if att.get('server_id') == server.id:
                        volumes.append(vol.id)
                        break
        except Exception as e:
            logging.warning(f"Volume search failed for server {server.id}: {e}")

    return volumes


def reset_server_state_with_fallback(conn, server_id, target_state="error"):
    """Attempt to reset server state using multiple methods"""
    try:
        conn.compute.reset_server_state(server_id, state=target_state)
        return True
    except exceptions.HttpException as e:
        if any(x in str(e) for x in ["DBReferenceError", "DatabaseError", "500"]):
            logging.warning(f"Standard reset failed for {server_id}, trying direct API")
        else:
            logging.error(f"Reset failed for {server_id}: {e}")
            return False
    except Exception as e:
        logging.error(f"Reset failed for {server_id}: {e}")
        return False

    # Direct admin API reset
    try:
        conn.compute.post(
            f"/servers/{server_id}/action",
            json={"os-resetState": {"state": target_state.upper()}}
        )
        logging.info(f"Reset {server_id} using direct API call")
        return True
    except Exception as e:
        logging.error(f"Direct API reset failed for {server_id}: {e}")
        return False


def force_delete_server_with_dependencies(conn, server_id):
    """Clean floating IPs if any, then force delete server"""
    try:
        # Clean floating IPs
        ports = list(conn.network.ports(device_id=server_id))
        for port in ports:
            floating_ips = list(conn.network.ips(port_id=port.id))
            for fip in floating_ips:
                logging.info(f"Disassociating floating IP {fip.id}")
                conn.network.update_ip(fip.id, port_id=None)
                time.sleep(1)

        conn.compute.delete_server(server_id, force=True)
        return True
    except Exception as e:
        logging.error(f"Force delete failed for server {server_id}: {e}")
        return False


def safe_delete_volume(conn, vol_id, server_id, wait_sec=5, max_attempts=24):
    """Attempt to delete volume with preparatory steps: detach, reset to error, delete snapshots, delete"""
    try:
        vol = conn.block_storage.get_volume(vol_id)
        if not vol:
            return True

        # Detach if still attached
        if vol.status == "in-use" or vol.attachments:
            logging.info(f"Detaching volume {vol_id} from server {server_id}")
            try:
                conn.compute.detach_volume(server_id, vol_id)
            except Exception:
                pass

            for _ in range(max_attempts):
                vol = conn.block_storage.get_volume(vol_id)
                if vol.status != "in-use" and not vol.attachments:
                    break
                time.sleep(wait_sec)

        # Reset to error
        try:
            conn.block_storage.reset_volume_status(vol_id, status='error')
            logging.info(f"Reset volume {vol_id} to 'error'")
            time.sleep(3)
        except Exception as e:
            logging.warning(f"Reset to 'error' failed for {vol_id}: {e}")

        # Delete snapshots if any
        snapshots = list(conn.block_storage.snapshots(volume_id=vol_id))
        for snap in snapshots:
            logging.info(f"Deleting snapshot {snap.id} of volume {vol_id}")
            try:
                conn.block_storage.delete_snapshot(snap.id, force=True)
            except Exception as e:
                logging.error(f"Snapshot {snap.id} delete failed: {e}")
            time.sleep(wait_sec)

        # Final delete
        vol = conn.block_storage.get_volume(vol_id)  # Refresh
        logging.info(f"Deleting volume {vol_id} (current status: {vol.status})")
        conn.block_storage.delete_volume(vol_id, force=True)
        return True

    except Exception as e:
        logging.error(f"Volume {vol_id} delete failed: {e}")
        return False


def main():
    args = parse_args()
    setup_logging(args.log_level)

    logging.info("Connecting to OpenStack...")
    try:
        conn = openstack.connect()
        conn.authorize()
        logging.info("Authentication successful")
    except Exception as e:
        logging.error(f"Connection failed: {e}")
        sys.exit(1)

    if args.reset_build:
        logging.info("Searching for VMs in BUILD status...")
        build_vms = list(conn.compute.servers(status="BUILD", all_projects=True))

        if not build_vms:
            logging.info("No BUILD VMs found.")
        else:
            logging.info(f"Found {len(build_vms)} BUILD VMs")
            reset_count = 0
            force_deleted = 0

            for vm in build_vms:
                logging.info(f"Processing VM {vm.id} ({vm.name or 'unnamed'})")
                if args.dry_run:
                    print(f"Would reset: {vm.id[:8]}... {vm.name or '<unnamed>':<30}")
                else:
                    if reset_server_state_with_fallback(conn, vm.id):
                        reset_count += 1
                    elif args.force_delete:
                        # For consistency, delete attached volumes before force deleting VM
                        attached = get_attached_volumes(conn, vm)
                        for vol_id in attached:
                            safe_delete_volume(conn, vol_id, vm.id, wait_sec=args.wait)
                            time.sleep(args.wait)
                        if force_delete_server_with_dependencies(conn, vm.id):
                            force_deleted += 1
                time.sleep(args.wait)

            print(f"\nBUILD → ERROR: {reset_count} VMs")
            if force_deleted:
                print(f"Force-deleted BUILD VMs: {force_deleted}")

    if args.force_delete:
        logging.info("Searching for VMs in ERROR status...")
        error_vms = list(conn.compute.servers(status="ERROR", all_projects=True))

        if not error_vms:
            logging.info("No ERROR VMs found.")
        else:
            logging.info(f"Found {len(error_vms)} ERROR VMs")

            if args.dry_run:
                print("\nDRY RUN — no changes will be made")
                for vm in error_vms:
                    print(f"Would delete VM: {vm.id[:8]}... {vm.name or '<unnamed>':<30}")
                    for vol_id in get_attached_volumes(conn, vm):
                        try:
                            vol = conn.block_storage.get_volume(vol_id)
                            print(f"  → Would reset to 'error' and delete volume: {vol_id[:8]}... {vol.name or '<unnamed>':<30} | {vol.status}")
                        except:
                            print(f"  → Would reset to 'error' and delete volume: {vol_id}")
                return

            print("\n" + "=" * 80)
            print("DELETING ERROR VMs AND THEIR VOLUMES (with reset to 'error' first)")
            print("=" * 80)

            deleted_vms = 0
            deleted_volumes = 0

            for vm in error_vms:
                attached = get_attached_volumes(conn, vm)
                for vol_id in attached:
                    if safe_delete_volume(conn, vol_id, vm.id, wait_sec=args.wait):
                        deleted_volumes += 1
                    time.sleep(args.wait)

                logging.info(f"Deleting VM {vm.id} ({vm.name or 'unnamed'})")
                if force_delete_server_with_dependencies(conn, vm.id):
                    deleted_vms += 1
                time.sleep(args.wait)

            print("\n" + "=" * 80)
            print("SUMMARY")
            print("=" * 80)
            print(f"  ERROR VMs processed : {len(error_vms)}")
            print(f"  Volumes deleted     : {deleted_volumes}")
            print(f"  VMs deleted         : {deleted_vms}")
            print("=" * 80)

    if not args.reset_build and not args.force_delete:
        logging.info("Listing all VMs...")
        all_vms = list(conn.compute.servers(all_projects=True))

        if not all_vms:
            logging.info("No VMs found.")
            return

        error_vms = [vm for vm in all_vms if vm.status == "ERROR"]
        other_vms = [vm for vm in all_vms if vm.status != "ERROR"]
        other_vms.sort(key=lambda v: (v.name or v.id).lower())

        print("\n" + "=" * 80)
        print("ALL VIRTUAL MACHINES AND ATTACHED VOLUMES (ERROR first)")
        print("=" * 80)

        for vm in error_vms + other_vms:
            print(f"VM: {vm.id[:8]}... {vm.name or '<unnamed>':<30} | Status: {vm.status:12}")
            attached = get_attached_volumes(conn, vm)
            if attached:
                print("  Attached volumes:")
                for vol_id in attached:
                    try:
                        vol = conn.block_storage.get_volume(vol_id)
                        if vol:
                            print(f"    {vol.id[:8]}... {vol.name or '<unnamed>':<30} | {vol.status:12} | {vol.size} GiB")
                    except:
                        print(f"    {vol_id[:8]}... (details unavailable)")
            else:
                print("  No attached volumes")
            print("-" * 80)


if __name__ == "__main__":
    main()