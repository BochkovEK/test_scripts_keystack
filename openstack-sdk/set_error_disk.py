#!/usr/bin/env python3
"""
Reset stuck volumes to 'error' status and/or delete volumes in 'error'.
Uses openstack.connect() for authentication (environment variables or clouds.yaml).

Behavior priority:
- --volumes "id1 id2 id3" → reset ONLY these volumes to 'error' (ignores all --reset-* flags)
- --force-delete → delete ALL volumes currently in 'error' status (always applies, even alone)
- If no --volumes → use --reset-creating / --reset-deleting / --reset-reserved to select volumes
- No flags → list all volumes with their statuses
"""

import argparse
import sys
import time
import logging

import openstack


def parse_args():
    parser = argparse.ArgumentParser(
        description="Reset volumes to 'error' status and/or delete volumes in 'error'"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Delete ALL volumes currently in 'error' status (always applies)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without executing any changes"
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
    parser.add_argument(
        "--reset-creating",
        action="store_true",
        help="Reset volumes in 'creating' status to 'error' (ignored if --volumes is used)"
    )
    parser.add_argument(
        "--reset-deleting",
        action="store_true",
        help="Reset volumes in 'deleting' status to 'error' (ignored if --volumes is used)"
    )
    parser.add_argument(
        "--reset-reserved",
        action="store_true",
        help="Reset volumes in 'reserved' status to 'error' (ignored if --volumes is used)"
    )
    parser.add_argument(
        "--volumes",
        type=str,
        help="Space-separated list of volume IDs to force reset to 'error' (highest priority)"
    )
    return parser.parse_args()


def setup_logging(level_str: str):
    logging.basicConfig(
        level=getattr(logging, level_str.upper()),
        format="%(asctime)s | %(levelname)-7s | %(message)s",
        datefmt="%H:%M:%S"
    )


def main():
    args = parse_args()
    setup_logging(args.log_level)

    logging.info("Connecting to OpenStack...")

    try:
        conn = openstack.connect()
        conn.authorize()
        logging.info("Authentication successful")
        cinder = conn.block_storage
    except Exception as e:
        logging.error(f"Connection failed: {e}")
        sys.exit(1)

    reset_volumes = []

    # Priority 1: --volumes — highest priority, ignores all --reset-* flags
    if args.volumes:
        volume_ids = args.volumes.split()
        logging.info(f"Processing {len(volume_ids)} specific volumes from --volumes (highest priority)")

        for vol_id in volume_ids:
            try:
                vol = cinder.get_volume(vol_id)
                if vol:
                    reset_volumes.append(vol)
                else:
                    logging.warning(f"Volume {vol_id} not found")
            except Exception as e:
                logging.error(f"Failed to fetch volume {vol_id}: {e}")

        # Explicitly ignore reset flags
        if args.reset_creating or args.reset_deleting or args.reset_reserved:
            logging.info("All --reset-* flags are ignored when --volumes is used")

    # Priority 2: status-based reset (only if no --volumes)
    elif args.reset_creating or args.reset_deleting or args.reset_reserved:
        if args.reset_creating:
            logging.info("Collecting volumes in 'creating' status...")
            reset_volumes.extend(cinder.volumes(status="creating", all_projects=True))

        if args.reset_deleting:
            logging.info("Collecting volumes in 'deleting' status...")
            reset_volumes.extend(cinder.volumes(status="deleting", all_projects=True))

        if args.reset_reserved:
            logging.info("Collecting volumes in 'reserved' status...")
            reset_volumes.extend(cinder.volumes(status="reserved", all_projects=True))

    # Show volumes to be reset (if any)
    if reset_volumes:
        logging.info(f"Found {len(reset_volumes)} volumes to reset to 'error'")
        for vol in reset_volumes:
            print(f"  {vol.id[:8]}... {vol.name or '<no name>':<30} | {vol.status:12} | {vol.size} GiB")

        if args.dry_run:
            logging.info("Dry run — no reset performed")
        else:
            updated = 0
            for vol in reset_volumes:
                try:
                    logging.info(f"Resetting volume {vol.id} to 'error'")
                    cinder.reset_volume_status(vol.id, status='error')
                    updated += 1
                    time.sleep(args.wait)

                    refreshed = cinder.get_volume(vol.id)
                    if refreshed.status == "error":
                        logging.info("  → success")
                    else:
                        logging.warning(f"  → status remains: {refreshed.status}")
                except Exception as e:
                    logging.error(f"Reset failed for {vol.id}: {e}")
            print(f"\nReset to 'error': {updated} volumes")

    # Handle --force-delete (independent, always deletes current 'error' volumes)
    if args.force_delete:
        logging.info("Collecting volumes in 'error' for deletion...")
        error_volumes = list(cinder.volumes(status="error", all_projects=True))

        if not error_volumes:
            logging.info("No volumes in 'error' status found for deletion.")
        else:
            print("\n" + "=" * 70)
            print("VOLUMES TO BE DELETED (status 'error')")
            print("=" * 70)
            for v in error_volumes:
                print(f"{v.id[:8]}... {v.name or '<no name>':<30} | {v.status:12} | {v.size} GiB")
            print("=" * 70)

            if args.dry_run:
                logging.info("Dry run — no deletions performed")
            else:
                deleted = 0
                for vol in error_volumes:
                    try:
                        logging.info(f"Deleting volume {vol.id} ({vol.name or 'no name'})")
                        cinder.delete_volume(vol.id, force=True)
                        deleted += 1
                        time.sleep(args.wait)
                    except Exception as e:
                        logging.error(f"Delete failed for {vol.id}: {e}")
                print(f"\nDeleted {deleted} volumes in 'error' status")

    # Default: no actions → list all volumes
    if not reset_volumes and not args.force_delete:
        logging.info("No actions requested. Listing all volumes...")
        all_volumes = list(cinder.volumes(all_projects=True))
        if not all_volumes:
            logging.info("No volumes found.")
            return

        print("\n" + "=" * 70)
        print("ALL VOLUMES")
        print("=" * 70)
        for v in all_volumes:
            print(f"{v.id[:8]}... {v.name or '<no name>':<30} | {v.status:12} | {v.size} GiB")
        print("=" * 70)


if __name__ == "__main__":
    main()