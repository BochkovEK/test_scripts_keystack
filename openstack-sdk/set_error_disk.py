#!/usr/bin/env python3
"""
Force reset 'creating' and/or 'deleting' volumes to 'error' status and optionally delete them.
Uses openstack.connect() for authentication (environment variables or clouds.yaml).
Requires admin privileges for reset_volume_status action.
"""

import argparse
import sys
import time
import logging

import openstack


def parse_args():
    parser = argparse.ArgumentParser(
        description="Force reset 'creating' and/or 'deleting' volumes to 'error' and optionally delete them"
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
        default=True,
        help="Process volumes in 'creating' status (default: True)"
    )
    parser.add_argument(
        "--reset-deleting",
        action="store_true",
        default=True,
        help="Process volumes in 'deleting' status (default: True)"
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

    logging.info("Connecting to OpenStack (using OS_* env vars or clouds.yaml)")

    try:
        conn = openstack.connect()
        conn.authorize()
        logging.info("Authentication successful")

        cinder = conn.block_storage
    except Exception as e:
        logging.error(f"Failed to connect or authorize: {e}")
        sys.exit(1)

    volumes = []

    if args.reset_creating:
        logging.info("Searching for volumes in 'creating' status...")
        creating_vols = list(cinder.volumes(status="creating", all_projects=True))
        volumes.extend(creating_vols)
        logging.info(f"Found {len(creating_vols)} volumes in 'creating'")

    if args.reset_deleting:
        logging.info("Searching for volumes in 'deleting' status...")
        deleting_vols = list(cinder.volumes(status="deleting", all_projects=True))
        volumes.extend(deleting_vols)
        logging.info(f"Found {len(deleting_vols)} volumes in 'deleting'")

    if not volumes:
        logging.info("No volumes to process. Exiting.")
        return

    # Remove duplicates if any (unlikely but safe)
    volumes = list({vol.id: vol for vol in volumes}.values())

    logging.info(f"Total volumes to process: {len(volumes)}")

    for vol in volumes:
        print(f"  {vol.id[:8]}... {vol.name or '<no name>'}  ({vol.size} GiB)  {vol.status}")

    if args.dry_run:
        logging.info("Dry run mode — no changes will be made")
        return

    print("\n" + "-" * 60)
    print("STARTING VOLUME STATUS RESET...")
    print("-" * 60)

    updated = 0
    deleted = 0

    for vol in volumes:
        try:
            logging.info(f"Resetting state to 'error' for volume {vol.id} ({vol.name or 'no name'}) "
                         f"current status: {vol.status}")

            cinder.reset_volume_status(vol.id, status='error')
            updated += 1

            time.sleep(args.wait)

            vol_refreshed = cinder.get_volume(vol.id)
            if vol_refreshed.status == "error":
                logging.info("  → success: status = error")
            else:
                logging.warning(f"  → status not changed: {vol_refreshed.status}")

            if args.force_delete:
                logging.info(f"  Deleting volume {vol.id}")
                cinder.delete_volume(vol.id, force=True)
                deleted += 1
                time.sleep(2)

        except Exception as e:
            logging.error(f"Error processing volume {vol.id}: {e}")

    print("\n" + "=" * 60)
    print("RESULT")
    print("=" * 60)
    print(f"  Total volumes processed         : {len(volumes)}")
    print(f"  Reset to 'error'                : {updated}")
    if args.force_delete:
        print(f"  Deleted                         : {deleted}")
    print("=" * 60)

    if updated == 0:
        logging.warning("No volumes were reset to error")


if __name__ == "__main__":
    main()