#!/usr/bin/env python3
"""
OpenStack Live Migration Test Script
"""

import openstack
import argparse
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from tabulate import tabulate
from typing import List, Optional
from concurrent.futures import ThreadPoolExecutor, as_completed


def parse_arguments() -> argparse.Namespace:
    """
    Parse command line arguments with environment variable fallback.

    Returns:
        argparse.Namespace: Parsed command line arguments
    """
    parser = argparse.ArgumentParser(
        description='OpenStack Live Migration Performance Test'
    )

    # Migration target configuration
    parser.add_argument(
        '--hypervisors',
        help='Comma-separated list of hypervisor hosts for migration cycling'
    )

    # OpenStack connection configuration
    parser.add_argument(
        '--cloud',
        default='openstack',
        help='OpenStack cloud name from clouds.yaml (optional - uses env vars if not specified)'
    )

    # Test execution parameters
    parser.add_argument(
        '--duration',
        type=int,
        help='Total test duration in seconds (default: 3600)'
    )
    parser.add_argument(
        '--migration-timeout',
        type=int,
        help='Timeout for single migration in seconds (default: 300)'
    )
    parser.add_argument(
        '--max-parallel',
        type=int,
        help='Maximum parallel migrations (-1 for unlimited, default: 2)'
    )

    # Retry configuration
    parser.add_argument(
        '--retry-attempts',
        type=int,
        help='Number of retry attempts for failed migrations (default: 3)'
    )
    parser.add_argument(
        '--retry-delay',
        type=int,
        help='Delay between retry attempts in seconds (default: 10)'
    )

    # Output configuration
    parser.add_argument(
        '--log-level',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        help='Logging level (default: INFO)'
    )
    parser.add_argument(
        '--output-format',
        choices=['table', 'json', 'text'],
        help='Results output format (default: table)'
    )
    parser.add_argument(
        '--results-file',
        help='Path to save results JSON file (default: migration_results.json)'
    )

    parser.add_argument(
        '--interface',
        choices=['public', 'internal', 'admin'],
        help='OpenStack endpoint interface (default: public)'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Validate environment without actual migration'
    )

    args = parser.parse_args()

    # Validate required parameters
    if not args.hypervisors and not os.getenv('MIGRATION_TEST_HYPERVISORS'):
        parser.error("Either --hypervisors or MIGRATION_TEST_HYPERVISORS required")

    return args


def get_config(args: argparse.Namespace) -> dict:
    """
    Build final configuration dictionary with priority:
    Command Line > Environment Variables > Default Values

    Cloud name is optional - None means use only environment variables
    """
    config = {
        # OpenStack connection settings (cloud_name can be None)
        'cloud_name': args.cloud or os.getenv('MIGRATION_TEST_CLOUD_NAME'),
        'region_name': os.getenv('OS_REGION_NAME'),
        'interface': args.interface or os.getenv('MIGRATION_TEST_INTERFACE', 'internal'),

        # Core test parameters
        'hypervisors': (args.hypervisors or os.getenv('MIGRATION_TEST_HYPERVISORS')).split(','),
        'duration': args.duration or int(os.getenv('MIGRATION_TEST_DURATION', 3600)),
        'migration_timeout': args.migration_timeout or int(os.getenv('MIGRATION_TEST_MIGRATION_TIMEOUT', 300)),

        # Parallel execution settings (define by vms qty)
        'max_parallel': args.max_parallel or int(os.getenv('MIGRATION_TEST_MAX_PARALLEL_MIGRATIONS', 2)),

        # Retry configuration
        'retry_attempts': args.retry_attempts or int(os.getenv('MIGRATION_TEST_RETRY_ATTEMPTS', 3)),
        'retry_delay': args.retry_delay or int(os.getenv('MIGRATION_TEST_RETRY_DELAY', 10)),

        # Output and logging
        'log_level': args.log_level or os.getenv('MIGRATION_TEST_LOG_LEVEL', 'INFO'),
        'output_format': args.output_format or os.getenv('MIGRATION_TEST_OUTPUT_FORMAT', 'table'),
        'results_file': args.results_file or os.getenv('MIGRATION_TEST_RESULTS_FILE', 'migration_results.json')
    }

    return config


def setup_logging(log_level: str):
    """Configure logging"""
    logging.basicConfig(
        level=getattr(logging, log_level),
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%H:%M:%S'
    )


# === Data Structures ===
@dataclass
class MigrationStats:
    """Statistics storage for migration test"""
    total_cycles: int = 0
    successful_migrations: int = 0
    failed_migrations: int = 0
    cycle_times: List[float] = field(default_factory=list)
    migration_times: List[float] = field(default_factory=list)
    total_duration: float = 0.0
    start_time: Optional[float] = None
    end_time: Optional[float] = None

    # Calculated metrics
    success_rate: float = 0.0
    avg_migration_time: float = 0.0
    min_migration_time: float = 0.0
    max_migration_time: float = 0.0
    avg_cycle_time: float = 0.0
    min_cycle_time: float = 0.0
    max_cycle_time: float = 0.0
    migrations_per_hour: float = 0.0
    cycles_per_hour: float = 0.0


# === Main Class ===
class MigrationTester:
    """Main migration test controller"""

    def __init__(self, config: dict):
        self.config = config
        self.conn = None
        self.stats = MigrationStats()
        self.vms = []

    def connect_openstack(self):
        """
        Establish connection to OpenStack using clouds.yaml if available,
        otherwise use environment variables only.
        """
        try:
            if self._clouds_yaml_exists():
                cloud_name = self.config['cloud_name'] or 'openstack'
                self.conn = openstack.connect(cloud=cloud_name)
                logging.info(f"✅ Connected via clouds.yaml, cloud: {cloud_name}")
            else:
                self.conn = openstack.connect()
                logging.info("✅ Connected via environment variables")

            # Test authentication
            token = self.conn.authorize()
            logging.info(f"🔑 Authentication successful, project: {self.conn.current_project_id}")

        except Exception as e:
            logging.error(f"❌ Connection failed: {e}")
            raise

    def validate_environment(self):
        """
        Validate OpenStack environment prerequisites for migration testing.

        Checks:
        - Hypervisor availability and status
        - Compute service health
        - Live migration support

        Raises:
            Exception: If environment validation fails
        """
        try:
            logging.info("🔍 Validating OpenStack environment...")

            # Check hypervisor availability
            hypervisors = list(self.conn.compute.hypervisors())
            available_hypervisors = {hyp.name for hyp in hypervisors
                                     if hyp.state == 'up' and hyp.status == 'enabled'}

            # Validate all target hypervisors are available
            missing_hypervisors = set(self.config['hypervisors']) - available_hypervisors
            if missing_hypervisors:
                raise Exception(f"Target hypervisors not found or not enabled: {missing_hypervisors}")

            logging.info(f"✅ All target hypervisors available: {self.config['hypervisors']}")

            # Check compute service status
            services = list(self.conn.compute.services())
            compute_services = {f"{s.host}:{s.binary}" for s in services
                                if s.state == 'up' and s.status == 'enabled'}

            if not compute_services:
                raise Exception("No active compute services found")

            logging.info(f"✅ Compute services active: {len(compute_services)} nodes")

            # Verify we have at least 2 hypervisors for migration
            if len(self.config['hypervisors']) < 2:
                raise Exception("At least 2 hypervisors required for migration testing")

            logging.info("✅ Environment validation completed successfully")

        except Exception as e:
            logging.error(f"❌ Environment validation failed: {e}")
            raise

    def discover_initial_vms(self):
        try:
            first_hypervisor = self.config['hypervisors'][0]
            logging.info(f"🔍 Discovering VMs on initial hypervisor: {first_hypervisor}")

            all_servers = list(self.conn.compute.servers(all_projects=True))
            suitable_servers = []

            for server in all_servers:
                # Check if server is on target hypervisor and active
                if (hasattr(server, 'hypervisor_hostname') and
                        server.hypervisor_hostname == first_hypervisor and
                        server.status == 'ACTIVE'):

                    # Check if VM is not locked (safe default if attribute doesn't exist)
                    is_locked = getattr(server, 'locked', False)
                    if not is_locked and MigrationTester._is_vm_migratable(server):
                        suitable_servers.append(server)
                        logging.debug(f"Found suitable VM: {server.name} (ID: {server.id})")

            if not suitable_servers:
                raise Exception(f"No suitable ACTIVE VMs found on hypervisor {first_hypervisor}")

            logging.info(f"✅ Found {len(suitable_servers)} VMs for migration testing")
            for server in suitable_servers:
                logging.info(f"   📦 {server.name} - {server.id}")

            return suitable_servers

        except Exception as e:
            logging.error(f"❌ VM discovery failed: {e}")
            raise

    @staticmethod
    def _clouds_yaml_exists() -> bool:
        """
        Check if clouds.yaml configuration file exists in standard locations.

        Returns:
            bool: True if clouds.yaml found, False otherwise
        """
        standard_paths = [
            # User-specific config
            os.path.expanduser('~/.config/openstack/clouds.yaml'),
            # System-wide config
            '/etc/openstack/clouds.yaml',
            # Current directory
            './clouds.yaml'
        ]

        for path in standard_paths:
            if os.path.exists(path):
                logging.debug(f"📁 Found clouds.yaml at: {path}")
                return True

        logging.debug("📁 clouds.yaml not found in standard locations")
        return False

    @staticmethod
    def _is_vm_migratable(server):
        """
        Check if VM is suitable for live migration.

        Args:
            server: Server object to check

        Returns:
            bool: True if VM can be live migrated
        """
        # Check VM is active
        if hasattr(server, 'vm_state') and server.vm_state != 'active':
            return False

        # Check if VM has PCI devices or other non-migratable resources
        if hasattr(server, 'pci_devices') and server.pci_devices:
            logging.debug(f"VM {server.name} has PCI devices, may not be migratable")
            return False

        # Check if VM has volume attachments (boot-from-volume)
        if hasattr(server, 'attached_volumes') and server.attached_volumes:
            return True

        # If no volume attachments, check old attribute
        if hasattr(server, 'volumes_attached') and server.volumes_attached:
            return True

        # No volumes found - VM likely has local disks
        logging.debug(f"VM {server.name} has no volume attachments, may not be migratable")
        return False

    def live_migrate_vm(self, server, target_host):
        """
        Perform live migration of a single VM to target hypervisor.

        Args:
            server: Server object to migrate
            target_host: Target hypervisor hostname

        Returns:
            tuple: (success: bool, migration_time: float, error_message: str)
        """
        start_time = time.time()

        try:
            logging.info(f"⏩ Starting live migration: {server.name} → {target_host}")

            # Initiate live migration
            migration = self.conn.compute.live_migrate_server(
                server=server.id,
                host=target_host,
                block_migration=False,  # Let OpenStack decide about block migration
                disk_over_commit=False
            )

            # Monitor migration progress
            success, error_msg = self.monitor_migration(server, self.config['migration_timeout'])
            migration_time = time.time() - start_time

            if success:
                logging.info(f"✅ Migration completed: {server.name} → {target_host} "
                             f"({migration_time:.2f}s)")
                return True, migration_time, None
            else:
                logging.error(f"❌ Migration failed: {server.name} → {target_host} - {error_msg}")
                return False, migration_time, error_msg

        except openstack.exceptions.ConflictException as e:
            migration_time = time.time() - start_time
            error_msg = f"Migration conflict: {e}"
            logging.error(f"❌ {error_msg}")
            return False, migration_time, error_msg

        except openstack.exceptions.SDKException as e:
            migration_time = time.time() - start_time
            error_msg = f"SDK error: {e}"
            logging.error(f"❌ {error_msg}")
            return False, migration_time, error_msg

        except Exception as e:
            migration_time = time.time() - start_time
            error_msg = f"Unexpected error: {e}"
            logging.error(f"❌ {error_msg}")
            return False, migration_time, error_msg

    def monitor_migration(self, server, timeout):
        """
        Monitor migration status until completion or timeout.

        Args:
            server: Server object to monitor
            timeout: Maximum monitoring time in seconds

        Returns:
            tuple: (success: bool, error_message: str)
        """
        start_time = time.time()

        try:
            logging.debug(f"👀 Monitoring migration status for: {server.name}")

            while time.time() - start_time < timeout:
                # Refresh server data to get current status
                server = self.conn.compute.get_server(server.id)

                # Check if migration is still in progress
                if hasattr(server, 'migration') and server.migration:
                    migration_status = server.migration.status
                    logging.debug(f"Migration status: {migration_status}")

                    if migration_status in ['completed', 'confirmed']:
                        return True, None
                    elif migration_status in ['error', 'failed']:
                        return False, f"Migration failed with status: {migration_status}"
                    # Continue monitoring for 'migrating', 'pre-migrating' etc.

                # Check server status as fallback
                if server.status == 'ACTIVE':
                    # Verify VM actually moved to new host
                    current_host = getattr(server, 'hypervisor_hostname', None)
                    if current_host and current_host != getattr(server, '_original_host', None):
                        return True, None
                    else:
                        return False, "VM did not change hypervisor after migration"

                elif server.status == 'ERROR':
                    return False, f"VM entered ERROR state during migration"

                # Wait before next check
                time.sleep(2)

            # Timeout reached
            return False, f"Migration timeout after {timeout} seconds"

        except Exception as e:
            error_msg = f"Monitoring error: {e}"
            logging.error(f"❌ {error_msg}")
            return False, error_msg

    def run_test_cycle(self):
        """
        Execute one complete migration cycle for all VMs in parallel.
        """
        cycle_start = time.time()
        cycle_success = True

        try:
            logging.info(f"🚀 Starting migration cycle {self.stats.total_cycles + 1}")

            # Calculate number of parallel workers
            if self.config['max_parallel'] == -1:
                workers = len(self.vms)  # Unlimited - all VMs in parallel
            else:
                workers = min(self.config['max_parallel'], len(self.vms))  # Limited

            logging.info(f"🔀 Executing {len(self.vms)} migrations with {workers} parallel workers")

            # Execute migrations in parallel
            with ThreadPoolExecutor(max_workers=workers) as executor:
                # Submit all migration tasks
                future_to_vm = {
                    executor.submit(self._migrate_single_vm, vm): vm
                    for vm in self.vms
                }

                # Collect results
                for future in as_completed(future_to_vm):
                    vm = future_to_vm[future]
                    try:
                        success, migration_time, error_msg = future.result()
                        if success:
                            self.stats.successful_migrations += 1
                            self.stats.migration_times.append(migration_time)
                            logging.info(f"✅ {vm.name} migrated in {migration_time:.2f}s")
                        else:
                            self.stats.failed_migrations += 1
                            cycle_success = False
                            logging.error(f"❌ {vm.name} failed: {error_msg}")
                    except Exception as e:
                        self.stats.failed_migrations += 1
                        cycle_success = False
                        logging.error(f"❌ {vm.name} failed with exception: {e}")

            # Refresh all VMs data after migrations
            self.vms = [self.conn.compute.get_server(vm.id) for vm in self.vms]

            # Update cycle statistics
            cycle_duration = time.time() - cycle_start
            self.stats.cycle_times.append(cycle_duration)
            self.stats.total_cycles += 1

            logging.info(
                f"🏁 Cycle {self.stats.total_cycles} completed in {cycle_duration:.2f}s - Success: {cycle_success}")
            return cycle_success

        except Exception as e:
            logging.error(f"❌ Cycle execution failed: {e}")
            self.stats.failed_migrations += len(self.vms)
            return False

    def _migrate_single_vm(self, vm):
        """
        Migrate single VM and return result.
        Helper method for parallel execution.
        """
        current_host = getattr(vm, 'hypervisor_hostname', 'unknown')
        next_host = self._get_next_hypervisor(current_host)

        logging.info(f"🔄 Migrating {vm.name} {current_host} → {next_host}")
        return self.live_migrate_vm(vm, next_host)

    def _get_next_hypervisor(self, current_host):
        """
        Get next hypervisor in round-robin sequence.

        Args:
            current_host: Current hypervisor hostname

        Returns:
            str: Next hypervisor hostname
        """
        hypervisors = self.config['hypervisors']

        try:
            current_index = hypervisors.index(current_host)
            next_index = (current_index + 1) % len(hypervisors)
            return hypervisors[next_index]
        except ValueError:
            # Current host not in target list, start from first
            return hypervisors[0]

    def dry_run(self):
        """
        Simple dry-run - only basic validation steps
        """
        try:
            logging.info("🔍 DRY-RUN: Starting basic validation")

            self.connect_openstack()
            self.validate_environment()
            self.vms = self.discover_initial_vms()

            logging.info("✅ DRY-RUN: All checks passed - migration should be possible")
            logging.info(f"📊 Summary: {len(self.vms)} VMs found on {self.config['hypervisors'][0]}")
            logging.info("💡 Use without --dry-run to start actual migration test")

            return True

        except Exception as e:
            logging.error(f"❌ DRY-RUN: Validation failed - {e}")
            return False

    def run_test(self):
        """
        Main test execution loop - runs migration cycles for specified duration.

        Coordinates the entire migration test process from start to finish.
        """
        try:
            logging.info("🎬 Starting OpenStack Live Migration Test")
            logging.info(f"⏱️  Test duration: {self.config['duration']} seconds")
            logging.info(f"🎯 Target hypervisors: {', '.join(self.config['hypervisors'])}")
            logging.info(f"📊 Max parallel migrations: {self.config['max_parallel']}")

            # Setup phase
            self.connect_openstack()
            self.validate_environment()
            self.vms = self.discover_initial_vms()

            # Record test start time
            test_start_time = time.time()
            self.stats.start_time = test_start_time

            logging.info(f"🔁 Starting migration cycles for {len(self.vms)} VMs")

            # Main test loop
            while time.time() - test_start_time < self.config['duration']:
                cycle_success = self.run_test_cycle()

                # Check if we should continue
                if not cycle_success and self.config['retry_attempts'] == 0:
                    logging.warning("⚠️  Cycle failed and no retries configured - stopping test")
                    break

                # Brief pause between cycles to avoid system overload
                time.sleep(5)

            # Record test end time
            self.stats.end_time = time.time()
            self.stats.total_duration = self.stats.end_time - self.stats.start_time

            # Generate final report
            self.calculate_statistics()
            self.generate_report()

            logging.info("🏁 Migration test completed successfully")

        except KeyboardInterrupt:
            logging.info("⏹️  Test interrupted by user")
            self.stats.end_time = time.time()
            self.stats.total_duration = self.stats.end_time - self.stats.start_time
            self.generate_report()
            raise

        except Exception as e:
            logging.error(f"💥 Test execution failed: {e}")
            self.stats.end_time = time.time()
            if self.stats.start_time:
                self.stats.total_duration = self.stats.end_time - self.stats.start_time
            self.generate_report()
            raise

    def calculate_statistics(self):
        """
        Calculate comprehensive statistics from migration test results.
        """
        try:
            logging.info("📊 Calculating test statistics...")

            # Basic counts
            total_migrations = self.stats.successful_migrations + self.stats.failed_migrations
            total_cycle_time = sum(self.stats.cycle_times) if self.stats.cycle_times else 0

            # Success rates
            if total_migrations > 0:
                self.stats.success_rate = (self.stats.successful_migrations / total_migrations) * 100
            else:
                self.stats.success_rate = 0.0

            # Migration time statistics
            if self.stats.migration_times:
                self.stats.avg_migration_time = sum(self.stats.migration_times) / len(self.stats.migration_times)
                self.stats.min_migration_time = min(self.stats.migration_times)
                self.stats.max_migration_time = max(self.stats.migration_times)
            else:
                self.stats.avg_migration_time = 0.0
                self.stats.min_migration_time = 0.0
                self.stats.max_migration_time = 0.0

            # Cycle time statistics
            if self.stats.cycle_times:
                self.stats.avg_cycle_time = sum(self.stats.cycle_times) / len(self.stats.cycle_times)
                self.stats.min_cycle_time = min(self.stats.cycle_times)
                self.stats.max_cycle_time = max(self.stats.cycle_times)
            else:
                self.stats.avg_cycle_time = 0.0
                self.stats.min_cycle_time = 0.0
                self.stats.max_cycle_time = 0.0

            # Performance metrics
            if self.stats.total_duration > 0:
                self.stats.migrations_per_hour = (total_migrations / self.stats.total_duration) * 3600
                self.stats.cycles_per_hour = (self.stats.total_cycles / self.stats.total_duration) * 3600
            else:
                self.stats.migrations_per_hour = 0.0
                self.stats.cycles_per_hour = 0.0

            logging.info("✅ Statistics calculation completed")

        except Exception as e:
            logging.error(f"❌ Statistics calculation failed: {e}")
            raise

    def generate_report(self):
        """
        Generate comprehensive test report in configured output format.

        Creates detailed report with statistics, performance metrics,
        and test summary for analysis.
        """
        try:
            logging.info("📈 Generating test report...")

            report_data = {
                'test_summary': {
                    'total_duration_seconds': round(self.stats.total_duration, 2),
                    'total_cycles': self.stats.total_cycles,
                    'total_migrations': self.stats.successful_migrations + self.stats.failed_migrations,
                    'successful_migrations': self.stats.successful_migrations,
                    'failed_migrations': self.stats.failed_migrations,
                    'success_rate_percent': round(self.stats.success_rate, 2)
                },
                'performance_metrics': {
                    'migrations_per_hour': round(self.stats.migrations_per_hour, 2),
                    'cycles_per_hour': round(self.stats.cycles_per_hour, 2),
                    'avg_migration_time_seconds': round(self.stats.avg_migration_time, 2),
                    'min_migration_time_seconds': round(self.stats.min_migration_time, 2),
                    'max_migration_time_seconds': round(self.stats.max_migration_time, 2),
                    'avg_cycle_time_seconds': round(self.stats.avg_cycle_time, 2),
                    'min_cycle_time_seconds': round(self.stats.min_cycle_time, 2),
                    'max_cycle_time_seconds': round(self.stats.max_cycle_time, 2)
                },
                'test_configuration': {
                    'hypervisors': self.config['hypervisors'],
                    'cloud_name': self.config['cloud_name'],
                    'duration_seconds': self.config['duration'],
                    'max_parallel_migrations': self.config['max_parallel'],
                    'migration_timeout_seconds': self.config['migration_timeout']
                },
                'timing_data': {
                    'migration_times': [round(t, 2) for t in self.stats.migration_times],
                    'cycle_times': [round(t, 2) for t in self.stats.cycle_times],
                    'start_time': self.stats.start_time,
                    'end_time': self.stats.end_time
                }
            }

            # Output based on configured format
            if self.config['output_format'] == 'json':
                self._generate_json_report(report_data)
            elif self.config['output_format'] == 'table':
                self._generate_table_report(report_data)
            else:  # text
                self._generate_text_report(report_data)

            # Save to file if specified
            if self.config['results_file']:
                self._save_report_to_file(report_data)

            logging.info("✅ Test report generated successfully")

        except Exception as e:
            logging.error(f"❌ Report generation failed: {e}")
            raise

    @staticmethod
    def _generate_text_report(report_data):
        """Generate report in simple text format."""
        print("\n" + "=" * 60)
        print("OPENSTACK LIVE MIGRATION TEST REPORT")
        print("=" * 60)

        summary = report_data['test_summary']
        perf = report_data['performance_metrics']

        print(f"\nTEST SUMMARY:")
        print(f"  Total Duration: {summary['total_duration_seconds']}s")
        print(f"  Total Cycles: {summary['total_cycles']}")
        print(f"  Total Migrations: {summary['total_migrations']}")
        print(f"  Successful: {summary['successful_migrations']}")
        print(f"  Failed: {summary['failed_migrations']}")
        print(f"  Success Rate: {summary['success_rate_percent']}%")

        print(f"\nPERFORMANCE METRICS:")
        print(f"  Migrations/Hour: {perf['migrations_per_hour']}")
        print(f"  Cycles/Hour: {perf['cycles_per_hour']}")
        print(f"  Avg Migration Time: {perf['avg_migration_time_seconds']}s")
        print(f"  Min-Max Migration Time: {perf['min_migration_time_seconds']}s-{perf['max_migration_time_seconds']}s")
        print(f"  Avg Cycle Time: {perf['avg_cycle_time_seconds']}s")

    @staticmethod
    def _generate_json_report(report_data):
        """Generate report in JSON format."""
        import json
        print(json.dumps(report_data, indent=2))

    def _save_report_to_file(self, report_data):
        """Save report to JSON file."""
        try:
            import json
            with open(self.config['results_file'], 'w') as f:
                json.dump(report_data, f, indent=2)
            logging.info(f"💾 Report saved to: {self.config['results_file']}")
        except Exception as e:
            logging.error(f"❌ Failed to save report: {e}")

    def _generate_table_report(self, report_data):
        """Generate report in table format."""
        try:
            print("\n" + "=" * 60)
            print("📊 OPENSTACK LIVE MIGRATION TEST REPORT")
            print("=" * 60)

            # Test Summary Table
            summary_table = [
                ["Total Duration", f"{report_data['test_summary']['total_duration_seconds']}s"],
                ["Total Cycles", report_data['test_summary']['total_cycles']],
                ["Total Migrations", report_data['test_summary']['total_migrations']],
                ["Successful", report_data['test_summary']['successful_migrations']],
                ["Failed", report_data['test_summary']['failed_migrations']],
                ["Success Rate", f"{report_data['test_summary']['success_rate_percent']}%"]
            ]
            print("\n📈 TEST SUMMARY:")
            print(tabulate(summary_table, tablefmt="grid"))

            # Performance Metrics Table
            perf_table = [
                ["Migrations/Hour", report_data['performance_metrics']['migrations_per_hour']],
                ["Cycles/Hour", report_data['performance_metrics']['cycles_per_hour']],
                ["Avg Migration Time", f"{report_data['performance_metrics']['avg_migration_time_seconds']}s"],
                ["Min Migration Time", f"{report_data['performance_metrics']['min_migration_time_seconds']}s"],
                ["Max Migration Time", f"{report_data['performance_metrics']['max_migration_time_seconds']}s"],
                ["Avg Cycle Time", f"{report_data['performance_metrics']['avg_cycle_time_seconds']}s"]
            ]
            print("\n⚡ PERFORMANCE METRICS:")
            print(tabulate(perf_table, tablefmt="grid"))

        except ImportError:
            self._generate_text_report(report_data)


# === Main Execution ===
def main():
    """Main entry point"""
    try:
        # Parse arguments and build config
        args = parse_arguments()
        config = get_config(args)

        # Setup logging
        setup_logging(config['log_level'])

        # Create tester
        tester = MigrationTester(config)

        # Dry-run mode
        if args.dry_run:
            success = tester.dry_run()
            sys.exit(0 if success else 1)
        else:
            # Normal test execution
            tester.run_test()

    except KeyboardInterrupt:
        logging.info("Test interrupted by user")
        sys.exit(1)
    except Exception as e:
        logging.error(f"Test failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

