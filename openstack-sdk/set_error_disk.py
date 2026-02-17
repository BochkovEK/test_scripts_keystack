#!/usr/bin/env python3
"""
Reset stuck volumes to 'error' status and/or delete volumes in 'error'.
Uses openstack.connect() for authentication (environment variables or clouds.yaml).

Behavior priority:
- --volumes "id1 id2 id3" → reset ONLY these volumes to 'error' (ignores all --reset-* flags)
- --vm-name to reset all volumes with matching name prefix
- --force-delete → delete ALL volumes currently in 'error' status (always applies, even alone)
- If no --volumes → use --reset-creating / --reset-deleting / --reset-reserved / --reset-attaching
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
        help="Delete ALL volumes in 'error' status"
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
        help="Reset volumes in 'creating' to 'error'"
    )
    parser.add_argument(
        "--reset-deleting",
        action="store_true",
        help="Reset volumes in 'deleting' to 'error'"
    )
    parser.add_argument(
        "--reset-reserved",
        action="store_true",
        help="Reset volumes in 'reserved' to 'error'"
    )
    parser.add_argument(
        "--reset-attaching",
        action="store_true",
        help="Reset volumes in 'attaching' to 'error'"
    )
    parser.add_argument(
        "--volumes",
        type=str,
        help="Space-separated volume IDs to reset to 'error' (highest priority)"
    )
    parser.add_argument(
        "--vm-name",
        type=str,
        help="Reset all volumes whose name starts with this prefix"
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

    conn = openstack.connect()
    cinder = conn.block_storage

    reset_volumes = []

    # Priority 1: specific volume IDs
    if args.volumes:
        volume_ids = args.volumes.split()
        for vol_id in volume_ids:
            vol = cinder.get_volume(vol_id)
            if vol:
                reset_volumes.append(vol)

    # Priority 2: name prefix (--vm-name)
    elif args.vm_name:
        prefix = args.vm_name.strip()
        all_vols = cinder.volumes(all_projects=True)
        reset_volumes = [v for v in all_vols if v.name and v.name.startswith(prefix)]

    # Priority 3: status-based reset
    elif any([args.reset_creating, args.reset_deleting, args.reset_reserved, args.reset_attaching]):
        if args.reset_creating:
            reset_volumes.extend(cinder.volumes(status="creating", all_projects=True))
        if args.reset_deleting:
            reset_volumes.extend(cinder.volumes(status="deleting", all_projects=True))
        if args.reset_reserved:
            reset_volumes.extend(cinder.volumes(status="reserved", all_projects=True))
        if args.reset_attaching:
            reset_volumes.extend(cinder.volumes(status="attaching", all_projects=True))

    # Show and reset volumes
    if reset_volumes:
        print("\nVolumes to reset to 'error':")
        print("-" * 80)
        for vol in reset_volumes:
            print(f"  {vol.id[:8]}... {vol.name or '<no name>':<36} | {vol.status:12} | {vol.size:>4} GiB")
        print("-" * 80)

        if not args.dry_run:
            updated = 0
            for vol in reset_volumes:
                try:
                    cinder.reset_volume_status(vol.id, status='error')
                    updated += 1
                    time.sleep(args.wait)
                except Exception as e:
                    logging.error(f"Reset failed for {vol.id}: {e}")
            print(f"Reset to 'error': {updated} volumes")

    # Force delete all error volumes (independent action)
    if args.force_delete:
        error_volumes = list(cinder.volumes(status="error", all_projects=True))
        if error_volumes:
            print("\nVolumes to delete (status 'error'):")
            print("=" * 80)
            for v in error_volumes:
                print(f"{v.id[:8]}... {v.name or '<no name>':<36} | {v.status:12} | {v.size:>4} GiB")
            print("=" * 80)

            if not args.dry_run:
                deleted = 0
                for vol in error_volumes:
                    try:
                        cinder.delete_volume(vol.id, force=True)
                        deleted += 1
                        time.sleep(args.wait)
                    except Exception as e:
                        logging.error(f"Delete failed for {vol.id}: {e}")
                print(f"Deleted {deleted} volumes")

    # Default: list all volumes
    if not reset_volumes and not args.force_delete:
        all_volumes = list(cinder.volumes(all_projects=True))
        if all_volumes:
            print("\nAll volumes:")
            print("=" * 80)
            for v in all_volumes:
                print(f"{v.id[:8]}... {v.name or '<no name>':<36} | {v.status:12} | {v.size:>4} GiB")
            print("=" * 80)


if __name__ == "__main__":
    main()