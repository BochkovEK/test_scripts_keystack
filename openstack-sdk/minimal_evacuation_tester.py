#!/usr/bin/env python3
"""
Minimal OpenStack Evacuation Tester (novaclient)

Evacuates VMs from failed host to target host.
Supports microversion as argument.
Does NOT start VMs after evacuation.
"""

import argparse
import logging
import sys
import time
import os
from concurrent.futures import ThreadPoolExecutor, as_completed

from novaclient import client as nova_client


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Evacuate VMs from failed host")
    parser.add_argument('--failed-host', required=True, help="Source host")
    parser.add_argument('--target-host', required=True, help="Target host")
    parser.add_argument('--microversion', default='2.96', help="Nova API microversion")
    parser.add_argument('--max-parallel', type=int, default=3, help="Max parallel evacuations")
    parser.add_argument('--timeout', type=int, default=600, help="Timeout per VM in seconds")
    parser.add_argument('--dry-run', action='store_true', help="Dry run")
    return parser.parse_args()


def get_nova_client(microversion):
    """Create nova client using environment variables."""
    return nova_client.Client(
        version=microversion,
        auth_url=os.getenv('OS_AUTH_URL'),
        username=os.getenv('OS_USERNAME'),
        password=os.getenv('OS_PASSWORD'),
        project_name=os.getenv('OS_PROJECT_NAME'),
        user_domain_name=os.getenv('OS_USER_DOMAIN_NAME', 'Default'),
        project_domain_name=os.getenv('OS_PROJECT_DOMAIN_NAME', 'Default')
    )


def evacuate_vms(args):
    """Main evacuation logic."""
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(message)s')

    nova = get_nova_client(args.microversion)
    logging.info(f"Connected to Nova API microversion {args.microversion}")

    # Find ACTIVE VMs on failed host
    vms = nova.servers.list(search_opts={'host': args.failed_host, 'all_tenants': 1})
    active_vms = [vm for vm in vms if vm.status == 'ACTIVE']

    if not active_vms:
        logging.info("No ACTIVE VMs found")
        return

    logging.info(f"Found {len(active_vms)} ACTIVE VMs to evacuate to {args.target_host}")

    if args.dry_run:
        return

    def evacuate_one(vm):
        """Evacuate one VM and wait for host change."""
        try:
            logging.info(f"Evacuating {vm.name} ({vm.id}) → {args.target_host}")

            # Execute evacuation
            nova.servers.evacuate(vm, host=args.target_host)

            # Monitor: wait for host change and task_state == None
            start = time.time()
            original_host = getattr(vm, 'OS-EXT-SRV-ATTR:hypervisor_hostname', None)

            while time.time() - start < args.timeout:
                vm = nova.servers.get(vm.id)
                current_host = getattr(vm, 'OS-EXT-SRV-ATTR:hypervisor_hostname', None)
                task_state = getattr(vm, 'OS-EXT-STS:task_state', None)

                if current_host and current_host != original_host and task_state is None:
                    logging.info(f"Success: {vm.name} moved to {current_host}")
                    return True

                if vm.status == 'ERROR':
                    fault = getattr(vm, 'fault', {}).get('message', 'no details')
                    logging.error(f"Failed: {vm.name} in ERROR - {fault}")
                    return False

                time.sleep(5)

            logging.warning(f"Timeout for {vm.name}: no host change or task not cleared")
            return False

        except Exception as e:
            logging.error(f"Error evacuating {vm.name}: {e}")
            return False

    # Parallel execution
    with ThreadPoolExecutor(max_workers=args.max_parallel) as executor:
        results = list(executor.map(evacuate_one, active_vms))

    success_count = sum(1 for r in results if r)
    logging.info(f"Evacuation completed: {success_count}/{len(active_vms)} successful")


def main():
    """Main entry point."""
    args = parse_arguments()
    evacuate_vms(args)
    sys.exit(0)


if __name__ == "__main__":
    main()