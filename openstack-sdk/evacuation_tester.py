#!/usr/bin/env python3
"""
OpenStack Evacuation Test Script

Performs evacuation testing of VMs from a failed hypervisor to available hosts.
Measures recovery times, success rates, and provides detailed DR metrics.
"""

import openstack
import argparse
import logging
import os
import sys
import time
import json
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Any
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime


def parse_arguments() -> argparse.Namespace:
    """
    Parse command line arguments for evacuation testing.

    Returns:
        argparse.Namespace: Parsed command line arguments
    """
    parser = argparse.ArgumentParser(
        description='OpenStack Hypervisor Evacuation Test',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --failed-host compute-01
  %(prog)s --failed-host compute-01 --target-hosts compute-02,compute-03
  %(prog)s --failed-host compute-01 --force-host-down --dry-run
        """
    )

    # Required parameters
    parser.add_argument(
        '--failed-host',
        required=True,
        help='Hypervisor host to evacuate VMs from (required)'
    )

    # OpenStack connection
    parser.add_argument(
        '--cloud',
        default=None,
        help='OpenStack cloud name from clouds.yaml (optional)'
    )
    parser.add_argument(
        '--interface',
        choices=['public', 'internal', 'admin'],
        default='public',
        help='OpenStack endpoint interface'
    )
    parser.add_argument(
        '--region-name',
        help='OpenStack region name'
    )

    # Host filtering and constraints
    parser.add_argument(
        '--target-hosts',
        help='Comma-separated list of allowed target hosts for evacuation'
    )
    parser.add_argument(
        '--exclude-hosts',
        help='Comma-separated list of hosts to exclude from evacuation targets'
    )
    parser.add_argument(
        '--availability-zone',
        help='Restrict evacuation to hosts in this availability zone'
    )
    parser.add_argument(
        '--project-id',
        help='Only evacuate VMs from this specific project'
    )

    # Test execution parameters
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
        help='Timeout per VM evacuation in seconds (default: 300)'
    )

    # Evacuation control flags
    parser.add_argument(
        '--force-host-down',
        action='store_true',
        help='Force host into down state before testing (simulate failure)'
    )
    parser.add_argument(
        '--on-shared-storage',
        action='store_true',
        help='Indicate that shared storage is used for evacuation'
    )
    parser.add_argument(
        '--restore-after-test',
        action='store_true',
        help='Restore host to enabled state after test completion'
    )

    # Output and logging
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
        help='Validate environment without actual evacuation'
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
    Build final configuration with priority:
    Command Line > Environment Variables > Default Values

    Returns:
        dict: Configuration dictionary
    """
    config = {
        # Required parameters
        'failed_host': args.failed_host,

        # OpenStack connection
        'cloud_name': args.cloud or os.getenv('OS_CLOUD'),
        'interface': args.interface,
        'region_name': args.region_name or os.getenv('OS_REGION_NAME'),

        # Host constraints
        'target_hosts': args.target_hosts,
        'exclude_hosts': args.exclude_hosts,
        'availability_zone': args.availability_zone,
        'project_id': args.project_id,

        # Test execution
        'max_parallel': args.max_parallel,
        'evacuation_timeout': args.evacuation_timeout,
        'per_vm_timeout': args.per_vm_timeout,

        # Control flags
        'force_host_down': args.force_host_down,
        'on_shared_storage': args.on_shared_storage,
        'restore_after_test': args.restore_after_test,
        'dry_run': args.dry_run,

        # Output
        'log_level': args.log_level,
        'output_format': args.output_format,
        'results_file': args.results_file,
    }

    return config


def setup_logging(log_level: str):
    """
    Configure logging with timestamp and level.

    Args:
        log_level: Logging level string
    """
    logging.basicConfig(
        level=getattr(logging, log_level),
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%H:%M:%S'
    )


@dataclass
class VMResult:
    """Individual VM evacuation result"""
    vm_id: str
    vm_name: str
    original_host: str
    target_host: Optional[str] = None
    status_before: str = 'UNKNOWN'
    status_after: str = 'UNKNOWN'
    evacuation_time: float = 0.0
    success: bool = False
    error_message: Optional[str] = None
    start_time: Optional[float] = None
    end_time: Optional[float] = None


@dataclass
class EvacuationStats:
    """Statistics storage for evacuation test"""
    # Core metrics
    total_vms_found: int = 0
    vms_evacuated: int = 0
    vms_failed: int = 0
    vms_skipped: int = 0

    # Timing
    total_duration: float = 0.0
    start_time: Optional[float] = None
    end_time: Optional[float] = None
    time_to_first_vm_up: float = 0.0
    time_to_last_vm_up: float = 0.0

    # Recovery times
    recovery_times: List[float] = field(default_factory=list)

    # Calculated metrics
    success_rate: float = 0.0
    avg_recovery_time: float = 0.0
    median_recovery_time: float = 0.0
    p95_recovery_time: float = 0.0
    p99_recovery_time: float = 0.0
    max_recovery_time: float = 0.0

    # Distribution
    vm_distribution: Dict[str, int] = field(default_factory=dict)

    # Detailed results
    vm_results: List[VMResult] = field(default_factory=list)


class EvacuationTester:
    """Main evacuation test controller"""

    def __init__(self, config: dict):
        self.config = config
        self.conn = None
        self.stats = EvacuationStats()
        self.failed_host_vms = []
        self.original_host_state = None

    def connect_openstack(self):
        """
        Establish connection to OpenStack using clouds.yaml or environment variables.

        Raises:
            Exception: If connection fails
        """
        try:
            if self.config['cloud_name']:
                self.conn = openstack.connect(
                    cloud=self.config['cloud_name'],
                    interface=self.config['interface'],
                    region_name=self.config['region_name']
                )
                logging.info(f"Connected via clouds.yaml, cloud: {self.config['cloud_name']}")
            else:
                self.conn = openstack.connect()
                logging.info("Connected via environment variables")

            # Test authentication
            self.conn.authorize()
            logging.info("Authentication successful")

        except Exception as e:
            logging.error(f"Connection failed: {e}")
            raise

    def validate_environment(self):
        """
        Validate OpenStack environment for evacuation testing.

        Checks:
        - Failed host exists
        - Target hosts availability
        - Compute service status

        Raises:
            Exception: If validation fails
        """
        try:
            logging.info("Validating OpenStack environment...")

            # Check if failed host exists (by name)
            try:
                failed_host = self._get_hypervisor_by_name(self.config['failed_host'])
                logging.info(
                    f"Found failed host: {failed_host.name} (State: {failed_host.state}, Status: {failed_host.status})")

                # Store original state if we need to restore
                self.original_host_state = {
                    'state': failed_host.state,
                    'status': failed_host.status,
                    'host': failed_host.name
                }

            except Exception as e:
                logging.error(f"Failed host {self.config['failed_host']} not found: {e}")
                raise

            # Check compute service status for failed host
            failed_host_services = self._get_hypervisor_services(self.config['failed_host'])
            if not failed_host_services:
                logging.warning(f"No compute services found for host {self.config['failed_host']}")
            else:
                for service in failed_host_services:
                    logging.info(f"Service state: {service.host}:{service.binary} = {service.state}/{service.status}")

            # Check available hosts for evacuation
            hypervisors = list(self.conn.compute.hypervisors())
            available_hosts = []

            for hyp in hypervisors:
                if (hyp.name != self.config['failed_host'] and
                        hyp.state == 'up' and
                        hyp.status == 'enabled'):

                    # Apply filters if specified
                    if self.config['target_hosts'] and hyp.name not in self.config['target_hosts']:
                        continue
                    if self.config['exclude_hosts'] and hyp.name in self.config['exclude_hosts']:
                        continue

                    # Check if host has active compute service
                    host_services = self._get_hypervisor_services(hyp.name)
                    active_services = [s for s in host_services if s.state == 'up' and s.status == 'enabled']

                    if active_services:
                        available_hosts.append(hyp.name)
                        logging.debug(f"Available target: {hyp.name} (State: {hyp.state}, Status: {hyp.status})")
                    else:
                        logging.debug(f"Skipping {hyp.name}: no active compute service")

            if not available_hosts:
                raise Exception("No available target hosts with active compute services found for evacuation")

            logging.info(f"Available target hosts ({len(available_hosts)}): {', '.join(available_hosts)}")

            # Check overall compute service status
            services = list(self.conn.compute.services())
            active_services = [s for s in services if s.state == 'up' and s.status == 'enabled']

            if not active_services:
                raise Exception("No active compute services found in the cloud")

            logging.info(f"Active compute services in cloud: {len(active_services)}")
            logging.info("Environment validation completed successfully")

        except Exception as e:
            logging.error(f"Environment validation failed: {e}")
            raise

    def prepare_failed_host(self):
        """
        Prepare the failed host for evacuation testing.

        If --force-host-down is specified, disable the host to simulate failure.
        """
        if not self.config['force_host_down']:
            logging.info(f"Using host {self.config['failed_host']} in current state")
            return

        try:
            logging.info(f"Forcing host {self.config['failed_host']} into down state...")

            # Get compute service for the host
            services = self._get_hypervisor_services(self.config['failed_host'])
            if not services:
                raise Exception(f"No compute service found for host {self.config['failed_host']}")

            # Disable compute service
            service = services[0]  # Usually there's one compute service per host
            self.conn.compute.disable_service(
                self.config['failed_host'],
                'nova-compute',
                reason='Evacuation testing'
            )

            logging.info(f"Host {self.config['failed_host']} disabled for evacuation testing")

        except Exception as e:
            logging.error(f"Failed to disable host: {e}")
            raise

    def restore_host(self):
        """
        Restore host to original state after testing.

        Only executed if --restore-after-test is specified.
        """
        if not self.config['restore_after_test']:
            return

        try:
            logging.info(f"Restoring host {self.config['failed_host']}...")

            # Enable compute service
            self.conn.compute.enable_service(
                self.config['failed_host'],
                'nova-compute'
            )

            logging.info(f"Host {self.config['failed_host']} restored to enabled state")

        except Exception as e:
            logging.error(f"Failed to restore host: {e}")

    def discover_vms_on_failed_host(self):
        """
        Discover VMs on the failed host.

        Returns:
            List: VMs found on the failed host
        """
        try:
            logging.info(f"Discovering VMs on failed host: {self.config['failed_host']}")

            all_servers = list(self.conn.compute.servers(all_projects=True))
            failed_host_vms = []

            for server in all_servers:
                server_host = getattr(server, 'hypervisor_hostname', None)

                # Check if VM is on the failed host
                if not self._is_vm_on_host(server, self.config['failed_host']):
                    continue

                # Apply project filter if specified
                if (self.config['project_id'] and
                        getattr(server, 'project_id', None) != self.config['project_id']):
                    continue

                # Check VM status
                if server.status not in ['ACTIVE', 'SHUTOFF', 'ERROR']:
                    logging.debug(f"Skipping VM {server.name} with status {server.status}")
                    continue

                # Check if VM is evacuatable
                if not self._is_vm_evacuatable(server):
                    logging.warning(f"VM {server.name} may not be evacuatable")

                failed_host_vms.append(server)
                logging.debug(f"Found VM: {server.name} ({server.id}) - Status: {server.status}")

            if not failed_host_vms:
                raise Exception(f"No VMs found on host {self.config['failed_host']}")

            logging.info(f"Found {len(failed_host_vms)} VMs on failed host")
            return failed_host_vms

        except Exception as e:
            logging.error(f"VM discovery failed: {e}")
            raise

    def check_host_state(self, host_name: str) -> dict:
        """
        Check current state of a host.

        Args:
            host_name: Host name to check

        Returns:
            dict: Host state information
        """
        try:
            # Get hypervisor info
            hyp = self._get_hypervisor_by_name(host_name)

            # Get service info
            services = self._get_hypervisor_services(host_name)
            service_state = None
            service_status = None

            if services:
                service = services[0]
                service_state = service.state
                service_status = service.status

            return {
                'hypervisor': {
                    'name': hyp.name,
                    'state': hyp.state,
                    'status': hyp.status,
                    'vcpus': hyp.vcpus,
                    'memory_mb': hyp.memory_mb,
                    'local_gb': hyp.local_gb
                },
                'service': {
                    'state': service_state,
                    'status': service_status
                } if services else None
            }

        except Exception as e:
            logging.error(f"Error checking host state for {host_name}: {e}")
            return None

    @staticmethod
    def _is_vm_on_host(server, host_name):
        """
        Check if VM is on specified host with flexible matching.

        Args:
            server: Server object
            host_name: Host name to check against

        Returns:
            bool: True if VM is on the host
        """
        server_host = getattr(server, 'hypervisor_hostname', None)

        if not server_host:
            return False

        # Exact match
        if server_host == host_name:
            return True

        # Case-insensitive match
        if server_host.lower() == host_name.lower():
            return True

        # Hostname vs FQDN match (compute-01 vs compute-01.domain.local)
        if ('.' in server_host and
                server_host.split('.')[0] == host_name):
            return True

        # Check host aggregates or other metadata
        if hasattr(server, 'host') and server.host == host_name:
            return True

        return False

    def _get_hypervisor_by_name(self, host_name: str):
        """
        Get hypervisor by host name (not UUID).

        Args:
            host_name: Host name to search for

        Returns:
            Hypervisor object

        Raises:
            Exception: If hypervisor not found
        """
        try:
            hypervisors = list(self.conn.compute.hypervisors())
            for hyp in hypervisors:
                if hyp.name == host_name:
                    return hyp

            raise Exception(f"Hypervisor '{host_name}' not found")

        except Exception as e:
            logging.error(f"Error finding hypervisor {host_name}: {e}")
            raise

    def _get_hypervisor_services(self, host_name: str):
        """
        Get compute services for a specific host.

        Args:
            host_name: Host name to get services for

        Returns:
            List of service objects
        """
        try:
            services = list(self.conn.compute.services())
            host_services = []

            for service in services:
                if service.host == host_name and service.binary == 'nova-compute':
                    host_services.append(service)

            return host_services

        except Exception as e:
            logging.error(f"Error getting services for {host_name}: {e}")
            return []

    def _debug_host_matching(self):
        """
        Debug method to help identify host matching issues.
        """
        logging.debug("Debugging host matching...")

        all_servers = list(self.conn.compute.servers(all_projects=True, limit=50))

        unique_hosts = set()
        for server in all_servers:
            host = getattr(server, 'hypervisor_hostname', None)
            if host:
                unique_hosts.add(host)

        logging.debug(f"Found {len(unique_hosts)} unique hypervisor hosts in VMs:")
        for host in sorted(unique_hosts):
            logging.debug(f"  - {host}")

        target = self.config['failed_host']
        similar = [h for h in unique_hosts
                   if target.lower() in h.lower() or h.lower() in target.lower()]

        if similar:
            logging.info(f"Similar host names found: {similar}")
            logging.info(f"Try using one of these names instead of '{target}'")

    @staticmethod
    def _is_vm_evacuatable(server) -> bool:
        """
        Check if VM is suitable for evacuation.

        Args:
            server: Server object to check

        Returns:
            bool: True if VM can be evacuated
        """
        # Basic checks
        if server.status not in ['ACTIVE', 'SHUTOFF', 'ERROR']:
            return False

        # Check for non-migratable resources
        if hasattr(server, 'pci_devices') and server.pci_devices:
            logging.debug(f"VM {server.name} has PCI devices, evacuation may be limited")
            return False

        return True

    def evacuate_vm(self, vm_result: VMResult) -> VMResult:
        """
        Evacuate a single VM from failed host.

        Args:
            vm_result: VMResult object with VM information

        Returns:
            VMResult: Updated with evacuation result
        """
        start_time = time.time()
        vm_result.start_time = start_time

        try:
            logging.info(f"Starting evacuation: {vm_result.vm_name}")

            # Get current server object
            server = self.conn.compute.get_server(vm_result.vm_id)

            # Store original status
            vm_result.status_before = server.status

            # Prepare evacuation parameters
            evacuate_params = {
                'server': server.id,
                'force': self.config['force_host_down'],
            }

            # Add shared storage flag if specified
            if self.config['on_shared_storage']:
                evacuate_params['on_shared_storage'] = True

            # Add host if specified in target hosts
            if (self.config['target_hosts'] and
                    len(self.config['target_hosts']) == 1):
                evacuate_params['host'] = self.config['target_hosts'][0]

            # Execute evacuation
            self.conn.compute.evacuate_server(**evacuate_params)

            # Monitor evacuation progress
            success, target_host, error_msg = self.monitor_evacuation(
                server,
                self.config['per_vm_timeout']
            )

            evacuation_time = time.time() - start_time
            vm_result.end_time = time.time()
            vm_result.evacuation_time = evacuation_time
            vm_result.success = success
            vm_result.target_host = target_host

            if success:
                vm_result.status_after = 'ACTIVE'
                logging.info(f"Evacuation successful: {vm_result.vm_name} → {target_host} ({evacuation_time:.2f}s)")
            else:
                vm_result.status_after = 'ERROR'
                vm_result.error_message = error_msg
                logging.error(f"Evacuation failed: {vm_result.vm_name} - {error_msg}")

            return vm_result

        except openstack.exceptions.ConflictException as e:
            evacuation_time = time.time() - start_time
            vm_result.end_time = time.time()
            vm_result.evacuation_time = evacuation_time
            vm_result.success = False
            vm_result.error_message = f"Conflict: {e}"
            logging.error(f"Evacuation conflict: {vm_result.vm_name} - {e}")
            return vm_result

        except Exception as e:
            evacuation_time = time.time() - start_time
            vm_result.end_time = time.time()
            vm_result.evacuation_time = evacuation_time
            vm_result.success = False
            vm_result.error_message = f"Unexpected error: {e}"
            logging.error(f"Evacuation error: {vm_result.vm_name} - {e}")
            return vm_result

    def monitor_evacuation(self, server, timeout: int):
        """
        Monitor evacuation status until completion or timeout.

        Args:
            server: Server object to monitor
            timeout: Maximum monitoring time in seconds

        Returns:
            tuple: (success: bool, target_host: str or None, error_message: str or None)
        """
        start_time = time.time()
        last_host = getattr(server, 'hypervisor_hostname', None)

        try:
            logging.debug(f"Monitoring evacuation: {server.name}")

            while time.time() - start_time < timeout:
                # Refresh server data
                server = self.conn.compute.get_server(server.id)
                current_host = getattr(server, 'hypervisor_hostname', None)

                # Check if VM moved to a different host
                if current_host and current_host != last_host:
                    logging.info(f"VM {server.name} moved to {current_host}")
                    return True, current_host, None

                # Check VM status
                if server.status == 'ACTIVE':
                    # VM is active but still on same host
                    if current_host == last_host:
                        return False, None, "VM did not move to different host"
                    else:
                        return True, current_host, None
                elif server.status == 'ERROR':
                    return False, None, f"VM entered ERROR state"
                elif server.status == 'SHUTOFF':
                    return False, None, f"VM is SHUTOFF, evacuation may have failed"

                # Wait before next check
                time.sleep(2)

            # Timeout reached
            return False, None, f"Evacuation timeout after {timeout} seconds"

        except Exception as e:
            return False, None, f"Monitoring error: {e}"

    def run_evacuation(self):
        """
        Execute evacuation of all VMs from failed host.
        """
        try:
            logging.info(f"Starting evacuation from host: {self.config['failed_host']}")

            # Prepare VM results
            vm_results = []
            for server in self.failed_host_vms:
                vm_result = VMResult(
                    vm_id=server.id,
                    vm_name=server.name,
                    original_host=self.config['failed_host'],
                    status_before=server.status
                )
                vm_results.append(vm_result)

            self.stats.vm_results = vm_results
            self.stats.total_vms_found = len(vm_results)

            # Record start time
            self.stats.start_time = time.time()
            evacuation_start = self.stats.start_time

            # Track first successful VM time
            first_vm_time = None

            # Execute evacuations in parallel
            workers = min(self.config['max_parallel'], len(vm_results))
            logging.info(f"Executing {len(vm_results)} evacuations with {workers} parallel workers")

            with ThreadPoolExecutor(max_workers=workers) as executor:
                # Submit all evacuation tasks
                future_to_vm = {
                    executor.submit(self.evacuate_vm, vm_result): vm_result
                    for vm_result in vm_results
                }

                # Collect results
                for future in as_completed(future_to_vm):
                    vm_result = future_to_vm[future]
                    try:
                        updated_result = future.result()

                        # Update statistics
                        if updated_result.success:
                            self.stats.vms_evacuated += 1
                            self.stats.recovery_times.append(updated_result.evacuation_time)

                            # Track time to first successful VM
                            if first_vm_time is None:
                                first_vm_time = updated_result.evacuation_time
                                self.stats.time_to_first_vm_up = first_vm_time

                            # Update VM distribution
                            if updated_result.target_host:
                                host = updated_result.target_host
                                self.stats.vm_distribution[host] = self.stats.vm_distribution.get(host, 0) + 1

                        else:
                            self.stats.vms_failed += 1
                            self.stats.vm_distribution['FAILED'] = self.stats.vm_distribution.get('FAILED', 0) + 1

                    except Exception as e:
                        logging.error(f"Error processing evacuation result: {e}")
                        self.stats.vms_failed += 1
                        self.stats.vm_distribution['FAILED'] = self.stats.vm_distribution.get('FAILED', 0) + 1

            # Record end time and calculate duration
            self.stats.end_time = time.time()
            self.stats.total_duration = self.stats.end_time - self.stats.start_time

            # Calculate time to last VM up
            successful_times = [r.evacuation_time for r in vm_results if r.success]
            if successful_times:
                self.stats.time_to_last_vm_up = max(successful_times)

            # Calculate statistics
            self.calculate_statistics()

            logging.info(f"Evacuation completed in {self.stats.total_duration:.2f}s")
            logging.info(f"Results: {self.stats.vms_evacuated} succeeded, {self.stats.vms_failed} failed")

        except Exception as e:
            logging.error(f"Evacuation execution failed: {e}")
            raise

    def calculate_statistics(self):
        """
        Calculate comprehensive statistics from evacuation results.
        """
        try:
            logging.info("Calculating evacuation statistics...")

            # Success rate
            total_processed = self.stats.vms_evacuated + self.stats.vms_failed
            if total_processed > 0:
                self.stats.success_rate = (self.stats.vms_evacuated / total_processed) * 100
            else:
                self.stats.success_rate = 0.0

            # Recovery time statistics
            if self.stats.recovery_times:
                sorted_times = sorted(self.stats.recovery_times)

                # Basic statistics
                self.stats.avg_recovery_time = sum(sorted_times) / len(sorted_times)
                self.stats.max_recovery_time = max(sorted_times)

                # Percentiles
                if len(sorted_times) >= 2:
                    median_idx = int(len(sorted_times) * 0.50)
                    p95_idx = int(len(sorted_times) * 0.95)
                    p99_idx = int(len(sorted(sorted_times) * 0.99))

                    self.stats.median_recovery_time = sorted_times[median_idx]
                    self.stats.p95_recovery_time = sorted_times[min(p95_idx, len(sorted_times) - 1)]
                    self.stats.p99_recovery_time = sorted_times[min(p99_idx, len(sorted_times) - 1)]
                else:
                    # Single VM case
                    self.stats.median_recovery_time = sorted_times[0]
                    self.stats.p95_recovery_time = sorted_times[0]
                    self.stats.p99_recovery_time = sorted_times[0]

            logging.info("Statistics calculation completed")

        except Exception as e:
            logging.error(f"Statistics calculation failed: {e}")
            raise

    def generate_report(self):
        """
        Generate report only if we have actual data.
        """
        if self.stats.total_vms_found == 0:
            logging.warning("No VMs found, skipping report generation")
            return

        try:
            logging.info("Generating evacuation test report...")

            report_data = self._prepare_report_data()

            # Output based on configured format
            if self.config['output_format'] == 'json':
                self._generate_json_report(report_data)
            elif self.config['output_format'] == 'table':
                self._generate_table_report(report_data)
            else:  # text
                self._generate_text_report(report_data)

            # Save to file
            self._save_report_to_file(report_data)

            logging.info("Report generation completed successfully")

        except Exception as e:
            logging.error(f"Report generation failed: {e}")
            raise

    def _prepare_report_data(self) -> dict:
        """Prepare report data structure."""

        # Convert VM results to serializable format
        vm_details = []
        for vm_result in self.stats.vm_results:
            vm_details.append({
                'vm_id': vm_result.vm_id,
                'vm_name': vm_result.vm_name,
                'original_host': vm_result.original_host,
                'target_host': vm_result.target_host,
                'status_before': vm_result.status_before,
                'status_after': vm_result.status_after,
                'evacuation_time_seconds': round(vm_result.evacuation_time, 2),
                'success': vm_result.success,
                'error_message': vm_result.error_message
            })

        report_data = {
            'evacuation_summary': {
                'failed_host': self.config['failed_host'],
                'start_time': datetime.fromtimestamp(
                    self.stats.start_time).isoformat() if self.stats.start_time else None,
                'end_time': datetime.fromtimestamp(self.stats.end_time).isoformat() if self.stats.end_time else None,
                'total_evacuation_time_seconds': round(self.stats.total_duration, 2),
                'total_vms_found': self.stats.total_vms_found,
                'vms_evacuated': self.stats.vms_evacuated,
                'vms_failed': self.stats.vms_failed,
                'success_rate_percent': round(self.stats.success_rate, 2)
            },
            'time_metrics': {
                'time_to_first_vm_up_seconds': round(self.stats.time_to_first_vm_up, 2),
                'time_to_last_vm_up_seconds': round(self.stats.time_to_last_vm_up, 2),
                'average_recovery_time_seconds': round(self.stats.avg_recovery_time, 2),
                'median_recovery_time_seconds': round(self.stats.median_recovery_time, 2),
                'p95_recovery_time_seconds': round(self.stats.p95_recovery_time, 2),
                'p99_recovery_time_seconds': round(self.stats.p99_recovery_time, 2),
                'max_recovery_time_seconds': round(self.stats.max_recovery_time, 2)
            },
            'vm_distribution': {
                'original_host': {
                    self.config['failed_host']: self.stats.total_vms_found
                },
                'after_evacuation': self.stats.vm_distribution
            },
            'vm_details': vm_details,
            'test_configuration': {
                'failed_host': self.config['failed_host'],
                'target_hosts': self.config['target_hosts'],
                'exclude_hosts': self.config['exclude_hosts'],
                'availability_zone': self.config['availability_zone'],
                'project_id': self.config['project_id'],
                'max_parallel': self.config['max_parallel'],
                'force_host_down': self.config['force_host_down'],
                'on_shared_storage': self.config['on_shared_storage'],
                'evacuation_timeout': self.config['evacuation_timeout'],
                'per_vm_timeout': self.config['per_vm_timeout']
            }
        }

        return report_data

    def _generate_json_report(self, report_data: dict):
        """Generate report in JSON format."""
        print(json.dumps(report_data, indent=2))

    def _generate_table_report(self, report_data: dict):
        """Generate report in table format."""
        try:
            from tabulate import tabulate

            print("\n" + "=" * 60)
            print("           OPENSTACK EVACUATION TEST REPORT           ")
            print("=" * 60)

            # Evacuation Summary
            summary = report_data['evacuation_summary']
            summary_table = [
                ["Failed Host", summary['failed_host']],
                ["Total Evacuation Time", f"{summary['total_evacuation_time_seconds']}s"],
                ["Total VMs Found", summary['total_vms_found']],
                ["VMs Evacuated", f"{summary['vms_evacuated']} ({summary['success_rate_percent']}%)"],
                ["VMs Failed", summary['vms_failed']]
            ]
            print("\n📊 EVACUATION SUMMARY:")
            print(tabulate(summary_table, tablefmt="grid"))

            # Time Metrics
            time_metrics = report_data['time_metrics']
            time_table = [
                ["Time to First VM Up", f"{time_metrics['time_to_first_vm_up_seconds']}s"],
                ["Time to Last VM Up", f"{time_metrics['time_to_last_vm_up_seconds']}s"],
                ["Average Recovery Time", f"{time_metrics['average_recovery_time_seconds']}s"],
                ["Median Recovery Time", f"{time_metrics['median_recovery_time_seconds']}s"],
                ["Max Recovery Time", f"{time_metrics['max_recovery_time_seconds']}s"]
            ]
            print("\n⏱️ RECOVERY TIME METRICS:")
            print(tabulate(time_table, tablefmt="grid"))

            # Percentiles Table
            percentiles_table = [
                ["P50 (Median)", f"{time_metrics['median_recovery_time_seconds']}s"],
                ["P95", f"{time_metrics['p95_recovery_time_seconds']}s"],
                ["P99", f"{time_metrics['p99_recovery_time_seconds']}s"],
                ["Maximum", f"{time_metrics['max_recovery_time_seconds']}s"]
            ]
            print("\n📈 RECOVERY TIME PERCENTILES:")
            print(tabulate(percentiles_table, tablefmt="grid"))

            # VM Distribution
            dist = report_data['vm_distribution']['after_evacuation']
            if dist:
                dist_table = []
                for host, count in dist.items():
                    dist_table.append([host, count])

                print("\n🎯 VM DISTRIBUTION AFTER EVACUATION:")
                print(tabulate(dist_table, headers=["Host", "VMs"], tablefmt="grid"))

            print("\n" + "=" * 60)

        except ImportError:
            self._generate_text_report(report_data)

    def _generate_text_report(self, report_data: dict):
        """Generate report in text format."""
        summary = report_data['evacuation_summary']
        time_metrics = report_data['time_metrics']
        dist = report_data['vm_distribution']['after_evacuation']

        print("\n" + "=" * 60)
        print("OPENSTACK EVACUATION TEST REPORT")
        print("=" * 60)

        print(f"\n📊 EVACUATION SUMMARY:")
        print(f"  Failed Host: {summary['failed_host']}")
        print(f"  Total Duration: {summary['total_evacuation_time_seconds']}s")
        print(f"  Total VMs: {summary['total_vms_found']}")
        print(f"  Evacuated: {summary['vms_evacuated']} ({summary['success_rate_percent']}%)")
        print(f"  Failed: {summary['vms_failed']}")

        print(f"\n⏱️ RECOVERY TIME METRICS:")
        print(f"  Time to First VM Up: {time_metrics['time_to_first_vm_up_seconds']}s")
        print(f"  Time to Last VM Up: {time_metrics['time_to_last_vm_up_seconds']}s")
        print(f"  Average: {time_metrics['average_recovery_time_seconds']}s")
        print(f"  Median: {time_metrics['median_recovery_time_seconds']}s")
        print(f"  P95: {time_metrics['p95_recovery_time_seconds']}s")
        print(f"  P99: {time_metrics['p99_recovery_time_seconds']}s")
        print(f"  Max: {time_metrics['max_recovery_time_seconds']}s")

        if dist:
            print(f"\n🎯 VM DISTRIBUTION:")
            for host, count in dist.items():
                print(f"  {host}: {count} VMs")

        print("\n" + "=" * 60)

    def _save_report_to_file(self, report_data: dict):
        """Save report to JSON file."""
        try:
            with open(self.config['results_file'], 'w') as f:
                json.dump(report_data, f, indent=2)
            logging.info(f"Report saved to: {self.config['results_file']}")
        except Exception as e:
            logging.error(f"Failed to save report: {e}")

    def dry_run(self):
        """
        Perform dry-run validation without actual evacuation.
        """
        try:
            logging.info("DRY-RUN: Starting validation")

            self.connect_openstack()
            self.validate_environment()

            if self.config['force_host_down']:
                logging.info("DRY-RUN: Would force host into down state")

            self.failed_host_vms = self.discover_vms_on_failed_host()

            if not self.failed_host_vms:
                logging.warning(f"⚠️ No VMs found on host {self.config['failed_host']}")
                logging.warning("Possible reasons:")
                logging.warning("  1. Host name mismatch (FQDN vs short name)")
                logging.warning("  2. No VMs actually on this host")
                logging.warning("  3. Hypervisor hostname not set for VMs")

                self._debug_host_matching()

                return False

            logging.info("✅ DRY-RUN: All checks passed")
            logging.info(f"📊 Summary: {len(self.failed_host_vms)} VMs would be evacuated")
            logging.info("💡 Use without --dry-run to start actual evacuation")

            # Generate dry-run report
            self.stats.total_vms_found = len(self.failed_host_vms)
            self.generate_report()

            return True

        except Exception as e:
            logging.error(f"❌ DRY-RUN: Validation failed - {e}")
            return False

    def run_test(self):
        """
        Main test execution method.
        """
        try:
            logging.info("Starting OpenStack Evacuation Test")

            # Setup and validation
            self.connect_openstack()
            self.validate_environment()

            # Prepare failed host if requested
            if self.config['force_host_down']:
                self.prepare_failed_host()

            # Discover VMs
            self.failed_host_vms = self.discover_vms_on_failed_host()

            # Check if it's a dry run
            if self.config['dry_run']:
                logging.info("Dry run completed successfully")
                return

            # Execute evacuation
            self.run_evacuation()

            # Restore host if requested
            if self.config['restore_after_test']:
                self.restore_host()

            # Generate final report
            self.generate_report()

            logging.info("Evacuation test completed successfully")

        except KeyboardInterrupt:
            logging.info("Test interrupted by user")
            if self.stats.start_time and not self.stats.end_time:
                self.stats.end_time = time.time()
                self.stats.total_duration = self.stats.end_time - self.stats.start_time
            self.generate_report()
            raise

        except Exception as e:
            logging.error(f"Test execution failed: {e}")
            if self.stats.start_time and not self.stats.end_time:
                self.stats.end_time = time.time()
                self.stats.total_duration = self.stats.end_time - self.stats.start_time
            self.generate_report()
            raise


def main():
    """Main entry point for evacuation test script."""
    try:
        # Parse arguments and build config
        args = parse_arguments()
        config = get_config(args)

        # Setup logging
        setup_logging(config['log_level'])

        # Create and run tester
        tester = EvacuationTester(config)
        tester.run_test()

    except KeyboardInterrupt:
        logging.info("Test interrupted by user")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Test failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
