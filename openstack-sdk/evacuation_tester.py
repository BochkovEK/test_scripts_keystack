#!/usr/bin/env python3
"""
OpenStack Simple Evacuation Tester

Simplified script for testing VM evacuation from a failed hypervisor.
Performs validation checks and executes evacuation with minimal complexity.

Note: Host must be already DOWN and nova-compute services forced_down before running.
This script no longer forces host down or restores it automatically.
"""

import openstack
import argparse
import logging
import os
import sys
import time
import json
from typing import List, Dict, Any
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed


def parse_arguments() -> argparse.Namespace:
    """
    Parse command line arguments.
    """
    parser = argparse.ArgumentParser(
        description='Simple OpenStack Hypervisor Evacuation Tester',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --failed-host compute-01 --dry-run
  %(prog)s --failed-host compute-01 --target-hosts compute-02,compute-03
  %(prog)s --failed-host compute-01 --max-parallel 4
  %(prog)s --failed-host compute-01 --local-storage   # only if using local disks
        """
    )

    # Required parameter
    parser.add_argument(
        '--failed-host',
        required=True,
        help='Hypervisor host to evacuate VMs from (required)'
    )

    # OpenStack connection
    parser.add_argument(
        '--cloud',
        default=None,
        help='OpenStack cloud name from clouds.yaml'
    )
    parser.add_argument(
        '--interface',
        choices=['public', 'internal', 'admin'],
        default='public',
        help='OpenStack endpoint interface'
    )

    # Host filtering
    parser.add_argument(
        '--target-hosts',
        help='Comma-separated list of allowed target hosts'
    )
    parser.add_argument(
        '--exclude-hosts',
        help='Comma-separated list of hosts to exclude'
    )
    parser.add_argument(
        '--availability-zone',
        help='Restrict to hosts in this availability zone'
    )
    parser.add_argument(
        '--project-id',
        help='Only evacuate VMs from this project'
    )

    # Execution control
    parser.add_argument(
        '--max-parallel',
        type=int,
        default=1,
        help='Maximum parallel evacuations (default: 1)'
    )
    parser.add_argument(
        '--evacuation-timeout',
        type=int,
        default=1800,
        help='Overall evacuation timeout in seconds (default: 1800)'
    )
    parser.add_argument(
        '--per-vm-timeout',
        type=int,
        default=300,
        help='Timeout per VM in seconds (default: 300)'
    )

    # Storage mode flags
    parser.add_argument(
        '--local-storage',
        action='store_true',
        help='Use block migration (only if VMs use local storage, not shared FC/Ceph/NFS)'
    )

    # Output
    parser.add_argument(
        '--log-level',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        default='INFO',
        help='Logging level (default: INFO)'
    )
    parser.add_argument(
        '--output-format',
        choices=['table', 'json', 'text'],
        default='table',
        help='Results output format (default: table)'
    )
    parser.add_argument(
        '--results-file',
        default='evacuation_results.json',
        help='Path to save results JSON file'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Validate only, no actual evacuation'
    )

    args = parser.parse_args()

    # Process comma-separated lists
    if args.target_hosts:
        args.target_hosts = [h.strip() for h in args.target_hosts.split(',') if h.strip()]
    if args.exclude_hosts:
        args.exclude_hosts = [h.strip() for h in args.exclude_hosts.split(',') if h.strip()]

    return args


def get_config(args: argparse.Namespace) -> dict:
    """
    Build configuration dictionary from arguments.
    """
    return {
        'failed_host': args.failed_host,
        'cloud_name': args.cloud or os.getenv('OS_CLOUD'),
        'interface': args.interface,
        'target_hosts': args.target_hosts,
        'exclude_hosts': args.exclude_hosts,
        'availability_zone': args.availability_zone,
        'project_id': args.project_id,
        'max_parallel': args.max_parallel,
        'evacuation_timeout': args.evacuation_timeout,
        'per_vm_timeout': args.per_vm_timeout,
        'use_shared_storage': not args.local_storage,  # True by default, False if --local-storage
        'dry_run': args.dry_run,
        'log_level': args.log_level,
        'output_format': args.output_format,
        'results_file': args.results_file,
    }


def setup_logging(log_level: str):
    """Configure logging."""
    logging.basicConfig(
        level=getattr(logging, log_level),
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%H:%M:%S'
    )


class SimpleEvacuationTester:
    """Simplified evacuation tester"""

    def __init__(self, config: dict):
        self.config = config
        self.conn = None
        self.failed_host_info = None
        self.vms = []
        self.target_hosts = []
        self.results = []
        self.start_time = None
        self.end_time = None

    def connect(self):
        """Connect to OpenStack."""
        try:
            if self.config['cloud_name']:
                self.conn = openstack.connect(
                    cloud=self.config['cloud_name'],
                    interface=self.config['interface']
                )
                logging.info(f"Connected via clouds.yaml, cloud: {self.config['cloud_name']}")
            else:
                self.conn = openstack.connect()
                logging.info("Connected via environment variables")

            self.conn.authorize()
            logging.info("Authentication successful")

        except Exception as e:
            logging.error(f"Connection failed: {e}")
            raise

    def get_host_by_name(self, host_name: str):
        """Find hypervisor by name."""
        try:
            for hyp in self.conn.compute.hypervisors():
                if hyp.name == host_name:
                    return hyp
            return None
        except Exception as e:
            logging.error(f"Error finding hypervisor {host_name}: {e}")
            return None

    def get_vms_on_host(self, host_name: str) -> List:
        """Find VMs on specified host."""
        vms = []
        try:
            for server in self.conn.compute.servers(all_projects=True):
                if getattr(server, 'hypervisor_hostname', None) != host_name:
                    continue
                if self.config['project_id'] and server.project_id != self.config['project_id']:
                    continue
                if server.status not in ['ACTIVE', 'SHUTOFF', 'ERROR']:
                    continue
                vms.append(server)
            return vms
        except Exception as e:
            logging.error(f"Error finding VMs on {host_name}: {e}")
            return []

    def get_available_targets(self) -> List[str]:
        """Find available target hosts for evacuation."""
        targets = []
        try:
            for hyp in self.conn.compute.hypervisors():
                if hyp.name == self.config['failed_host']:
                    continue
                if hyp.state != 'up' or hyp.status != 'enabled':
                    continue
                if self.config['target_hosts'] and hyp.name not in self.config['target_hosts']:
                    continue
                if self.config['exclude_hosts'] and hyp.name in self.config['exclude_hosts']:
                    continue
                if (self.config['availability_zone'] and
                        hasattr(hyp, 'availability_zone') and
                        hyp.availability_zone != self.config['availability_zone']):
                    continue
                targets.append(hyp.name)
            return targets
        except Exception as e:
            logging.error(f"Error finding target hosts: {e}")
            return []

    def validate_host(self) -> bool:
        """Validate failed host state."""
        logging.info(f"Validating host: {self.config['failed_host']}")

        self.failed_host_info = self.get_host_by_name(self.config['failed_host'])

        if not self.failed_host_info:
            logging.error(f"Host '{self.config['failed_host']}' not found")
            return False

        logging.info(f"Host found: {self.failed_host_info.name} "
                     f"(state: {self.failed_host_info.state}, status: {self.failed_host_info.status})")

        if self.failed_host_info.state == 'up':
            logging.error("Host is UP — evacuation will most likely fail")
            logging.error("You must put host DOWN and force nova-compute services down manually")
            return False

        return True

    def validate_vms(self) -> bool:
        """Validate VMs on failed host."""
        logging.info(f"Looking for VMs on {self.config['failed_host']}")
        self.vms = self.get_vms_on_host(self.config['failed_host'])

        if not self.vms:
            logging.error(f"No suitable VMs found on host {self.config['failed_host']}")
            return False

        logging.info(f"Found {len(self.vms)} VMs eligible for evacuation")
        if self.config['dry_run']:
            for vm in self.vms[:6]:
                logging.info(f"  • {vm.name} ({vm.status})")
            if len(self.vms) > 6:
                logging.info(f"  ... and {len(self.vms)-6} more")

        return True

    def validate_target_hosts(self) -> bool:
        """Validate available target hosts."""
        logging.info("Looking for available target hosts")
        self.target_hosts = self.get_available_targets()

        if not self.target_hosts:
            logging.error("No available target hosts found")
            return False

        logging.info(f"Found {len(self.target_hosts)} available target hosts")
        if self.config['dry_run']:
            for h in self.target_hosts[:8]:
                logging.info(f"  • {h}")
            if len(self.target_hosts) > 8:
                logging.info(f"  ... and {len(self.target_hosts)-8} more")

        return True

    def show_recommendations(self):
        """Show dry-run recommendations."""
        if not self.config['dry_run']:
            return

        logging.info("\nRecommendations / reminders:")
        logging.info("  • Host must be DOWN before real evacuation")
        logging.info("  • nova-compute services should be disabled + forced_down")
        logging.info(f"  • {len(self.vms)} VMs will be evacuated")
        logging.info(f"  • {len(self.target_hosts)} target hosts available")
        logging.info("  • Using shared storage mode by default (on_shared_storage=True)")
        if self.config['max_parallel'] > 1:
            logging.info(f"  • Parallel mode: up to {self.config['max_parallel']} concurrent evacuations")

    # def evacuate_single_vm(self, vm) -> Dict[str, Any]:
    #     """Evacuate single VM."""
    #     result = {
    #         'vm_id': vm.id,
    #         'vm_name': vm.name,
    #         'success': False,
    #         'start_time': time.time(),
    #         'error_message': None,
    #         'target_host': None,
    #         'evacuation_time': 0
    #     }
    #
    #     try:
    #         logging.info(f"Evacuating: {vm.name}")
    #
    #         params = {'server': vm.id}
    #
    #         # Always use on_shared_storage=True unless --local-storage is specified
    #         # ks-2025.3.1 nova does not support the on_shared_storage parameter
    #         # "...Additional properties are not allowed ('onSharedStorage' was unexpected)"
    #         params['on_shared_storage'] = self.config['use_shared_storage']
    #
    #         params['microversion'] = '2.7'
    #
    #         if len(self.target_hosts) == 1:
    #             params['host'] = self.target_hosts[0]
    #             logging.info(f"  → explicit target: {self.target_hosts[0]}")
    #
    #         self.conn.compute.evacuate_server(**params)
    #
    #         success, target = self.monitor_evacuation(vm)
    #         result['success'] = success
    #         result['target_host'] = target
    #
    #     except Exception as e:
    #         result['error_message'] = str(e)
    #         logging.error(f"Evacuation error {vm.name}: {e}")
    #
    #     finally:
    #         result['end_time'] = time.time()
    #         result['evacuation_time'] = result['end_time'] - result['start_time']
    #
    #     if result['success']:
    #         logging.info(f"✓ {vm.name} → {result['target_host']} ({result['evacuation_time']:.1f}s)")
    #     else:
    #         logging.error(f"✗ {vm.name} failed")
    #
    #     return result

    def evacuate_single_vm(self, vm) -> Dict[str, Any]:
        """
        Evacuate single VM using low-level POST request to support custom microversion
        and onSharedStorage parameter.
        """
        result = {
            'vm_id': vm.id,
            'vm_name': vm.name,
            'success': False,
            'start_time': time.time(),
            'error_message': None,
            'target_host': None,
            'evacuation_time': 0
        }

        try:
            logging.info(f"Evacuating: {vm.name}")

            # Build evacuate payload
            payload = {
                "evacuate": {
                    "host": None  # will be set below if needed
                }
            }

            # Explicitly add onSharedStorage (case-sensitive as per Nova API)
            payload["evacuate"]["onSharedStorage"] = True  # always True for shared storage

            # Optional: target host
            if len(self.target_hosts) == 1:
                payload["evacuate"]["host"] = self.target_hosts[0]
                logging.info(f"  → explicit target: {self.target_hosts[0]}")

            # Low-level POST to /servers/{id}/action with explicit microversion
            response = self.conn.compute.post(
                f"/servers/{vm.id}/action",
                json=payload,
                microversion="2.14"  # minimum for onSharedStorage; try "2.95" if newer
            )

            if response.status_code == 202:
                logging.debug("Evacuation request accepted (202 Accepted)")
                success, target = self.monitor_evacuation(vm)
                result['success'] = success
                result['target_host'] = target
            else:
                error_text = response.text if hasattr(response, 'text') else str(response)
                raise openstack.exceptions.BadRequestException(
                    f"Evacuation failed: HTTP {response.status_code} - {error_text}"
                )

        except Exception as e:
            result['error_message'] = str(e)
            logging.error(f"Evacuation error {vm.name}: {e}")

        finally:
            result['end_time'] = time.time()
            result['evacuation_time'] = result['end_time'] - result['start_time']

        if result['success']:
            logging.info(f"✓ {vm.name} → {result['target_host']} ({result['evacuation_time']:.1f}s)")
        else:
            logging.error(f"✗ {vm.name} failed")

        return result

    def monitor_evacuation(self, vm, check_interval: int = 3):
        """Monitor evacuation progress."""
        timeout = self.config['per_vm_timeout']
        start = time.time()
        orig_host = getattr(vm, 'hypervisor_hostname', None)

        while time.time() - start < timeout:
            try:
                vm = self.conn.compute.get_server(vm.id)
                curr_host = getattr(vm, 'hypervisor_hostname', None)

                if curr_host and curr_host != orig_host:
                    return True, curr_host

                if vm.status == 'ERROR':
                    return False, None

                time.sleep(check_interval)

            except Exception:
                time.sleep(check_interval)

        return False, None

    def execute_evacuation(self) -> List[Dict[str, Any]]:
        """Execute evacuation of all VMs with parallel support."""
        logging.info(f"Starting evacuation of {len(self.vms)} VMs")

        if self.config['max_parallel'] <= 1:
            return self._execute_sequential()
        else:
            return self._execute_parallel(self.config['max_parallel'])

    def _execute_sequential(self):
        """Execute evacuations sequentially."""
        logging.info("Using sequential evacuation")
        return [self.evacuate_single_vm(vm) for vm in self.vms]

    def _execute_parallel(self, max_workers: int):
        """Execute evacuations in parallel using ThreadPoolExecutor."""
        logging.info(f"Using parallel evacuation with {max_workers} workers")
        results = []

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(self.evacuate_single_vm, vm): vm
                for vm in self.vms
            }

            for future in as_completed(futures):
                vm = futures[future]
                try:
                    results.append(future.result())
                except Exception as e:
                    logging.error(f"Unexpected error for {vm.name}: {e}")
                    results.append({
                        'vm_id': vm.id,
                        'vm_name': vm.name,
                        'success': False,
                        'error_message': str(e),
                        'evacuation_time': 0
                    })

        return results

    def create_report(self, results: List[Dict[str, Any]]):
        """Create evacuation report."""
        if not results:
            return

        successful = sum(1 for r in results if r['success'])
        failed = len(results) - successful

        report = {
            'summary': {
                'failed_host': self.config['failed_host'],
                'start_time': datetime.fromtimestamp(self.start_time).isoformat(),
                'end_time': datetime.fromtimestamp(self.end_time).isoformat(),
                'total_duration': self.end_time - self.start_time,
                'total_vms': len(results),
                'successful': successful,
                'failed': failed,
                'success_rate': successful / len(results) * 100 if results else 0,
            },
            'configuration': {
                'use_shared_storage': self.config['use_shared_storage'],
                'max_parallel': self.config['max_parallel'],
                'target_hosts_count': len(self.target_hosts),
            },
            'results': results
        }

        if successful > 0:
            times = [r['evacuation_time'] for r in results if r['success']]
            report['timing'] = {
                'average': sum(times) / len(times),
                'min': min(times),
                'max': max(times)
            }

        self.output_report(report)

    def output_report(self, report: dict):
        """Output report in specified format."""
        if self.config['output_format'] == 'json':
            print(json.dumps(report, indent=2, ensure_ascii=False))
        elif self.config['output_format'] == 'table':
            self._print_table_report(report)
        else:
            self._print_text_report(report)

        try:
            with open(self.config['results_file'], 'w', encoding='utf-8') as f:
                json.dump(report, f, indent=2, ensure_ascii=False)
            logging.info(f"Results saved: {self.config['results_file']}")
        except Exception as e:
            logging.error(f"Cannot save report: {e}")

    def _print_text_report(self, report):
        """Print text format report."""
        s = report['summary']
        print("\n" + "="*70)
        print(" EVACUATION SUMMARY ")
        print("="*70)
        print(f" Host          : {s['failed_host']}")
        print(f" Duration      : {s['total_duration']:.1f} s")
        print(f" VMs total     : {s['total_vms']}")
        print(f" Succeeded     : {s['successful']} ({s['success_rate']:.1f}%)")
        print(f" Failed        : {s['failed']}")
        if 'timing' in report:
            t = report['timing']
            print(f" Avg time      : {t['average']:.1f} s")
            print(f" Min / Max     : {t['min']:.1f} – {t['max']:.1f} s")
        print("="*70 + "\n")

    def _print_table_report(self, report):
        """Print table format report."""
        try:
            from tabulate import tabulate
            s = report['summary']
            rows = [
                ["Host", s['failed_host']],
                ["Duration", f"{s['total_duration']:.1f} s"],
                ["VMs total", s['total_vms']],
                ["Succeeded", f"{s['successful']} ({s['success_rate']:.1f}%)"],
                ["Failed", s['failed']],
            ]
            print("\n" + tabulate(rows, headers=["Metric", "Value"], tablefmt="grid"))

            if 'timing' in report:
                t = report['timing']
                timing_rows = [
                    ["Average", f"{t['average']:.1f} s"],
                    ["Minimum", f"{t['min']:.1f} s"],
                    ["Maximum", f"{t['max']:.1f} s"],
                ]
                print("\nTiming (successful VMs):")
                print(tabulate(timing_rows, headers=["Stat", "Value"], tablefmt="grid"))
            print()

        except ImportError:
            self._print_text_report(report)

    def dry_run(self) -> bool:
        """Perform dry-run validation only."""
        logging.info("DRY-RUN MODE")
        ok = all([
            self.validate_host(),
            self.validate_vms(),
            self.validate_target_hosts(),
        ])
        if ok:
            logging.info("All validations passed ✓")
            self.show_recommendations()
        else:
            logging.error("Some validations failed")
        return ok

    def real_evacuation(self) -> bool:
        """Perform real evacuation."""
        logging.info("REAL EVACUATION START")
        self.start_time = time.time()

        if not all([
            self.validate_host(),
            self.validate_vms(),
            self.validate_target_hosts(),
        ]):
            return False

        results = self.execute_evacuation()
        self.end_time = time.time()
        self.create_report(results)

        success_count = sum(1 for r in results if r['success'])
        return success_count > 0

    def run(self) -> bool:
        """Main execution method."""
        try:
            self.connect()

            if self.config['dry_run']:
                return self.dry_run()
            else:
                return self.real_evacuation()

        except Exception as e:
            logging.exception(f"Critical error: {e}")
            return False


def main():
    """Main entry point."""
    args = parse_arguments()
    config = get_config(args)
    setup_logging(config['log_level'])

    tester = SimpleEvacuationTester(config)
    success = tester.run()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
