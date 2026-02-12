#!/usr/bin/env python3
"""
Minimal OpenStack Evacuation Tester (novaclient)
"""

import argparse
import logging
import sys
import time
import os
import signal
from tabulate import tabulate
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime

from novaclient import client as nova_client


class TimeoutManager:
    """Manage timeout settings and interrupt handling."""

    def __init__(self, default_timeout=600):
        self.timeout = default_timeout
        self.interrupted = False
        signal.signal(signal.SIGINT, self.handle_interrupt)
        signal.signal(signal.SIGTERM, self.handle_interrupt)

    def handle_interrupt(self, signum, frame):
        """Handle Ctrl+C gracefully."""
        print("\n\n⚠️  INTERRUPT RECEIVED! Completing current evacuations...")
        print("   Press Ctrl+C again to force exit.\n")
        self.interrupted = True
        # Reset signal handlers for second interrupt
        signal.signal(signal.SIGINT, signal.default_int_handler)
        signal.signal(signal.SIGTERM, signal.default_int_handler)

    def check_interrupted(self):
        """Check if interrupt was received."""
        return self.interrupted


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Evacuate VMs from a failed host",
        epilog="""
TIMEOUT OPTIONS:
  --timeout N           Set timeout in seconds (default: 600)
  --no-timeout         Disable timeout completely (wait forever)

MANUAL INTERRUPTION:
  Press Ctrl+C once to gracefully complete current evacuations
  Press Ctrl+C twice to force immediate exit
        """,
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('--failed-host', required=True, help="Source host")
    parser.add_argument('--target-host', required=False,
                        help="Target host (optional - if not specified, Nova will auto-select)")
    parser.add_argument('--microversion', default='2.96', help="Nova API microversion")
    parser.add_argument('--max-parallel', type=int, default=3, help="Max parallel evacuations")

    # Timeout options group
    timeout_group = parser.add_mutually_exclusive_group()
    timeout_group.add_argument('--timeout', type=int, default=600,
                               help="Timeout per VM in seconds (default: 600)")
    timeout_group.add_argument('--no-timeout', action='store_true',
                               help="Disable timeout - wait indefinitely for each VM")

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

    # Initialize timeout manager
    timeout_value = None if args.no_timeout else args.timeout
    timeout_mgr = TimeoutManager(timeout_value)

    start_time = time.time()
    nova = get_nova_client(args.microversion)
    logging.info(f"Connected to Nova API microversion {args.microversion}")

    if args.no_timeout:
        logging.info("⚠️  Timeout disabled - will wait indefinitely for each VM")
        logging.info("   Press Ctrl+C once for graceful completion, twice to force exit")
    else:
        logging.info(f"⏱️  Timeout per VM: {args.timeout}s (Ctrl+C once to interrupt)")

    # Find ACTIVE VMs on failed host
    vms = nova.servers.list(search_opts={'host': args.failed_host, 'all_tenants': 1})
    active_vms = [vm for vm in vms if vm.status == 'ACTIVE']

    if not active_vms:
        logging.info("No ACTIVE VMs found")
        return 0, 0, 0, start_time, time.time()

    if args.target_host:
        logging.info(f"Found {len(active_vms)} ACTIVE VMs to evacuate to {args.target_host}")
    else:
        logging.info(f"Found {len(active_vms)} ACTIVE VMs to evacuate (Nova auto-select target)")

    if args.dry_run:
        logging.info("Dry run mode — no actual evacuation performed")
        return 0, 0, len(active_vms), start_time, time.time()

    def evacuate_one(vm):
        """Evacuate one VM and wait for host change."""
        try:
            if args.target_host:
                logging.info(f"Evacuating {vm.name} ({vm.id}) → {args.target_host}")
            else:
                logging.info(f"Evacuating {vm.name} ({vm.id}) → (auto-selected host)")

            # Execute evacuation
            if args.target_host:
                nova.servers.evacuate(vm, host=args.target_host)
            else:
                nova.servers.evacuate(vm)

            # Monitor: wait for host change and task_state == None
            start = time.time()
            original_host = getattr(vm, 'OS-EXT-SRV-ATTR:hypervisor_hostname', None)

            # Show timeout status in monitoring
            timeout_status = "∞" if args.no_timeout else f"{args.timeout}s"
            logging.debug(f"Monitoring {vm.name} (timeout: {timeout_status})")

            while True:
                # Check for manual interrupt
                if timeout_mgr.check_interrupted():
                    logging.warning(f"⚠️  Interrupt received, stopping monitoring of {vm.name}")
                    return False, time.time() - start, "INTERRUPTED"

                vm = nova.servers.get(vm.id)
                current_host = getattr(vm, 'OS-EXT-SRV-ATTR:hypervisor_hostname', None)
                task_state = getattr(vm, 'OS-EXT-STS:task_state', None)

                if current_host and current_host != original_host and task_state is None:
                    logging.info(f"✅ Success: {vm.name} moved to {current_host}")
                    return True, time.time() - start, "SUCCESS"

                if vm.status == 'ERROR':
                    fault = getattr(vm, 'fault', {}).get('message', 'no details')
                    logging.error(f"❌ Failed: {vm.name} in ERROR - {fault}")
                    return False, time.time() - start, "ERROR"

                # Check timeout only if enabled
                if not args.no_timeout and (time.time() - start) > args.timeout:
                    logging.warning(f"⏰ Timeout for {vm.name}: {args.timeout}s elapsed")
                    return False, time.time() - start, "TIMEOUT"

                time.sleep(5)

        except Exception as e:
            logging.error(f"💥 Error evacuating {vm.name}: {e}")
            return False, 0, f"EXCEPTION: {str(e)[:50]}"

    # Parallel execution with interrupt handling
    results = []
    successful_results = []

    with ThreadPoolExecutor(max_workers=args.max_parallel) as executor:
        futures = [executor.submit(evacuate_one, vm) for vm in active_vms]

        try:
            for future in as_completed(futures):
                if timeout_mgr.check_interrupted():
                    logging.warning("⚠️  Interrupt received - cancelling remaining evacuations")
                    for f in futures:
                        f.cancel()
                    break

                success, mig_time, status = future.result()
                results.append((success, mig_time, status))
                if success:
                    successful_results.append(mig_time)

        except KeyboardInterrupt:
            logging.warning("⚠️  Force interrupt - stopping all operations")
            for f in futures:
                f.cancel()
            raise

    end_time = time.time()

    # Calculate statistics
    success_count = sum(1 for s, _, _ in results if s)
    total_migrations = len(active_vms)
    duration = end_time - start_time

    # Count different failure reasons
    timeout_count = sum(1 for _, _, status in results if status == "TIMEOUT")
    error_count = sum(1 for _, _, status in results if status in ["ERROR", "EXCEPTION"])
    interrupted_count = sum(1 for _, _, status in results if status == "INTERRUPTED")

    # Performance metrics
    avg_time = sum(successful_results) / len(successful_results) if successful_results else 0
    min_time = min(successful_results) if successful_results else 0
    max_time = max(successful_results) if successful_results else 0

    migrations_per_hour = (success_count * 3600) / duration if duration > 0 else 0

    # Final report
    print("\n" + "=" * 70)
    print("📊 OPENSTACK EVACUATION TEST REPORT")
    print("=" * 70)

    # Timeout mode info
    timeout_mode = "Disabled (wait forever)" if args.no_timeout else f"{args.timeout}s per VM"

    print("🔧 CONFIGURATION:")
    print(tabulate([
        ["Source Host", args.failed_host],
        ["Target Host", args.target_host if args.target_host else "Auto-selected by Nova"],
        ["Timeout Mode", timeout_mode],
        ["Max Parallel", args.max_parallel],
        ["API Microversion", args.microversion],
    ], tablefmt="grid"))

    print("\n📈 TEST SUMMARY:")
    print(tabulate([
        ["Total Duration", f"{duration:.2f}s"],
        ["Total VMs", total_migrations],
        ["✅ Successful", success_count],
        ["❌ Failed", total_migrations - success_count],
        ["   ├─ Timeouts", timeout_count],
        ["   ├─ Errors", error_count],
        ["   └─ Interrupted", interrupted_count],
        ["Success Rate", f"{success_count / total_migrations * 100:.1f}%" if total_migrations else "0.0%"]
    ], tablefmt="grid"))

    if successful_results:
        print("\n⚡ PERFORMANCE METRICS:")
        print(tabulate([
            ["Migrations/Hour", f"{migrations_per_hour:.2f}"],
            ["Avg Evacuation Time", f"{avg_time:.2f}s"],
            ["Min Evacuation Time", f"{min_time:.2f}s"],
            ["Max Evacuation Time", f"{max_time:.2f}s"]
        ], tablefmt="grid"))

    print("=" * 70)

    if interrupted_count > 0:
        print("\n⚠️  Note: Process was interrupted before completion")
    if timeout_count > 0:
        print(f"⏰  Note: {timeout_count} VMs timed out after {args.timeout if not args.no_timeout else 'N/A'}s")

    return success_count, total_migrations - success_count, total_migrations, start_time, end_time


def main():
    """Main entry point."""
    args = parse_arguments()
    try:
        evacuate_vms(args)
    except KeyboardInterrupt:
        print("\n\n⚠️  Force exit by user")
        sys.exit(130)
    sys.exit(0)


if __name__ == "__main__":
    main()