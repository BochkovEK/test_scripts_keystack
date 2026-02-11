#!/usr/bin/env python3
"""
Force reset 'creating' and/or 'deleting' volumes to 'error' status and optionally delete them.
Uses openstack.connect() for authentication.

Behavior:
- No flags → list all volumes with statuses (dry-run like)
- --reset-creating / --reset-deleting → reset matching volumes to error
- --force-delete → delete volumes after reset
"""

import argparse
import sys
import time
import logging

import openstack


def parse_args():
    parser = argparse.ArgumentParser(
        description="Reset stuck 'creating' and/or 'deleting' volumes to 'error' and optionally delete"
    )
    parser.add_argument(
        "--force-delete",
        action="store_true",
        help="Delete volumes after setting error status"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show actions without executing them"
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
        help="Process volumes in 'creating' status"
    )
    parser.add_argument(
        "--reset-deleting",
        action="store_true",
        help="Process volumes in 'deleting' status"
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

    # Собираем тома для обработки
    target_volumes = []

    if args.reset_creating:
        logging.info("Collecting volumes in 'creating'...")
        target_volumes.extend(cinder.volumes(status="creating", all_projects=True))

    if args.reset_deleting:
        logging.info("Collecting volumes in 'deleting'...")
        target_volumes.extend(cinder.volumes(status="deleting", all_projects=True))

    # Если ничего не выбрано — показываем все тома
    if not target_volumes:
        logging.info("No specific reset flags. Listing all volumes...")
        all_volumes = list(cinder.volumes(all_projects=True))
        if not all_volumes:
            logging.info("No volumes found at all.")
            return

        print("\n" + "=" * 70)
        print("ALL VOLUMES (no reset flags provided)")
        print("=" * 70)
        for v in all_volumes:
            print(f"{v.id[:8]}... {v.name or '<no name>':<30} | {v.status:12} | {v.size} GiB")
        print("=" * 70)
        return

    # Есть флаги — работаем с выбранными
    logging.info(f"Found {len(target_volumes)} volumes to process")

    for vol in target_volumes:
        print(f"  {vol.id[:8]}... {vol.name or '<no name>':<30} | {vol.status:12} | {vol.size} GiB")

    if args.dry_run:
        logging.info("Dry run — no changes will be applied")
        return

    print("\n" + "-" * 70)
    print("STARTING RESET TO ERROR...")
    print("-" * 70)

    updated = 0
    deleted = 0

    for vol in target_volumes:
        try:
            logging.info(f"Resetting {vol.id} ({vol.name or 'no name'}) from {vol.status} → error")

            cinder.reset_volume_status(vol.id, status='error')
            updated += 1

            time.sleep(args.wait)

            refreshed = cinder.get_volume(vol.id)
            if refreshed.status == "error":
                logging.info("  → success")
            else:
                logging.warning(f"  → status remains: {refreshed.status}")

            if args.force_delete:
                logging.info(f"  Deleting {vol.id}")
                cinder.delete_volume(vol.id, force=True)
                deleted += 1
                time.sleep(2)

        except Exception as e:
            logging.error(f"Error with {vol.id}: {e}")

    print("\n" + "=" * 70)
    print("RESULT")
    print("=" * 70)
    print(f"  Processed volumes     : {len(target_volumes)}")
    print(f"  Set to error          : {updated}")
    if args.force_delete:
        print(f"  Deleted               : {deleted}")
    print("=" * 70)

    if updated == 0:
        logging.warning("No volumes were reset")


if __name__ == "__main__":
    main()