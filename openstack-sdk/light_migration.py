#!/usr/bin/env python3
"""
OpenStack VM Live Migration Tool with SHUTOFF handling

Migrates VMs (ACTIVE → live migration, SHUTOFF → start + live migration)
from source host to target host (or to any if target not specified).
"""

import openstack
import argparse
import logging
import time
import sys
from typing import List, Dict, Any
from concurrent.futures import ThreadPoolExecutor, as_completed


def parse_arguments() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Migrate VMs from one compute host to another (or let scheduler choose)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  %(prog)s --source-host compute-05 --target-host compute-12
  %(prog)s --source-host compute-05 --dry-run
  %(prog)s --source-host compute-05 --max-parallel 4 --on-shared-storage
  %(prog)s --source-host compute-05 --project-id 8a4... --timeout-per-vm 600
        """
    )

    parser.add_argument(
        "--source-host",
        required=True,
        help="Source compute host (from where we migrate VMs)"
    )
    parser.add_argument(
        "--target-host",
        help="Target compute host (optional — if omitted, Nova scheduler decides)"
    )
    parser.add_argument(
        "--cloud",
        default=None,
        help="OpenStack clouds.yaml cloud name"
    )
    parser.add_argument(
        "--project-id",
        help="Filter VMs only from this project"
    )
    parser.add_argument(
        "--max-parallel",
        type=int,
        default=2,
        help="Maximum concurrent migrations / starts (default: 2)"
    )
    parser.add_argument(
        "--timeout-per-vm",
        type=int,
        default=900,
        help="Timeout for single VM operation (start or migrate) in seconds (default: 900)"
    )
    parser.add_argument(
        "--on-shared-storage",
        action="store_true",
        help="Pass on_shared_storage=True (useful for live migrate without shared storage)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only show what would be done, no real actions"
    )
    parser.add_argument(
        "--log-level",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        default="INFO",
        help="Logging level (default: INFO)"
    )

    return parser.parse_args()


class HostVMmigrator:
    """Live migrates VMs from one host to another (or lets scheduler choose)"""

    def __init__(self, config: dict):
        self.config = config
        self.conn = None
        self.vms_to_migrate: List = []

    def run(self) -> bool:
        """Execute the full migration workflow."""
        try:
            self.connect()
            if not self.validate_source_host():
                return False

            self.find_vms_to_process()

            if not self.vms_to_migrate:
                logging.info("No ACTIVE or SHUTOFF VMs found on source host → nothing to do")
                return True

            logging.info(f"Found {len(self.vms_to_migrate)} VMs to process "
                         f"({sum(1 for v in self.vms_to_migrate if v.status == 'SHUTOFF')} SHUTOFF)")

            if self.config["dry_run"]:
                self.dry_run_report()
                return True

            results = self.process_vms()
            self.print_summary(results)

            success_count = sum(1 for r in results if r["success"])
            return success_count == len(results)  # all must succeed for overall success

        except Exception as e:
            logging.exception(f"Critical failure: {e}")
            return False

    def connect(self):
        """Establish connection to OpenStack."""
        try:
            if self.config["cloud"]:
                self.conn = openstack.connect(cloud=self.config["cloud"])
            else:
                self.conn = openstack.connect()
            self.conn.authorize()
            logging.info("Connected to OpenStack")
        except Exception as e:
            logging.error(f"Connection failed: {e}")
            raise

    def validate_source_host(self) -> bool:
        """Verify that source hypervisor and nova-compute service are operational."""
        host = self.config["source_host"]
        logging.info(f"Checking source host: {host}")

        hyp = self.conn.compute.find_hypervisor(host, ignore_missing=True)
        if not hyp:
            logging.error(f"Hypervisor {host} not found")
            return False

        if hyp.status != "enabled" or hyp.state != "up":
            logging.error(f"Source host is not operational: status={hyp.status}, state={hyp.state}")
            return False

        # Find nova-compute services running on this host
        compute_services = list(
            self.conn.compute.services(binary="nova-compute", host=host)
        )

        if not compute_services:
            logging.error(f"No nova-compute service found for host {host}")
            return False

        for svc in compute_services:
            if svc.status != "enabled" or svc.state != "up":
                logging.error(
                    f"nova-compute service on {host} is not operational: "
                    f"state={svc.state}, status={svc.status}"
                )
                return False

        logging.info(f"nova-compute service(s) on {host} are operational")
        return True

    def find_vms_to_process(self):
        """Find all ACTIVE and SHUTOFF VMs residing on the source host."""
        self.vms_to_migrate = []

        # Note: status filter may not be supported in all SDK versions — fallback to manual check
        servers = self.conn.compute.servers(all_projects=True)

        for server in servers:
            if getattr(server, "hypervisor_hostname", None) != self.config["source_host"]:
                continue
            if self.config["project_id"] and server.project_id != self.config["project_id"]:
                continue
            if server.status not in ("ACTIVE", "SHUTOFF"):
                continue
            self.vms_to_migrate.append(server)

    def dry_run_report(self):
        """Print summary of what would be migrated without performing any actions."""
        logging.info("═" * 70)
        logging.info("DRY-RUN MODE — no real actions will be performed")
        logging.info("═" * 70)

        shutoff = [vm for vm in self.vms_to_migrate if vm.status == "SHUTOFF"]
        active = [vm for vm in self.vms_to_migrate if vm.status == "ACTIVE"]

        logging.info(f"Would process {len(self.vms_to_migrate)} VMs:")
        logging.info(f"  • {len(shutoff)} SHUTOFF → start + migrate")
        logging.info(f"  • {len(active)}  ACTIVE  → live migrate")

        if self.config["target_host"]:
            logging.info(f"Target host: {self.config['target_host']}")
        else:
            logging.info("Target host: not specified → Nova scheduler will choose")

        logging.info("\nSample VMs:")
        for vm in self.vms_to_migrate[:10]:
            logging.info(f"  • {vm.name or vm.id}  ({vm.status})")
        if len(self.vms_to_migrate) > 10:
            logging.info(f"  ... and {len(self.vms_to_migrate)-10} more")

    def process_vms(self) -> List[Dict[str, Any]]:
        """Start and/or migrate all collected VMs in parallel."""
        results = []
        max_workers = min(self.config["max_parallel"], len(self.vms_to_migrate))

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(self.migrate_or_start_and_migrate, vm): vm
                for vm in self.vms_to_migrate
            }

            for future in as_completed(futures):
                vm = futures[future]
                try:
                    results.append(future.result())
                except Exception as exc:
                    results.append({
                        "vm_id": vm.id,
                        "vm_name": vm.name or vm.id,
                        "original_status": vm.status,
                        "success": False,
                        "error": str(exc),
                        "duration": 0,
                        "final_host": None,
                        "actions": [],
                    })

        return results

    def migrate_or_start_and_migrate(self, vm) -> Dict[str, Any]:
        """Perform start (if needed) and live migration for a single VM."""
        result = {
            "vm_id": vm.id,
            "vm_name": vm.name or vm.id,
            "original_status": vm.status,
            "success": False,
            "error": None,
            "duration": 0,
            "final_host": None,
            "actions": [],
        }

        start_ts = time.time()

        try:
            if vm.status == "SHUTOFF":
                logging.info(f"Starting SHUTOFF VM: {vm.name}")
                result["actions"].append("start")
                self.conn.compute.start_server(vm)
                if not self._wait_for_status(vm.id, "ACTIVE", self.config["timeout_per_vm"]):
                    raise RuntimeError("VM failed to reach ACTIVE state after start")

            # Perform live migration
            logging.info(f"Live migrating VM: {vm.name}")
            migrate_kwargs = {"server": vm.id}

            if self.config["target_host"]:
                migrate_kwargs["host"] = self.config["target_host"]

            if self.config["on_shared_storage"]:
                migrate_kwargs["block_migration"] = False
            else:
                migrate_kwargs["block_migration"] = True

            result["actions"].append("live-migrate")
            self.conn.compute.live_migrate_server(**migrate_kwargs)

            if not self._wait_for_migration_complete(vm.id, self.config["timeout_per_vm"]):
                raise RuntimeError("Live migration did not complete in time")

            # Get final location
            vm = self.conn.compute.get_server(vm.id)
            result["final_host"] = getattr(vm, "hypervisor_hostname", "unknown")
            result["success"] = True

        except Exception as e:
            result["error"] = str(e)

        result["duration"] = time.time() - start_ts
        return result

    def _wait_for_status(self, server_id: str, desired_status: str, timeout: int, interval: int = 6) -> bool:
        """Wait until server reaches desired status or fails."""
        start = time.time()
        while time.time() - start < timeout:
            server = self.conn.compute.get_server(server_id)
            if server.status == desired_status:
                return True
            if server.status == "ERROR":
                return False
            time.sleep(interval)
        return False

    def _wait_for_migration_complete(self, server_id: str, timeout: int, interval: int = 8) -> bool:
        """
        Wait for live migration to finish.
        Simple heuristic: wait until VM is ACTIVE again after seeing non-ACTIVE state.
        """
        start = time.time()
        seen_non_active = False

        while time.time() - start < timeout:
            server = self.conn.compute.get_server(server_id)

            if server.status == "ERROR":
                return False

            if server.status != "ACTIVE":
                seen_non_active = True
                time.sleep(interval)
                continue

            if seen_non_active:
                return True

            time.sleep(interval)

        return False

    def print_summary(self, results: List[Dict]):
        """Print summary of migration results."""
        total = len(results)
        success = sum(1 for r in results if r["success"])
        failed = total - success

        logging.info("═" * 70)
        logging.info("MIGRATION SUMMARY")
        logging.info("═" * 70)
        logging.info(f"Source host     : {self.config['source_host']}")
        logging.info(f"Target host     : {self.config['target_host'] or 'Nova scheduler'}")
        logging.info(f"Total VMs       : {total}")
        logging.info(f"Successfully    : {success} ({success/total*100:.1f}%)")
        logging.info(f"Failed          : {failed}")

        if failed > 0:
            logging.info("\nFailed VMs:")
            for r in [r for r in results if not r["success"]]:
                logging.info(f"  • {r['vm_name']}  ({r['original_status']}) → {r['error']}")

        times = [r["duration"] for r in results if r["success"]]
        if times:
            logging.info(f"Avg successful duration : {sum(times)/len(times):.0f} s")


def main():
    """Main entry point."""
    args = parse_arguments()

    config = {
        "source_host": args.source_host,
        "target_host": args.target_host,
        "cloud": args.cloud,
        "project_id": args.project_id,
        "max_parallel": args.max_parallel,
        "timeout_per_vm": args.timeout_per_vm,
        "on_shared_storage": args.on_shared_storage,
        "dry_run": args.dry_run,
    }

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper()),
        format="%(asctime)s [%(levelname)-5s] %(message)s",
        datefmt="%H:%M:%S",
    )

    migrator = HostVMmigrator(config)
    ok = migrator.run()

    sys.exit(0 if ok else 2)


if __name__ == "__main__":
    main()
