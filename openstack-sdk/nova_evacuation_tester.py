#!/usr/bin/env python3
"""
Simple OpenStack Hypervisor Evacuation Tester using python-novaclient

Tests VM evacuation from a failed hypervisor with validation and parallel execution.
Host must be DOWN and nova-compute services forced_down before running.
"""

import argparse
import logging
import os
import sys
import time
import json
from typing import List, Dict, Any
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

from novaclient import client as nova_client
from novaclient.exceptions import ClientException


def parse_arguments() -> argparse.Namespace:
    """
    Parse command line arguments.
    """
    parser = argparse.ArgumentParser(
        description='Simple OpenStack Hypervisor Evacuation Tester (novaclient)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --failed-host compute-01 --dry-run
  %(prog)s --failed-host compute-01 --target-hosts compute-02,compute-03
  %(prog)s --failed-host compute-01 --microversion 2.14 --max-parallel 4
        """
    )

    # Required parameter
    parser.add_argument(
        '--failed-host',
        required=True,
        help='Hypervisor host to evacuate VMs from (required)'
    )

    # Nova API version
    parser.add_argument(
        '--microversion',
        default='2.1',
        help='Nova API microversion to use (default: 2.1)'
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
        '--per-vm-timeout',
        type=int,
        default=300,
        help='Timeout per VM in seconds (default: 300)'
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


def setup_logging(log_level: str):
    """Configure logging."""
    logging.basicConfig(
        level=getattr(logging, log_level),
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%H:%M:%S'
    )


class EvacuationTester:
    """Evacuation tester using python-novaclient"""

    def __init__(self, args):
        self.args = args
        self.nova = self._get_nova_client()
        self.vms: List = []
        self.results: List[Dict] = []
        self.start_time = None
        self.end_time = None

    def _get_nova_client(self):
        """Create nova client using environment variables or clouds.yaml"""
        try:
            # Use OS_* variables or clouds.yaml if OS_CLOUD set
            nc = nova_client.Client(
                version=self.args.microversion,
                session=None,  # will use env vars / clouds.yaml
                auth_url=os.getenv('OS_AUTH_URL'),
                username=os.getenv('OS_USERNAME'),
                password=os.getenv('OS_PASSWORD'),
                project_name=os.getenv('OS_PROJECT_NAME'),
                user_domain_name=os.getenv('OS_USER_DOMAIN_NAME', 'Default'),
                project_domain_name=os.getenv('OS_PROJECT_DOMAIN_NAME', 'Default')
            )
            logging.info(f"Nova client connected (microversion {self.args.microversion})")
            return nc
        except Exception as e:
            logging.error(f"Nova client connection failed: {e}")
            sys.exit(1)

    def find_vms_on_host(self) -> List:
        """Find ACTIVE and suitable VMs on failed host."""
        vms = []
        search_opts = {'host': self.args.failed_host, 'all_tenants': 1}
        if self.args.project_id:
            search_opts['tenant_id'] = self.args.project_id

        for server in self.nova.servers.list(search_opts=search_opts):
            if server.status in ['ACTIVE', 'SHUTOFF', 'ERROR']:
                vms.append(server)

        logging.info(f"Found {len(vms)} VMs on {self.args.failed_host}")
        return vms

    def evacuate_single_vm(self, server) -> Dict[str, Any]:
        """Evacuate single VM."""
        result = {
            'vm_id': server.id,
            'vm_name': server.name,
            'success': False,
            'start_time': time.time(),
            'error': None,
            'target_host': None,
            'evacuation_time': 0
        }

        try:
            logging.info(f"Evacuating {server.name} ({server.id})")

            target = None
            if self.args.target_hosts and len(self.args.target_hosts) == 1:
                target = self.args.target_hosts[0]
                logging.info(f"  → target: {target}")

            # Perform evacuation
            self.nova.servers.evacuate(
                server=server,
                host=target,
            )

            # Simple monitoring
            start = time.time()
            original_host = getattr(server, 'OS-EXT-SRV-ATTR:hypervisor_hostname', None)

            while time.time() - start < self.args.per_vm_timeout:
                server = self.nova.servers.get(server.id)
                current_host = getattr(server, 'OS-EXT-SRV-ATTR:hypervisor_hostname', None)

                if server.status == 'ACTIVE' and current_host and current_host != original_host:
                    result['target_host'] = current_host
                    result['success'] = True
                    break
                if server.status == 'ERROR':
                    result['error'] = "VM entered ERROR state"
                    break
                time.sleep(5)

            if not result['success'] and not result['error']:
                result['error'] = "Timeout or no host change"

        except ClientException as e:
            result['error'] = str(e)

        result['evacuation_time'] = time.time() - result['start_time']
        if result['success']:
            logging.info(f"Success: {server.name} → {result['target_host']}")
        else:
            logging.error(f"Failed: {server.name} - {result['error']}")

        return result

    def run(self):
        """Run the evacuation test."""
        setup_logging(self.args.log_level)
        logging.info("Starting evacuation test")

        self.vms = self.find_vms_on_host()
        if not self.vms:
            logging.info("No VMs to evacuate")
            return

        if self.args.dry_run:
            logging.info("Dry run mode — no actual evacuation performed")
            logging.info(f"Found {len(self.vms)} VMs ready for evacuation")
            return

        self.start_time = time.time()

        # Parallel execution
        max_workers = min(self.args.max_parallel, len(self.vms))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [executor.submit(self.evacuate_single_vm, vm) for vm in self.vms]
            for future in as_completed(futures):
                self.results.append(future.result())

        self.end_time = time.time()
        self._print_summary()

    def _print_summary(self):
        """Print simple summary of results."""
        successful = sum(1 for r in self.results if r['success'])
        failed = len(self.results) - successful
        duration = self.end_time - self.start_time if self.start_time and self.end_time else 0

        print("\n" + "="*60)
        print("EVACUATION SUMMARY")
        print("="*60)
        print(f"Host: {self.args.failed_host}")
        print(f"Duration: {duration:.1f}s")
        print(f"Total VMs: {len(self.results)}")
        print(f"Successful: {successful} ({successful/len(self.results)*100:.1f}% if self.results else 0)")
        print(f"Failed: {failed}")
        if self.results:
            times = [r['evacuation_time'] for r in self.results if r['success']]
            if times:
                print(f"Avg time (successful): {sum(times)/len(times):.1f}s")
        print("="*60)


if __name__ == "__main__":
    args = parse_arguments()
    tester = EvacuationTester(args)
    tester.run()
    sys.exit(0)