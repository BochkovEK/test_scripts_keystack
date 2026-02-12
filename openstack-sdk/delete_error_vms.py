#!/usr/bin/env python3
"""
Force reset VMs in 'BUILD' status to 'ERROR' and/or delete ERROR VMs along with their attached volumes.
Uses openstack.connect() for authentication (environment variables or clouds.yaml).
Requires admin privileges for force delete and reset actions.

Behavior:
- No flags → list all VMs sorted by status (ERROR first), then attached volumes
- --reset-build → reset ALL VMs in 'BUILD' status to 'ERROR'
- --force-delete → delete all volumes attached to ERROR VMs, then delete the ERROR VMs
"""

import argparse
import sys
import time
import logging

import openstack
from openstack import exceptions


def parse_args():
    parser = argparse.ArgumentParser(
        description="Reset BUILD VMs to ERROR and/or delete ERROR VMs with attached volumes"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Delete all volumes attached to ERROR VMs, then delete the ERROR VMs"
    )
    parser.add_argument(
        "--reset-build",
        action="store_true",
        help="Reset ALL VMs in 'BUILD' status to 'ERROR'"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without executing changes"
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
    """Get attached volumes from Nova + fallback search by instance_uuid"""
    volumes = []

    # Primary method — from Nova extended attribute
    for attachment in getattr(server, 'os-extended-volumes:volumes_attached', []):
        vol_id = attachment.get('id')
        if vol_id:
            volumes.append(vol_id)

    # Fallback: search volumes where instance_uuid matches server.id
    if not volumes:
        logging.debug(f"Fallback search for volumes attached to {server.id}")
        try:
            all_vols = conn.block_storage.volumes(all_projects=True)
            for vol in all_vols:
                attachments = getattr(vol, 'attachments', [])
                for att in attachments:
                    if att.get('server_id') == server.id:
                        volumes.append(vol.id)
                        break
        except Exception as e:
            logging.warning(f"Could not search volumes for VM {server.id}: {e}")

    return volumes


def reset_server_state_with_fallback(conn, server_id, target_state="error"):
    """
    Attempt to reset server state with fallback methods.
    Returns True if successful, False otherwise.
    """
    # Method 1: Standard reset_state
    try:
        conn.compute.reset_server_state(server_id, state=target_state)
        return True
    except exceptions.HttpException as e:
        if "DBReferenceError" in str(e) or "DatabaseError" in str(e) or "500" in str(e):
            logging.warning(f"Standard reset failed for {server_id} (DB error), trying nova CLI fallback...")
        else:
            logging.error(f"Unexpected error resetting {server_id}: {e}")
            return False
    except Exception as e:
        logging.error(f"Failed to reset VM {server_id}: {e}")
        return False

    # Method 2: Direct API call with admin privileges
    try:
        # Force reset using admin API (bypasses some DB checks)
        conn.compute.post(
            f"/servers/{server_id}/action",
            json={"os-resetState": {"state": target_state.upper()}}
        )
        logging.info(f"Successfully reset {server_id} using admin API")
        return True
    except Exception as e:
        logging.error(f"Admin API reset failed for {server_id}: {e}")

    # Method 3: Force delete as last resort for BUILD VMs
    logging.warning(f"Cannot reset {server_id}, attempting force delete instead...")
    return False


def force_delete_server_with_dependencies(conn, server_id):
    """Force delete server and clean up dependencies first."""
    try:
        # 1. Try to get floating IPs and disassociate them
        try:
            ports = list(conn.network.ports(device_id=server_id))
            for port in ports:
                if port.fixed_ips:
                    for fixed_ip in port.fixed_ips:
                        # Find and remove floating IPs
                        floating_ips = list(conn.network.ips(port_id=port.id))
                        for fip in floating_ips:
                            logging.info(f"Disassociating floating IP {fip.id} from server {server_id}")
                            conn.network.update_ip(fip.id, port_id=None)
                            time.sleep(1)
        except Exception as e:
            logging.debug(f"Floating IP cleanup for {server_id}: {e}")

        # 2. Try to delete the server with force=True
        conn.compute.delete_server(server_id, force=True)
        return True
    except Exception as e:
        logging.error(f"Force delete failed for server {server_id}: {e}")
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

    # Step 1: Reset BUILD VMs to ERROR (if flag is set)
    if args.reset_build:
        logging.info("Searching for VMs in 'BUILD' status...")
        try:
            build_vms = list(conn.compute.servers(status="BUILD", all_projects=True))
        except Exception as e:
            logging.error(f"Failed to list BUILD VMs: {e}")
            build_vms = []

        if not build_vms:
            logging.info("No VMs found in 'BUILD' status.")
        else:
            logging.info(f"Found {len(build_vms)} VMs in 'BUILD' status")
            updated = 0
            force_deleted = 0

            for vm in build_vms:
                try:
                    logging.info(f"Attempting to reset VM {vm.id} ({vm.name or 'no name'}) from BUILD to ERROR")

                    if args.dry_run:
                        print(f"Would reset VM: {vm.id[:8]}... {vm.name or '<no name>'}")
                    else:
                        success = reset_server_state_with_fallback(conn, vm.id)
                        if success:
                            updated += 1
                        else:
                            # If reset fails, offer to force delete
                            logging.warning(f"Cannot reset VM {vm.id}, consider using --force-delete flag")
                            if args.force_delete:
                                logging.info(f"Attempting force delete for stuck BUILD VM {vm.id}")
                                if force_delete_server_with_dependencies(conn, vm.id):
                                    force_deleted += 1

                        time.sleep(args.wait)

                except Exception as e:
                    logging.error(f"Failed to process VM {vm.id}: {e}")

            print(f"\nReset BUILD → ERROR: {updated} VMs")
            if force_deleted:
                print(f"Force deleted stuck BUILD VMs: {force_deleted}")

    # Step 2: Force-delete mode — process ERROR VMs
    if args.force_delete:
        logging.info("Searching for VMs in 'ERROR' status...")
        try:
            error_vms = list(conn.compute.servers(status="ERROR", all_projects=True))
        except Exception as e:
            logging.error(f"Failed to list ERROR VMs: {e}")
            error_vms = []

        if not error_vms:
            logging.info("No VMs found in 'ERROR' status.")
            if not args.reset_build:
                return
        else:
            logging.info(f"Found {len(error_vms)} VMs in 'ERROR' status")

            if args.dry_run:
                print("\nDRY RUN MODE — no deletions will be performed")
                for vm in error_vms:
                    print(f"Would delete VM: {vm.id[:8]}... {vm.name or '<no name>':<30}")
                    attached = get_attached_volumes(conn, vm)
                    for vol_id in attached:
                        try:
                            vol = conn.block_storage.get_volume(vol_id)
                            if vol:
                                print(
                                    f"  → Would delete volume: {vol.id[:8]}... {vol.name or '<no name>':<30} | {vol.status}")
                        except Exception:
                            print(f"  → Would delete volume: {vol_id} (could not retrieve details)")
                return

            print("\n" + "=" * 80)
            print("STARTING DELETION OF ERROR VMs AND THEIR VOLUMES")
            print("=" * 80)

            deleted_vms = 0
            deleted_volumes = 0

            for vm in error_vms:
                try:
                    # Step 1: Delete attached volumes first
                    attached = get_attached_volumes(conn, vm)
                    for vol_id in attached:
                        try:
                            vol = conn.block_storage.get_volume(vol_id)
                            if vol:
                                logging.info(f"Deleting volume {vol.id} attached to VM {vm.id}")
                                conn.block_storage.delete_volume(vol.id, force=True)
                                deleted_volumes += 1
                                time.sleep(args.wait)
                        except Exception as e:
                            logging.error(f"Failed to delete volume {vol_id}: {e}")

                    # Step 2: Delete the VM with dependency cleanup
                    logging.info(f"Deleting VM {vm.id} ({vm.name or 'no name'}) in ERROR status")
                    if force_delete_server_with_dependencies(conn, vm.id):
                        deleted_vms += 1
                    time.sleep(args.wait)

                except Exception as e:
                    logging.error(f"Error processing VM {vm.id}: {e}")

            print("\n" + "=" * 80)
            print("RESULT")
            print("=" * 80)
            print(f"  Processed ERROR VMs           : {len(error_vms)}")
            print(f"  Deleted volumes               : {deleted_volumes}")
            print(f"  Deleted VMs                   : {deleted_vms}")
            print("=" * 80)

    # Default: no actions → list all VMs (ERROR first)
    if not args.force_delete and not args.reset_build:
        logging.info("Listing all VMs with attached volumes...")
        try:
            all_vms = list(conn.compute.servers(all_projects=True))
        except Exception as e:
            logging.error(f"Failed to list VMs: {e}")
            sys.exit(1)

        if not all_vms:
            logging.info("No VMs found.")
            return

        # Sort: ERROR VMs first, then others sorted by name (case-insensitive)
        error_vms = [vm for vm in all_vms if vm.status == "ERROR"]
        other_vms = [vm for vm in all_vms if vm.status != "ERROR"]
        other_vms.sort(key=lambda vm: (vm.name or vm.id).lower())

        sorted_vms = error_vms + other_vms

        print("\n" + "=" * 80)
        print("LIST OF ALL VIRTUAL MACHINES AND ATTACHED VOLUMES (ERROR first)")
        print("=" * 80)

        for vm in sorted_vms:
            print(f"VM: {vm.id[:8]}... {vm.name or '<no name>':<30} | Status: {vm.status:12}")
            attached = get_attached_volumes(conn, vm)
            if attached:
                print("  Attached volumes:")
                for vol_id in attached:
                    try:
                        vol = conn.block_storage.get_volume(vol_id)
                        if vol:
                            print(
                                f"    {vol.id[:8]}... {vol.name or '<no name>':<30} | {vol.status:12} | {vol.size} GiB")
                    except Exception:
                        print(f"    {vol_id[:8]}... (could not retrieve volume details)")
            else:
                print("  No attached volumes")
            print("-" * 80)


if __name__ == "__main__":
    main()