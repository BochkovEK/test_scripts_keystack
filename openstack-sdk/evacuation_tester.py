#!/usr/bin/env python3
"""
OpenStack Simple Evacuation Tester

Simplified script for testing VM evacuation from a failed hypervisor.
Performs validation checks and executes evacuation with minimal complexity.
"""

import openstack
import argparse
import logging
import os
import sys
import time
import json
from typing import List, Optional, Dict, Any
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed


def parse_arguments() -> argparse.Namespace:
    """
    Parse command line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description='Simple OpenStack Hypervisor Evacuation Tester',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --failed-host compute-01 --dry-run
  %(prog)s --failed-host compute-01 --force-host-down
  %(prog)s --failed-host compute-01 --target-hosts compute-02,compute-03
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

    # Control flags
    parser.add_argument(
        '--force-host-down',
        action='store_true',
        help='Force host into down state before testing'
    )
    parser.add_argument(
        '--on-shared-storage',
        action='store_true',
        help='Indicate shared storage is used'
    )
    parser.add_argument(
        '--restore-after-test',
        action='store_true',
        help='Restore host after test completion'
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
        args.target_hosts = args.target_hosts.split(',')
    if args.exclude_hosts:
        args.exclude_hosts = args.exclude_hosts.split(',')

    return args


def get_config(args: argparse.Namespace) -> dict:
    """
    Build configuration dictionary.

    Returns:
        dict: Configuration
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
        'force_host_down': args.force_host_down,
        'on_shared_storage': args.on_shared_storage,
        'restore_after_test': args.restore_after_test,
        'dry_run': args.dry_run,
        'log_level': args.log_level,
        'output_format': args.output_format,
        'results_file': args.results_file or 'evacuation_results.json',
    }


def setup_logging(log_level: str):
    """
    Configure logging.

    Args:
        log_level: Logging level
    """
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
        """
        Connect to OpenStack.

        Raises:
            Exception: If connection fails
        """
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

            # Test connection
            self.conn.authorize()
            logging.info("Authentication successful")

        except Exception as e:
            logging.error(f"Connection failed: {e}")
            raise

    def get_host_by_name(self, host_name: str):
        """
        Find hypervisor by name.

        Args:
            host_name: Host name to find

        Returns:
            Hypervisor object or None
        """
        try:
            hypervisors = list(self.conn.compute.hypervisors())
            for hyp in hypervisors:
                if hyp.name == host_name:
                    return hyp
            return None
        except Exception as e:
            logging.error(f"Error finding hypervisor {host_name}: {e}")
            return None

    def get_vms_on_host(self, host_name: str) -> List:
        """
        Find VMs on specified host.

        Args:
            host_name: Host name

        Returns:
            List of VMs
        """
        vms = []
        try:
            all_servers = list(self.conn.compute.servers(all_projects=True))

            for server in all_servers:
                server_host = getattr(server, 'hypervisor_hostname', None)

                # Check if VM is on the host
                if not server_host or server_host != host_name:
                    continue

                # Apply project filter
                if (self.config['project_id'] and
                        getattr(server, 'project_id', None) != self.config['project_id']):
                    continue

                # Check VM status
                if server.status not in ['ACTIVE', 'SHUTOFF', 'ERROR']:
                    continue

                vms.append(server)

            return vms

        except Exception as e:
            logging.error(f"Error finding VMs on {host_name}: {e}")
            return []

    def get_available_targets(self) -> List[str]:
        """
        Find available target hosts for evacuation.

        Returns:
            List of host names
        """
        targets = []
        try:
            hypervisors = list(self.conn.compute.hypervisors())

            for hyp in hypervisors:
                # Skip failed host
                if hyp.name == self.config['failed_host']:
                    continue

                # Check host state
                if hyp.state != 'up' or hyp.status != 'enabled':
                    continue

                # Apply filters
                if self.config['target_hosts'] and hyp.name not in self.config['target_hosts']:
                    continue
                if self.config['exclude_hosts'] and hyp.name in self.config['exclude_hosts']:
                    continue

                # Check availability zone
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
        """
        Validate failed host.

        Returns:
            bool: True if validation passed
        """
        logging.info(f"Validating host: {self.config['failed_host']}")

        self.failed_host_info = self.get_host_by_name(self.config['failed_host'])

        if not self.failed_host_info:
            logging.error(f"Host '{self.config['failed_host']}' not found")
            return False

        logging.info(f"Host found: {self.failed_host_info.name} "
                     f"(state: {self.failed_host_info.state}, "
                     f"status: {self.failed_host_info.status})")

        # Warn if host is up
        if self.failed_host_info.state == 'up':
            logging.warning("⚠️  Host is UP (not down)")
            logging.warning("   For evacuation, host must be DOWN")
            logging.warning("   Use --force-host-down to simulate failure")

        return True

    def validate_vms(self) -> bool:
        """
        Validate VMs on failed host.

        Returns:
            bool: True if VMs found
        """
        logging.info(f"Looking for VMs on {self.config['failed_host']}")

        self.vms = self.get_vms_on_host(self.config['failed_host'])

        if not self.vms:
            logging.error(f"No VMs found on host {self.config['failed_host']}")
            logging.info("Check host name or use --project-id filter")
            return False

        logging.info(f"Found {len(self.vms)} VMs on host")

        # Show sample VMs in dry-run
        if self.config['dry_run']:
            for vm in self.vms[:5]:  # First 5 VMs
                logging.info(f"  - {vm.name} ({vm.status})")
            if len(self.vms) > 5:
                logging.info(f"  ... and {len(self.vms) - 5} more")

        return True

    def validate_target_hosts(self) -> bool:
        """
        Validate available target hosts.

        Returns:
            bool: True if targets found
        """
        logging.info("Looking for available target hosts")

        self.target_hosts = self.get_available_targets()

        if not self.target_hosts:
            logging.error("No available target hosts found")
            logging.info("Check host states and filters")
            return False

        logging.info(f"Found {len(self.target_hosts)} available target hosts")

        if self.config['dry_run']:
            for host in self.target_hosts:
                logging.info(f"  - {host}")

        if self.config['max_parallel'] > 1:
            if len(self.target_hosts) == 0:
                logging.error("Parallel evacuation requires target hosts")
                return False

            if self.config['max_parallel'] > len(self.target_hosts) * 3:
                logging.warning(
                    f"High parallelism ({self.config['max_parallel']}) "
                    f"for {len(self.target_hosts)} target hosts"
                )

        return True

    def show_recommendations(self):
        """Show recommendations based on validation."""
        if not self.config['dry_run']:
            return

        logging.info("\n💡 RECOMMENDATIONS:")

        if self.failed_host_info.state == 'up':
            logging.info("  - Host is UP, MUST use: --force-host-down")

        logging.info(f"  - {len(self.vms)} VMs will be evacuated")
        logging.info(f"  - Target hosts available: {len(self.target_hosts)}")

        # Parallelism recommendations
        if self.config['max_parallel'] <= 1:
            logging.info("  - Using sequential evacuation (max_parallel <= 1)")
        else:
            logging.info(f"  - Using parallel evacuation (max_parallel={self.config['max_parallel']})")

            # Warn if too high
            if self.config['max_parallel'] > len(self.target_hosts) * 3:
                logging.warning("  ⚠️  High parallelism may overwhelm target hosts")

            if self.config['max_parallel'] > len(self.vms):
                logging.info(f"  - Note: Only {len(self.vms)} VMs, parallelism limited")

    def force_host_down(self):
        """
        Force host into down state.

        Raises:
            Exception: If operation fails or host not properly disabled
        """
        if not self.config['force_host_down']:
            logging.info(f"Using host {self.config['failed_host']} in current state")
            return

        try:
            logging.info(f"Forcing host {self.config['failed_host']} into down state...")

            # Get compute service for the host
            services = list(self.conn.compute.services(
                host=self.config['failed_host'],
                binary='nova-compute'
            ))

            if not services:
                raise ValueError(f"No nova-compute service found on host {self.config['failed_host']}")

            service = services[0]  # We expect one nova-compute service per hypervisor

            # Status → disabled
            self.conn.compute.disable_service(
                service,
                disabled_reason='Evacuation testing (forced down)'
            )

            # # State → down
            # self.conn.compute.update_service_forced_down(
            #     service,
            #     forced=True  # True = down, False = up
            # )

            # Wait for state change propagation
            logging.info("Waiting for service state change...")
            time.sleep(15)

            # Verify service is now disabled
            services = list(self.conn.compute.services(
                host=self.config['failed_host'],
                binary='nova-compute'
            ))

            if not services:
                raise ValueError(f"Service disappeared after disable attempt")

            service = services[0]
            logging.info(f"Service state after disable: {service.state}/{service.status}")

            # CRITICAL: Check if service is actually disabled
            if service.status != 'disabled':
                logging.error(f"❌ FAILED: Service not disabled. Current status: {service.status}")
                logging.error("Possible reasons:")
                logging.error("  1. Insufficient permissions")
                logging.error("  2. OpenStack configuration issue")
                logging.error("  3. Service auto-recovery")
                logging.error("")
                logging.error("Evacuation cannot proceed - host is not in down state")
                logging.error("Manual intervention required:")
                logging.error(f"  openstack compute service set --disable {self.config['failed_host']} nova-compute")
                raise Exception(f"Service not disabled after force-host-down attempt. Status: {service.status}")

            # Also check hypervisor state
            host = self.get_host_by_name(self.config['failed_host'])
            if host:
                logging.info(f"Hypervisor state: {host.state}/{host.status}")

                # Warning if hypervisor still shows as up
                if host.state == 'up':
                    logging.warning(f"⚠️  Hypervisor state still shows 'up'")
                    logging.warning("This may take time to update. Waiting additional 30 seconds...")
                    time.sleep(30)

                    # Re-check after additional wait
                    host = self.get_host_by_name(self.config['failed_host'])
                    if host and host.state == 'up':
                        logging.warning(f"Hypervisor still shows 'up' after extended wait")
                        logging.warning("Evacuation may fail if host is not properly down")

            logging.info("✅ Host successfully disabled for evacuation testing")

        except Exception as e:
            logging.error(f"Failed to disable host: {e}")
            # Don't just raise - provide specific exit
            logging.error("❌ CRITICAL: Cannot proceed with evacuation")
            logging.error("Exiting with error code 1")
            sys.exit(1)

    def restore_host(self):
        """Restore host to original state."""
        if not self.config['restore_after_test']:
            return

        try:
            logging.info(f"Restoring host {self.config['failed_host']}...")

            self.conn.compute.enable_service(
                self.config['failed_host'],
                'nova-compute'
            )

            logging.info("Host restored")

        except Exception as e:
            logging.error(f"Failed to restore host: {e}")

    def evacuate_single_vm(self, vm) -> Dict[str, Any]:
        """
        Evacuate single VM.

        Args:
            vm: VM object

        Returns:
            Dict with evacuation result
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

            params = {
                'server': vm.id,
            }

            # Add on_shared_storage if specified
            if self.config['on_shared_storage']:
                params['on_shared_storage'] = True

            # Optional: Specify target host if only one target
            if len(self.target_hosts) == 1:
                params['host'] = self.target_hosts[0]
                logging.info(f"Specifying target host: {self.target_hosts[0]}")

            # Execute evacuation
            self.conn.compute.evacuate_server(**params)

            # Monitor progress
            success, target_host = self.monitor_evacuation(vm)

            result['end_time'] = time.time()
            result['evacuation_time'] = result['end_time'] - result['start_time']
            result['success'] = success
            result['target_host'] = target_host

            if success:
                logging.info(f"✅ {vm.name} evacuated to {target_host} "
                             f"({result['evacuation_time']:.1f}s)")
            else:
                result['error_message'] = "Evacuation failed"
                logging.error(f"❌ {vm.name} evacuation failed")

        except Exception as e:
            result['end_time'] = time.time()
            result['evacuation_time'] = result['end_time'] - result['start_time']
            result['error_message'] = str(e)
            logging.error(f"❌ {vm.name} error: {e}")

        return result

    def monitor_evacuation(self, vm, check_interval: int = 2):
        """
        Monitor evacuation progress.

        Args:
            vm: VM object
            check_interval: Check interval in seconds

        Returns:
            tuple: (success, target_host)
        """
        timeout = self.config['per_vm_timeout']
        start_time = time.time()
        original_host = getattr(vm, 'hypervisor_hostname', None)

        while time.time() - start_time < timeout:
            try:
                # Refresh VM data
                vm = self.conn.compute.get_server(vm.id)
                current_host = getattr(vm, 'hypervisor_hostname', None)

                # Check if VM moved
                if current_host and current_host != original_host:
                    return True, current_host

                # Check VM status
                if vm.status == 'ERROR':
                    return False, None

                time.sleep(check_interval)

            except Exception as e:
                logging.debug(f"Monitoring error for {vm.name}: {e}")
                time.sleep(check_interval)

        return False, None

    def execute_evacuation(self) -> List[Dict[str, Any]]:
        """
        Execute evacuation of all VMs with parallel support.

        Returns:
            List of evacuation results
        """
        logging.info(f"Starting evacuation of {len(self.vms)} VMs")

        if self.config['max_parallel'] <= 1:
            # Sequential mode (backward compatible)
            return self._execute_sequential()
        else:
            # Parallel mode
            return self._execute_parallel(self.config['max_parallel'])

    def _execute_sequential(self) -> List[Dict[str, Any]]:
        """Execute evacuations sequentially."""
        logging.info("Using sequential evacuation")

        results = []
        successful = 0
        failed = 0

        for vm in self.vms:
            result = self.evacuate_single_vm(vm)
            results.append(result)

            if result['success']:
                successful += 1
            else:
                failed += 1

        logging.info(f"Evacuation completed: {successful} succeeded, {failed} failed")
        return results

    def _execute_parallel(self, max_workers: int) -> List[Dict[str, Any]]:
        """
        Execute evacuations in parallel using ThreadPoolExecutor.

        Args:
            max_workers: Maximum parallel threads

        Returns:
            List of evacuation results
        """
        logging.info(f"Using parallel evacuation with {max_workers} workers")

        results = []
        completed = 0
        successful = 0
        failed = 0
        total_vms = len(self.vms)

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit all evacuation tasks
            future_to_vm = {
                executor.submit(self.evacuate_single_vm, vm): vm
                for vm in self.vms
            }

            # Process results as they complete
            for future in as_completed(future_to_vm):
                completed += 1
                vm = future_to_vm[future]

                try:
                    result = future.result()
                    results.append(result)

                    if result['success']:
                        successful += 1
                        status = "✓"
                    else:
                        failed += 1
                        status = "✗"

                    # Log progress
                    progress = (completed / total_vms) * 100
                    logging.info(
                        f"{status} {vm.name} "
                        f"({completed}/{total_vms}, {progress:.1f}%) - "
                        f"{successful} ✓, {failed} ✗"
                    )

                except Exception as e:
                    failed += 1
                    results.append({
                        'vm_id': vm.id,
                        'vm_name': vm.name,
                        'success': False,
                        'error_message': str(e)
                    })
                    logging.error(f"✗ {vm.name}: Exception - {e}")

        logging.info(f"Evacuation completed: {successful} succeeded, {failed} failed")
        return results

    def create_report(self, results: List[Dict[str, Any]]):
        """
        Create evacuation report.

        Args:
            results: List of evacuation results
        """
        if not results:
            logging.warning("No results to report")
            return

        # Calculate statistics
        successful = [r for r in results if r['success']]
        failed = [r for r in results if not r['success']]

        report = {
            'summary': {
                'failed_host': self.config['failed_host'],
                'start_time': datetime.fromtimestamp(self.start_time).isoformat(),
                'end_time': datetime.fromtimestamp(self.end_time).isoformat(),
                'total_duration': self.end_time - self.start_time,
                'total_vms': len(results),
                'successful': len(successful),
                'failed': len(failed),
                'success_rate': (len(successful) / len(results)) * 100 if results else 0,
                'parallel_mode': 'sequential' if self.config['max_parallel'] <= 1
                else f'parallel_{self.config["max_parallel"]}'
            },
            'configuration': {
                'force_host_down': self.config['force_host_down'],
                'on_shared_storage': self.config['on_shared_storage'],
                'max_parallel': self.config['max_parallel'],
                'target_hosts': self.target_hosts
            },
            'results': results
        }

        # Add timing statistics if there are successful evacuations
        if successful:
            times = [r['evacuation_time'] for r in successful]
            report['timing'] = {
                'average': sum(times) / len(times),
                'min': min(times),
                'max': max(times)
            }

        # Output report
        self.output_report(report)

    def output_report(self, report: dict):
        """
        Output report in specified format.

        Args:
            report: Report data
        """
        if self.config['output_format'] == 'json':
            print(json.dumps(report, indent=2))
        elif self.config['output_format'] == 'table':
            self.print_table_report(report)
        else:  # text
            self.print_text_report(report)

        # Save to file
        self.save_report_to_file(report)

    def print_text_report(self, report: dict):
        """Print text format report."""
        summary = report['summary']

        print("\n" + "=" * 60)
        print("EVACUATION REPORT")
        print("=" * 60)

        print(f"\nSummary:")
        print(f"  Failed Host: {summary['failed_host']}")
        print(f"  Duration: {summary['total_duration']:.1f}s")
        print(f"  Total VMs: {summary['total_vms']}")
        print(f"  Successful: {summary['successful']} ({summary['success_rate']:.1f}%)")
        print(f"  Failed: {summary['failed']}")

        if 'timing' in report:
            timing = report['timing']
            print(f"\nTiming (successful only):")
            print(f"  Average: {timing['average']:.1f}s")
            print(f"  Minimum: {timing['min']:.1f}s")
            print(f"  Maximum: {timing['max']:.1f}s")

        print("\n" + "=" * 60)

    def print_table_report(self, report: dict):
        """Print table format report."""
        try:
            from tabulate import tabulate

            summary = report['summary']

            print("\n" + "=" * 60)
            print("EVACUATION REPORT")
            print("=" * 60)

            # Summary table
            summary_table = [
                ["Failed Host", summary['failed_host']],
                ["Total Duration", f"{summary['total_duration']:.1f}s"],
                ["Total VMs", summary['total_vms']],
                ["Successful", f"{summary['successful']} ({summary['success_rate']:.1f}%)"],
                ["Failed", summary['failed']]
            ]

            print("\nSummary:")
            print(tabulate(summary_table, tablefmt="grid"))

            # Timing table if available
            if 'timing' in report:
                timing = report['timing']
                timing_table = [
                    ["Average", f"{timing['average']:.1f}s"],
                    ["Minimum", f"{timing['min']:.1f}s"],
                    ["Maximum", f"{timing['max']:.1f}s"]
                ]

                print("\nTiming (successful evacuations):")
                print(tabulate(timing_table, tablefmt="grid"))

            print("\n" + "=" * 60)

        except ImportError:
            self.print_text_report(report)

    def save_report_to_file(self, report: dict):
        """
        Save report to JSON file.

        Args:
            report: Report data
        """
        try:
            with open(self.config['results_file'], 'w') as f:
                json.dump(report, f, indent=2)
            logging.info(f"Report saved to: {self.config['results_file']}")
        except Exception as e:
            logging.error(f"Failed to save report: {e}")

    def dry_run(self) -> bool:
        """
        Perform dry-run validation only.

        Returns:
            bool: True if validation passed
        """
        logging.info("=== DRY-RUN VALIDATION ===")

        # Validate host
        if not self.validate_host():
            logging.error("❌ Host validation failed")
            return False

        # Validate VMs
        if not self.validate_vms():
            logging.error("❌ VM validation failed")
            return False

        # Validate target hosts
        if not self.validate_target_hosts():
            logging.error("❌ Target hosts validation failed")
            return False

        logging.info("\n✅ DRY-RUN: All checks passed")
        self.show_recommendations()

        return True

    def real_evacuation(self) -> bool:
        """
        Perform real evacuation.

        Returns:
            bool: True if evacuation completed
        """
        logging.info("=== STARTING EVACUATION ===")

        # Record start time
        self.start_time = time.time()

        # Validate environment
        if not self.validate_host():
            return False
        if not self.validate_vms():
            return False
        if not self.validate_target_hosts():
            return False

        # Check if host is actually down or force is needed
        if self.failed_host_info.state == 'up':
            if not self.config['force_host_down']:
                logging.error("ERROR: Host is UP but --force-host-down not specified")
                logging.error("Evacuation requires host to be DOWN")
                logging.error("Either ensure host is actually down or use --force-host-down")
                return False
            else:
                logging.warning("Host is UP, using --force-host-down to simulate failure")

        try:
            self.force_host_down()

        except SystemExit:
            raise
        except Exception as e:
            logging.error(f"Failed during host disable: {e}")
            return False

        # Execute evacuation
        results = self.execute_evacuation()

        # Restore host if requested
        self.restore_host()

        # Record end time
        self.end_time = time.time()

        # Create report
        self.create_report(results)

        # Check if any evacuations succeeded
        successful = any(r['success'] for r in results)

        if successful:
            logging.info("✅ Evacuation completed")
            return True
        else:
            logging.error("❌ Evacuation failed - no VMs were evacuated")
            return False

    def run(self) -> bool:
        """
        Main execution method.

        Returns:
            bool: True if operation succeeded
        """
        try:
            # Connect to OpenStack
            self.connect()

            # Run dry-run or real evacuation
            if self.config['dry_run']:
                return self.dry_run()
            else:
                return self.real_evacuation()

        except Exception as e:
            logging.error(f"Operation failed: {e}")
            return False


def main():
    """Main entry point."""
    # Parse arguments
    args = parse_arguments()
    config = get_config(args)

    # Setup logging
    setup_logging(config['log_level'])

    # Create and run tester
    tester = SimpleEvacuationTester(config)
    success = tester.run()

    # Exit with appropriate code
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()