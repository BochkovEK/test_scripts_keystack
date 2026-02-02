#!/usr/bin/env python3
"""
OpenStack VM Starter for SHUTOFF VMs

Starts SHUTOFF VMs on a specified host before evacuation.
Checks host services state to ensure VM can be started.
"""

import openstack
import argparse
import logging
import time
import sys
from typing import List, Dict, Any


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Start SHUTOFF VMs on OpenStack host'
    )

    parser.add_argument(
        '--host',
        required=True,
        help='Host to start SHUTOFF VMs on'
    )

    parser.add_argument(
        '--cloud',
        default=None,
        help='OpenStack cloud name'
    )

    parser.add_argument(
        '--project-id',
        help='Only start VMs from this project'
    )

    parser.add_argument(
        '--start-timeout',
        type=int,
        default=300,
        help='Timeout per VM start in seconds (default: 300)'
    )

    parser.add_argument(
        '--max-parallel',
        type=int,
        default=2,
        help='Max parallel VM starts (default: 2)'
    )

    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be started without actual start'
    )

    parser.add_argument(
        '--log-level',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        default='INFO',
        help='Logging level'
    )

    return parser.parse_args()


class VMStarter:
    """Starts SHUTOFF VMs on a host."""

    def __init__(self, config: dict):
        self.config = config
        self.conn = None
        self.host_info = None

    def run(self) -> bool:
        """Main execution."""
        try:
            self.connect()

            # Validate host is accessible
            if not self.validate_host_services():
                return False

            # Find SHUTOFF VMs
            shutoff_vms = self.find_shutoff_vms()

            if not shutoff_vms:
                logging.info("⚠️ No SHUTOFF VMs found on host")
                return True

            logging.info(f"Found {len(shutoff_vms)} SHUTOFF VMs on {self.config['host']}")

            if self.config['dry_run']:
                self.dry_run_report(shutoff_vms)
                return True

            # Start VMs
            results = self.start_vms(shutoff_vms)

            # Report results
            self.report_results(results)

            successful = sum(1 for r in results if r['success'])
            return successful > 0

        except Exception as e:
            logging.error(f"Failed: {e}")
            return False

    def connect(self):
        """Connect to OpenStack."""
        try:
            if self.config['cloud']:
                self.conn = openstack.connect(cloud=self.config['cloud'])
            else:
                self.conn = openstack.connect()

            self.conn.authorize()
            logging.info("Connected to OpenStack")

        except Exception as e:
            logging.error(f"Connection failed: {e}")
            raise

    def validate_host_services(self) -> bool:
        """
        Validate host services are operational.

        Returns:
            bool: True if host services are OK
        """
        logging.info(f"Validating host services: {self.config['host']}")

        # Check hypervisor state
        try:
            hypervisors = list(self.conn.compute.hypervisors())
            for hyp in hypervisors:
                if hyp.name == self.config['host']:
                    self.host_info = hyp
                    logging.info(f"Host found: {hyp.name} (state: {hyp.state}, status: {hyp.status})")

                    # Host must be UP and enabled
                    if hyp.state != 'up' or hyp.status != 'enabled':
                        logging.error(f"Host is not operational: state={hyp.state}, status={hyp.status}")
                        logging.error("Cannot start VMs on down/disabled host")
                        return False
                    break
            else:
                logging.error(f"Host {self.config['host']} not found")
                return False

        except Exception as e:
            logging.error(f"Error checking host: {e}")
            return False

        # Check compute service
        try:
            services = list(self.conn.compute.services())
            compute_services = [
                s for s in services
                if s.host == self.config['host'] and s.binary == 'nova-compute'
            ]

            if not compute_services:
                logging.error(f"No compute service found on host {self.config['host']}")
                return False

            service = compute_services[0]
            logging.info(f"Compute service: {service.state}/{service.status}")

            if service.state != 'up' or service.status != 'enabled':
                logging.error(f"Compute service not operational: {service.state}/{service.status}")
                return False

        except Exception as e:
            logging.error(f"Error checking services: {e}")
            return False

        logging.info("✅ Host services validation passed")
        return True

    def find_shutoff_vms(self) -> List:
        """Find SHUTOFF VMs on host."""
        vms = []

        try:
            all_servers = list(self.conn.compute.servers(all_projects=True))

            for server in all_servers:
                server_host = getattr(server, 'hypervisor_hostname', None)

                if server_host != self.config['host']:
                    continue

                if self.config['project_id'] and getattr(server, 'project_id') != self.config['project_id']:
                    continue

                if server.status == 'SHUTOFF':
                    vms.append(server)

        except Exception as e:
            logging.error(f"Error finding VMs: {e}")

        return vms

    def start_vms(self, vms: List) -> List[Dict[str, Any]]:
        """Start SHUTOFF VMs."""
        from concurrent.futures import ThreadPoolExecutor, as_completed

        results = []

        logging.info(f"Starting {len(vms)} SHUTOFF VMs...")

        max_workers = min(self.config['max_parallel'], len(vms))

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_vm = {
                executor.submit(self.start_single_vm, vm): vm
                for vm in vms
            }

            for future in as_completed(future_to_vm):
                vm = future_to_vm[future]
                try:
                    result = future.result()
                    results.append(result)

                    if result['success']:
                        logging.info(f"✅ {vm.name}: Started successfully")
                    else:
                        logging.error(f"❌ {vm.name}: Failed - {result.get('error')}")

                except Exception as e:
                    results.append({
                        'vm_id': vm.id,
                        'vm_name': vm.name,
                        'success': False,
                        'error': str(e)
                    })
                    logging.error(f"❌ {vm.name}: Exception - {e}")

        return results

    def start_single_vm(self, vm) -> Dict[str, Any]:
        """Start single SHUTOFF VM."""
        result = {
            'vm_id': vm.id,
            'vm_name': vm.name,
            'success': False,
            'error': None,
            'start_time': time.time(),
            'end_time': None,
            'duration': None
        }

        try:
            logging.info(f"Starting VM: {vm.name}")

            # Start VM
            self.conn.compute.start_server(vm.id)

            # Monitor start progress
            timeout = self.config['start_timeout']
            start_time = time.time()

            while time.time() - start_time < timeout:
                vm = self.conn.compute.get_server(vm.id)

                if vm.status == 'ACTIVE':
                    result['success'] = True
                    result['end_time'] = time.time()
                    result['duration'] = result['end_time'] - result['start_time']
                    return result

                elif vm.status == 'ERROR':
                    result['error'] = f"VM entered ERROR state"
                    break

                time.sleep(5)

            if not result['success']:
                result['error'] = f"Timeout after {timeout}s, final status: {vm.status}"

        except Exception as e:
            result['error'] = str(e)

        result['end_time'] = time.time()
        result['duration'] = result['end_time'] - result['start_time']
        return result

    def dry_run_report(self, vms: List):
        """Show dry-run report."""
        logging.info("=" * 60)
        logging.info("DRY RUN - No VMs will be started")
        logging.info("=" * 60)

        logging.info(f"\nWould attempt to start {len(vms)} SHUTOFF VMs:")
        for vm in vms:
            logging.info(f"  - {vm.name} (ID: {vm.id})")

        logging.info("\nRequirements checked:")
        logging.info(f"  ✅ Host {self.config['host']} is UP and enabled")
        logging.info(f"  ✅ Compute service is operational")
        logging.info(f"  ⚠️  Starting {len(vms)} VMs may take ~{len(vms) * 2} minutes")

    def report_results(self, results: List[Dict[str, Any]]):
        """Report start results."""
        successful = [r for r in results if r['success']]
        failed = [r for r in results if not r['success']]

        logging.info("\n" + "=" * 60)
        logging.info("VM START RESULTS")
        logging.info("=" * 60)

        logging.info(f"Total VMs: {len(results)}")
        logging.info(f"Successful: {len(successful)}")
        logging.info(f"Failed: {len(failed)}")

        if successful:
            avg_time = sum(r['duration'] for r in successful) / len(successful)
            logging.info(f"Average start time: {avg_time:.1f}s")

        if failed:
            logging.info("\nFailed VMs:")
            for r in failed:
                logging.info(f"  - {r['vm_name']}: {r.get('error', 'Unknown error')}")


def main():
    """Main entry point."""
    args = parse_arguments()

    config = {
        'host': args.host,
        'cloud': args.cloud,
        'project_id': args.project_id,
        'start_timeout': args.start_timeout,
        'max_parallel': args.max_parallel,
        'dry_run': args.dry_run,
        'log_level': args.log_level
    }

    logging.basicConfig(
        level=getattr(logging, config['log_level']),
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%H:%M:%S'
    )

    starter = VMStarter(config)
    success = starter.run()

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
