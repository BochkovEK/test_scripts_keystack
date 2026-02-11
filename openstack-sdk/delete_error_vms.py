#!/usr/bin/env python3
"""
Force delete VMs in 'ERROR' status along with their attached volumes.
Uses openstack.connect() for authentication (environment variables or clouds.yaml).
Requires admin privileges for force delete actions.

Behavior:
- No flags → list all VMs with their attached volumes
- --force-delete → delete all volumes attached to ERROR VMs, then delete the ERROR VMs themselves
"""

import argparse
import sys
import time
import logging

import openstack


def parse_args():
    parser = argparse.ArgumentParser(
        description="Delete VMs in 'ERROR' status and their attached volumes"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Delete all volumes attached to ERROR VMs, then delete the ERROR VMs"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be deleted without executing changes"
    )
    parser.add_argument(
        "--wait",
        type=int,
        default=3,
        help="Seconds to wait between delete operations (default: 3)"
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
    for attachment in getattr(server, 'os-extended-volumes:volumes_attached', []):
        vol_id = attachment.get('id')
        if vol_id:
            volumes.append(vol_id)
    return volumes


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

    # Find all VMs in ERROR status
    logging.info("Searching for VMs in 'ERROR' status...")
    error_vms = list(conn.compute.servers(status="ERROR", all_projects=True))

    if not error_vms:
        logging.info("No VMs found in 'ERROR' status.")

    # If no --force-delete → just list all VMs and their volumes
    if not args.force_delete:
        logging.info("Listing all VMs with attached volumes...")

        all_vms = list(conn.compute.servers(all_projects=True))
        if not all_vms:
            logging.info("No VMs found at all.")
            return

        print("\n" + "=" * 80)
        print("ALL VIRTUAL MACHINES AND ATTACHED VOLUMES")
        print("=" * 80)

        for vm in all_vms:
            print(f"VM: {vm.id[:8]}... {vm.name or '<no name>':<30} | Status: {vm.status:12}")
            attached = get_attached_volumes(conn, vm)
            if attached:
                print("  Attached volumes:")
                for vol_id in attached:
                    vol = conn.block_storage.get_volume(vol_id)
                    if vol:
                        print(f"    {vol.id[:8]}... {vol.name or '<no name>':<30} | {vol.status:12} | {vol.size} GiB")
            else:
                print("  No attached volumes")
            print("-" * 80)

        return

    # If --force-delete is set → process ERROR VMs
    logging.info(f"Found {len(error_vms)} VMs in 'ERROR' status")

    if args.dry_run:
        print("\nDRY RUN MODE — no deletions will be performed")
        for vm in error_vms:
            print(f"Would delete VM: {vm.id[:8]}... {vm.name or '<no name>':<30}")
            attached = get_attached_volumes(conn, vm)
            for vol_id in attached:
                vol = conn.block_storage.get_volume(vol_id)
                if vol:
                    print(f"  → Would delete volume: {vol.id[:8]}... {vol.name or '<no name>':<30} | {vol.status}")
        return

    print("\n" + "=" * 80)
    print("STARTING DELETION OF ERROR VMs AND THEIR VOLUMES")
    print("=" * 80)

    deleted_vms = 0
    deleted_volumes = 0

    for vm in error_vms:
        try:
            # Step 1: Delete attached volumes
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

            # Step 2: Delete the VM itself
            logging.info(f"Deleting VM {vm.id} ({vm.name or 'no name'}) in ERROR status")
            conn.compute.delete_server(vm.id, force=True)
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


if __name__ == "__main__":
    main()
