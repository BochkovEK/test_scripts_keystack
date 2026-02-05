#!/usr/bin/env python3
"""
Minimal OpenStack Evacuation Tester (novaclient)

Evacuates VMs from failed host to target host.
Supports microversion as argument.
"""

import argparse
import logging
import sys
import time
import os
from concurrent.futures import ThreadPoolExecutor, as_completed

from novaclient import client as nova_client


def parse_arguments():
    parser = argparse.ArgumentParser(description="Evacuate VMs from failed host")
    parser.add_argument('--failed-host', required=True, help="Source host")
    parser.add_argument('--target-host', required=True, help="Target host")
    parser.add_argument('--microversion', default='2.96', help="Nova API microversion")
    parser.add_argument('--max-parallel', type=int, default=3, help="Max parallel evacuations")
    parser.add_argument('--dry-run', action='store_true', help="Dry run")
    return parser.parse_args()


def get_nova_client(microversion):
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
        try:
            logging.info(f"Evacuating {vm.name} ({vm.id}) → {args.target_host}")
            nova.servers.evacuate(vm, host=args.target_host)
            # Wait for completion (simple polling)
            for _ in range(60):  # ~5 min max
                vm = nova.servers.get(vm.id)
                if vm.status == 'ACTIVE':
                    logging.info(f"Success: {vm.name}")
                    return True
                if vm.status == 'ERROR':
                    logging.error(f"Failed: {vm.name} in ERROR")
                    return False
                time.sleep(5)
            logging.warning(f"Timeout for {vm.name}")
            return False
        except Exception as e:
            logging.error(f"Error evacuating {vm.name}: {e}")
            return False

    # Parallel execution
    with ThreadPoolExecutor(max_workers=args.max_parallel) as executor:
        results = list(executor.map(evacuate_one, active_vms))

    success_count = sum(results)
    logging.info(f"Evacuation completed: {success_count}/{len(active_vms)} successful")


def main():
    args = parse_arguments()
    evacuate_vms(args)
    sys.exit(0)


if __name__ == "__main__":
    main()