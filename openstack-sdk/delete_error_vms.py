#!/usr/bin/env python3
"""
Force delete VMs (by default in ERROR status) along with their attached volumes.
For each targeted VM:
  1. Collect attached volumes
  2. Reset all attached volumes to 'error' status
  3. Force delete all those volumes
  4. Force delete the VM itself

Uses openstack.connect() for authentication (environment variables or clouds.yaml).
Requires admin privileges.
"""

import argparse
import sys
import time
import logging

import openstack
from openstack import exceptions


def parse_args():
    parser = argparse.ArgumentParser(
        description="Force-delete VMs after resetting and deleting their attached volumes (no detach)"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Reset attached volumes to 'error' → delete volumes → delete targeted VMs"
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

    status_group = parser.add_mutually_exclusive_group()
    status_group.add_argument(
        "--status", "-s",
        default="ERROR",
        help="Only target VMs with this status (default: ERROR). Ignored if --all-statuses is set."
    )
    status_group.add_argument(
        "--all-statuses", "-as",
        action="store_true",
        help="Target VMs regardless of status (DANGEROUS: includes ACTIVE, BUILD, etc). "
             "Requires interactive confirmation unless --yes is also passed."
    )

    parser.add_argument(
        "--yes", "-y",
        action="store_true",
        help="Skip the interactive confirmation prompt required by --all-statuses"
    )

    return parser.parse_args()


def setup_logging(level_str: str):
    logging.basicConfig(
        level=getattr(logging, level_str.upper()),
        format="%(asctime)s | %(levelname)-7s | %(message)s",
        datefmt="%H:%M:%S"
    )


def get_attached_volumes(conn, server):
    """Get list of volume IDs currently attached to the server"""
    volumes = []

    # Primary method: os-extended-volumes:volumes_attached
    for attachment in getattr(server, 'os-extended-volumes:volumes_attached', []):
        vol_id = attachment.get('id')
        if vol_id:
            volumes.append(vol_id)

    # Fallback: check volume attachments
    if not volumes:
        logging.debug(f"Fallback lookup for volumes attached to {server.id}")
        try:
            all_vols = conn.block_storage.volumes(all_projects=True)
            for vol in all_vols:
                for att in getattr(vol, 'attachments', []):
                    if att.get('server_id') == server.id:
                        volumes.append(vol.id)
                        break
        except Exception as e:
            logging.warning(f"Volume fallback search failed for {server.id}: {e}")

    return list(set(volumes))  # remove possible duplicates


def reset_volume_to_error(conn, vol_id):
    """Reset volume status to 'error'"""
    try:
        conn.block_storage.reset_volume_status(vol_id, status='error')
        logging.info(f"Reset volume {vol_id} to 'error'")
        return True
    except Exception as e:
        logging.error(f"Failed to reset volume {vol_id} to 'error': {e}")
        return False


def force_delete_volume(conn, vol_id):
    """Delete volume (ignores current state)"""
    try:
        conn.block_storage.delete_volume(vol_id)
        logging.info(f"Delete issued for volume {vol_id}")
        return True
    except Exception as e:
        logging.error(f"Delete volume {vol_id} failed: {e}")
        return False


def force_delete_server_with_dependencies(conn, server_id):
    """Clean floating IPs (if any) → force delete server"""
    try:
        # Optional: clean floating IPs
        ports = list(conn.network.ports(device_id=server_id))
        for port in ports:
            floating_ips = list(conn.network.ips(port_id=port.id))
            for fip in floating_ips:
                logging.info(f"Disassociating floating IP {fip.id}")
                conn.network.update_ip(fip.id, port_id=None)
                time.sleep(1)

        conn.compute.delete_server(server_id, force=True)
        logging.info(f"Force delete issued for server {server_id}")
        return True
    except Exception as e:
        logging.error(f"Force delete server {server_id} failed: {e}")
        return False


def confirm_all_statuses():
    """Interactive safety confirmation before touching VMs of any status"""
    print("\n" + "!" * 80)
    print("WARNING: --all-statuses selected.")
    print("This will target VMs in ANY status, including ACTIVE, BUILD, SHUTOFF, etc.")
    print("Attached volumes will be reset to 'error' and force-deleted, then the VM")
    print("itself will be force-deleted. This is IRREVERSIBLE.")
    print("!" * 80)
    answer = input("\nType 'yes' to continue: ").strip().lower()
    return answer == "yes"


def main():
    args = parse_args()
    setup_logging(args.log_level)

    target_status = None if args.all_statuses else args.status.upper()

    logging.info("Connecting to OpenStack...")
    try:
        conn = openstack.connect()
        conn.authorize()
        logging.info("Authentication successful")
    except Exception as e:
        logging.error(f"Connection failed: {e}")
        sys.exit(1)

    if not args.force_delete:
        logging.info("No --force-delete flag provided → showing usage info only")
        print("\nRun with --force-delete flag to perform cleanup\n")
        return

    if args.all_statuses and not args.yes:
        if not confirm_all_statuses():
            logging.info("Aborted by user.")
            return

    if target_status:
        logging.info(f"Searching for VMs in '{target_status}' status...")
        target_vms = list(conn.compute.servers(status=target_status, all_projects=True))
    else:
        logging.info("Searching for VMs in ANY status...")
        target_vms = list(conn.compute.servers(all_projects=True))

    if not target_vms:
        if target_status:
            logging.info(f"No VMs found in '{target_status}' status.")
        else:
            logging.info("No VMs found.")
        return

    logging.info(f"Found {len(target_vms)} target VMs")

    if args.dry_run:
        print("\nDRY RUN — no changes will be made")
        for vm in target_vms:
            print(f"VM: {vm.id[:8]}... {vm.name or '<unnamed>':<30} | status={vm.status}")
            vols = get_attached_volumes(conn, vm)
            if vols:
                print("  Volumes to reset to 'error' → delete:")
                for v in vols:
                    try:
                        vol = conn.block_storage.get_volume(v)
                        print(f"    {v[:8]}... {vol.name or '<no name>':<30} | {vol.status}")
                    except:
                        print(f"    {v[:8]}...")
            else:
                print("  No attached volumes")
        return

    print("\n" + "=" * 80)
    if target_status:
        print(f"CLEANUP: '{target_status}' VMs → reset volumes to error → delete volumes → delete VMs")
    else:
        print("CLEANUP: ALL VMs (any status) → reset volumes to error → delete volumes → delete VMs")
    print("=" * 80)

    deleted_vms = 0
    deleted_volumes = 0
    reset_volumes_count = 0

    for vm in target_vms:
        print(f"\nProcessing VM: {vm.id}  {vm.name or '<unnamed>'}  (status={vm.status})")

        attached = get_attached_volumes(conn, vm)

        # 1. Reset all volumes to error
        for vol_id in attached:
            if reset_volume_to_error(conn, vol_id):
                reset_volumes_count += 1
            time.sleep(args.wait)

        # 2. Delete volumes
        for vol_id in attached:
            if force_delete_volume(conn, vol_id):
                deleted_volumes += 1
            time.sleep(args.wait)

        # 3. Delete VM
        if force_delete_server_with_dependencies(conn, vm.id):
            deleted_vms += 1

        time.sleep(args.wait)

    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"  Processed VMs              : {len(target_vms)}")
    print(f"  Volumes reset to 'error'   : {reset_volumes_count}")
    print(f"  Volumes deleted            : {deleted_volumes}")
    print(f"  VMs deleted                : {deleted_vms}")
    print("=" * 80)


if __name__ == "__main__":
    main()