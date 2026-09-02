#!/usr/bin/env python3
"""
Force delete VMs (by default in ERROR status, across all projects/domains)
along with their attached volumes.

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
        "--project", "-p",
        action="append",
        default=None,
        metavar="NAME_OR_ID",
        help="Only target VMs belonging to this project (name or ID). Repeatable "
             "(-p projA -p projB). Default: all projects."
    )
    parser.add_argument(
        "--domain", "-d",
        action="append",
        default=None,
        metavar="NAME_OR_ID",
        help="Only target VMs whose project belongs to this domain (name or ID). "
             "Repeatable (-d domainA -d domainB). Default: all domains. "
             "Combines with --project as a union of matching projects."
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


def resolve_project_filter(conn, args):
    """
    Resolve --project / --domain arguments into a set of project IDs to
    filter on. Returns None if no filtering requested (i.e. all projects
    across all domains, which is the default).
    """
    if not args.project and not args.domain:
        return None

    project_ids = set()

    if args.project:
        for p in args.project:
            try:
                proj = conn.identity.find_project(p, ignore_missing=False)
                project_ids.add(proj.id)
                logging.debug(f"Resolved project '{p}' -> {proj.id}")
            except Exception as e:
                logging.error(f"Could not resolve project '{p}': {e}")
                sys.exit(1)

    if args.domain:
        for d in args.domain:
            try:
                dom = conn.identity.find_domain(d, ignore_missing=False)
                logging.debug(f"Resolved domain '{d}' -> {dom.id}")
            except Exception as e:
                logging.error(f"Could not resolve domain '{d}': {e}")
                sys.exit(1)
            try:
                domain_projects = list(conn.identity.projects(domain_id=dom.id))
            except Exception as e:
                logging.error(f"Could not list projects for domain '{d}': {e}")
                sys.exit(1)
            for proj in domain_projects:
                project_ids.add(proj.id)

    if not project_ids:
        logging.warning("No projects matched --project/--domain filters; nothing to do.")

    return project_ids


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


def make_project_name_resolver(conn):
    """Returns a cached lookup function: project_id -> project name (or id if lookup fails)"""
    cache = {}

    def resolve(project_id):
        if not project_id:
            return "<unknown>"
        if project_id not in cache:
            try:
                proj = conn.identity.get_project(project_id)
                cache[project_id] = proj.name
            except Exception:
                cache[project_id] = project_id
        return cache[project_id]

    return resolve


def print_listing(conn, target_vms, project_name, header):
    """Print the found VMs + their attached volumes (used for dry-run and info mode)"""
    print(f"\n{header}")
    for vm in target_vms:
        proj = project_name(getattr(vm, 'project_id', None))
        print(f"VM: {vm.id[:8]}... {vm.name or '<unnamed>':<30} | status={vm.status} | project={proj}")
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

    # Resolve --project/--domain filters (None = no filtering, i.e. all projects/domains)
    project_filter = resolve_project_filter(conn, args)
    if project_filter is not None and not project_filter:
        return  # nothing matched --project/--domain

    # Always search/collect matching VMs, regardless of --force-delete,
    # so the user can see what would be affected.
    if target_status:
        logging.info(f"Searching for VMs in '{target_status}' status (all projects/domains unless filtered)...")
        target_vms = list(conn.compute.servers(status=target_status, all_projects=True))
    else:
        logging.info("Searching for VMs in ANY status (all projects/domains unless filtered)...")
        target_vms = list(conn.compute.servers(all_projects=True))

    if project_filter is not None:
        before = len(target_vms)
        target_vms = [vm for vm in target_vms if getattr(vm, 'project_id', None) in project_filter]
        logging.info(f"Filtered by --project/--domain: {before} -> {len(target_vms)} VMs")

    if not target_vms:
        logging.info("No matching VMs found.")
        return

    logging.info(f"Found {len(target_vms)} target VMs")

    project_name = make_project_name_resolver(conn)

    # --dry-run always just lists what would happen, whether or not --force-delete was given.
    if args.dry_run:
        print_listing(conn, target_vms, project_name, "DRY RUN — no changes will be made")
        return

    # No --force-delete: informational listing only, no changes, no confirmation prompt.
    if not args.force_delete:
        print_listing(conn, target_vms, project_name, "INFO — the following VMs match your filters (no changes made)")
        print("\nRun with --force-delete flag to perform cleanup\n")
        return

    # From here on we are about to make real changes.
    if args.all_statuses and not args.yes:
        if not confirm_all_statuses():
            logging.info("Aborted by user.")
            return

    print("\n" + "=" * 80)
    scope_desc = target_status if target_status else "ALL statuses"
    if args.project or args.domain:
        scope_desc += " | filtered by --project/--domain"
    else:
        scope_desc += " | all projects/domains"
    print(f"CLEANUP: {scope_desc} → reset volumes to error → delete volumes → delete VMs")
    print("=" * 80)

    deleted_vms = 0
    deleted_volumes = 0
    reset_volumes_count = 0

    for vm in target_vms:
        proj = project_name(getattr(vm, 'project_id', None))
        print(f"\nProcessing VM: {vm.id}  {vm.name or '<unnamed>'}  (status={vm.status}, project={proj})")

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