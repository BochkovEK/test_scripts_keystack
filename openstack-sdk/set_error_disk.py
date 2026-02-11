#!/usr/bin/env python3
"""
Reset stuck 'creating' and/or 'deleting' volumes to 'error' status
and/or delete all volumes in 'error' status.
Uses openstack.connect() for authentication (environment variables or clouds.yaml).

Behavior:
- No reset flags → list all volumes with their statuses
- --reset-creating / --reset-deleting → reset matching volumes to 'error'
- --force-delete → delete ALL volumes currently in 'error' status
"""

import argparse
import sys
import time
import logging

import openstack


def parse_args():
    parser = argparse.ArgumentParser(
        description="Reset stuck volumes to 'error' and/or delete volumes in 'error' status"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Delete ALL volumes currently in 'error' status"
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
    parser.add_argument(
        "--reset-creating",
        action="store_true",
        help="Reset volumes in 'creating' status to 'error'"
    )
    parser.add_argument(
        "--reset-deleting",
        action="store_true",
        help="Reset volumes in 'deleting' status to 'error'"
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

    # 1. Handle --force-delete: delete all volumes in 'error'
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

    # 2. Handle reset flags (if any)
    reset_volumes = []

    if args.reset_creating:
        logging.info("Collecting volumes in 'creating' status...")
        reset_volumes.extend(cinder.volumes(status="creating", all_projects=True))

    if args.reset_deleting:
        logging.info("Collecting volumes in 'deleting' status...")
        reset_volumes.extend(cinder.volumes(status="deleting", all_projects=True))

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

    # 3. If no actions were requested — list all volumes
    if not args.force_delete and not reset_volumes:
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
