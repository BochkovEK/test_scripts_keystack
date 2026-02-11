#!/usr/bin/env python3
"""
Force reset VMs in 'BUILDING' status to 'ERROR' and/or delete ERROR VMs along with their attached volumes.
Uses openstack.connect() for authentication (environment variables or clouds.yaml).
Requires admin privileges for force delete and reset actions.

Behavior:
- No flags → list all VMs sorted by status (ERROR first), then attached volumes
- --reset-building → reset ALL VMs in 'BUILDING' status to 'ERROR'
- --force-delete → delete all volumes attached to ERROR VMs, then delete the ERROR VMs
"""

import argparse
import sys
import time
import logging

import openstack


def parse_args():
    parser = argparse.ArgumentParser(
        description="Reset BUILDING VMs to ERROR and/or delete ERROR VMs with attached volumes"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Delete all volumes attached to ERROR VMs, then delete the ERROR VMs"
    )
    parser.add_argument(
        "--reset-building",
        action="store_true",
        help="Reset ALL VMs in 'BUILDING' status to 'ERROR'"
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
        all_vols = conn.block_storage.volumes(all_projects=True)
        for vol in all_vols:
            attachments = getattr(vol, 'attachments', [])
            for att in attachments:
                if att.get('server_id') == server.id:
                    volumes.append(vol.id)
                    break

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

    # Step 1: Reset BUILDING VMs to ERROR (if flag is set)
    if args.reset_building:
        logging.info("Searching for VMs in 'BUILDING' status...")
        building_vms = list(conn.compute.servers(status="BUILDING", all_projects=True))

        if not building_vms:
            logging.info("No VMs found in 'BUILDING' status.")
        else:
            logging.info(f"Found {len(building_vms)} VMs in 'BUILDING' status")
            updated = 0

            for vm in building_vms:
                try:
                    logging.info(f"Resetting VM {vm.id} ({vm.name or 'no name'}) from BUILDING to ERROR")
                    conn.compute.reset_server_state(vm.id, state="error")
                    updated += 1
                    time.sleep(args.wait)
                except Exception as e:
                    logging.error(f"Failed to reset VM {vm.id}: {e}")

            print(f"\nReset BUILDING → ERROR: {updated} VMs")

    # Step 2: Force-delete mode — only process ERROR VMs
    if args.force_delete:
        logging.info("Searching for VMs in 'ERROR' status...")
        error_vms = list(conn.compute.servers(status="ERROR", all_projects=True))

        if not error_vms:
            logging.info("No VMs found in 'ERROR' status.")
            return

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

                # Step 2: Delete the VM
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

    # Default: no actions → list all VMs (ERROR first)
    if not args.force_delete and not args.reset_building:
        logging.info("Listing all VMs with attached volumes...")
        all_vms = list(conn.compute.servers(all_projects=True))

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
                    vol = conn.block_storage.get_volume(vol_id)
                    if vol:
                        print(f"    {vol.id[:8]}... {vol.name or '<no name>':<30} | {vol.status:12} | {vol.size} GiB")
            else:
                print("  No attached volumes")
            print("-" * 80)


if __name__ == "__main__":
    main()