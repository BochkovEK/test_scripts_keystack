#!/usr/bin/env python3
"""
Force set 'creating' volumes to 'error' status and optionally delete them.
Requires admin privileges.
"""

import argparse
import sys
import time
import logging
from openstack import connection


def parse_args():
    parser = argparse.ArgumentParser(
        description="Force set all 'creating' volumes to 'error' and optionally delete them"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Delete volumes after setting error status"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes"
    )
    parser.add_argument(
        "--wait",
        type=int,
        default=1,
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


def main():
    args = parse_args()
    setup_logging(args.log_level)

    logging.info("Connecting to OpenStack (using OS_* environment variables)")

    try:
        conn = connection.Connection()
        cinder = conn.block_storage
    except Exception as e:
        logging.error(f"Failed to connect to OpenStack: {e}")
        sys.exit(1)

    logging.info("Searching for volumes in 'creating' status...")
    volumes = list(cinder.volumes(status="creating", all_projects=True))

    if not volumes:
        logging.info("No volumes in 'creating' status found. Exiting.")
        return

    logging.info(f"Found {len(volumes)} volumes in 'creating' status")

    for vol in volumes:
        print(f"  {vol.id[:8]}... {vol.name or '<no name>'}  ({vol.size} GiB)  {vol.status}")

    if args.dry_run:
        logging.info("Dry run mode — no changes will be made")
        return

    print("\n" + "-" * 60)
    print("STARTING VOLUME STATUS CHANGE...")
    print("-" * 60)

    updated = 0
    deleted = 0

    for vol in volumes:
        try:
            logging.info(f"Setting status 'error' for volume {vol.id} ({vol.name or 'no name'})")
            cinder.update_volume(vol.id, status="error")
            updated += 1

            time.sleep(args.wait)

            # Verify status
            vol = cinder.get_volume(vol.id)
            if vol.status == "error":
                logging.info("  → success: status = error")
            else:
                logging.warning(f"  → status not changed: {vol.status}")

            if args.force_delete:
                logging.info(f"  Deleting volume {vol.id}")
                cinder.delete_volume(vol.id)
                deleted += 1
                time.sleep(2)

        except Exception as e:
            logging.error(f"Error processing volume {vol.id}: {e}")

    print("\n" + "=" * 60)
    print("RESULT")
    print("=" * 60)
    print(f"  Found volumes in 'creating'     : {len(volumes)}")
    print(f"  Set to 'error'                  : {updated}")
    if args.force_delete:
        print(f"  Deleted                         : {deleted}")
    print("=" * 60)

    if updated == 0:
        logging.warning("No volumes were set to error")


if __name__ == "__main__":
    main()