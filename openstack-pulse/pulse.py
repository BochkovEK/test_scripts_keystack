import time
import sys
import os
import re
import threading
import argparse
import io
from contextlib import redirect_stdout

# Add project directories to Python path
sys.path.append(os.path.join(os.path.dirname(__file__), 'services'))
sys.path.append(os.path.join(os.path.dirname(__file__), 'single_check_services'))
sys.path.append(os.path.join(os.path.dirname(__file__), 'config'))

from config.config import Config, ServiceType

# Check services
from services.nova import NovaCheck
from services.cinder import CinderCheck
from services.keystone import KeystoneCheck
from services.neutron import NeutronCheck
from services.rabbitmq import RabbitCheck
from services.mariadb import MariaDBCheck

# Single check services
from single_check_services.placement import PlacementCheck


class Pulse:
    """OpenStack Pulse - Lightweight diagnostic tool"""

    # Service registry - Pulse knows TYPES but not SERVICE LOGIC
    SERVICE_REGISTRY = {
        'nova': {'type': ServiceType.OPENSTACK, 'class': NovaCheck},
        'cinder': {'type': ServiceType.OPENSTACK, 'class': CinderCheck},
        'keystone': {'type': ServiceType.OPENSTACK, 'class': KeystoneCheck},
        'neutron': {'type': ServiceType.OPENSTACK, 'class': NeutronCheck},
        'rabbitmq': {'type': ServiceType.RABBITMQ, 'class': RabbitCheck},
        'galera': {'type': ServiceType.MARIADB, 'class': MariaDBCheck},
    }

    SINGLE_CHECK_SERVICE_REGISTRY = {
        'placement': {'type': ServiceType.OPENSTACK, 'class': PlacementCheck},
    }

    def __init__(self, inventory_path=None,
                 config_path=None,
                 debug=False,
                 output_path=None,
                 duration=None,
                 single_mode=False):
        """
        Initialize Pulse monitor

        Args:
            inventory_path: Path to inventory file
            config_path: Path to config.yml file
            debug: Enable debug output
            output_path: Path for log output
            single_mode: Run once and exit
            duration: duration (seconds)
        """
        self.debug = debug
        self.single_mode = single_mode
        self.duration = duration
        self.inventory_path = inventory_path
        self.config_path = config_path

        # Core components
        self.config = Config(inventory_path=self.inventory_path, config_path=self.config_path)
        self.service_checks = {}
        self.latest_results = {}
        self.service_ready_events = {}

        # Logging
        self.log_file = None
        self.log_handle = None

        # Initialize
        self._init_service_checks()
        self._start_continuous_checks()
        self._setup_logging(output_path)

    def _init_service_checks(self):
        """Initialize service check instances from registry"""
        print("⚙️ Initializing services...")

        for service_name in self.config.settings.check_services:
            if service_name in self.SERVICE_REGISTRY:
                try:
                    service_info = self.SERVICE_REGISTRY[service_name]

                    # Create service instance
                    check = service_info['class'](self.config, debug=self.debug)
                    self.service_checks[service_name] = check
                    self.service_ready_events[service_name] = threading.Event()

                    print(f"  ✅ {service_name} initialized")

                except Exception as e:
                    print(f"  ❌ Failed to initialize {service_name}: {e}")
            else:
                print(f"  ⚠️ Service '{service_name}' not found in registry")

    def _init_single_mode_checks(self):
        """Initialize single-mode check instances"""
        single_checks = {}

        if not self.single_mode:
            return single_checks

        print("🔍 Initializing single-mode checks...")

        for check_name in self.config.settings.single_mode_checks:
            if check_name in self.SINGLE_CHECK_SERVICE_REGISTRY:
                try:
                    service_info = self.SINGLE_CHECK_SERVICE_REGISTRY[check_name]
                    check_instance = service_info['class'](self.config, debug=self.debug)
                    single_checks[check_name] = check_instance
                    print(f"  ✅ {check_name} initialized")
                except Exception as e:
                    print(f"  ❌ Failed to initialize {check_name}: {e}")
            else:
                print(f"  ⚠️ Single-mode check '{check_name}' not found in registry")

        return single_checks

    def _setup_logging(self, output_path=None):
        """
        Setup log file with automatic naming
        Priority: CLI argument → config.yml → /tmp
        """
        enable_log = getattr(self.config.settings.log, 'enable_log', False) if hasattr(self.config.settings,
                                                                                       'log') else False

        if not enable_log:
            self.log_file = None
            print("📝 Logging: disabled")
            return

        # Determine output path (CLI → config → /tmp)
        if output_path is None:
            log_config_path = getattr(self.config.settings.log, 'path', None) if hasattr(self.config.settings,
                                                                                         'log') else None
            output_path = log_config_path or "/tmp"

        if os.path.isdir(output_path):
            # Generate filename
            date_str = time.strftime("%d_%m_%y")
            number = self._find_next_log_number(output_path, date_str)
            filename = f"openstack_pulse_{date_str}_{number:03d}.log"
            log_file = os.path.join(output_path, filename)
        else:
            # Use specified file directly
            log_file = output_path

        self.log_file = log_file
        print(f"📝 Logging: enabled → {self.log_file}")

    def _find_next_log_number(self, directory, date_str):
        """
        Find the next available log file number for the given date
        """
        pattern = f"openstack_pulse_{date_str}_(\\d+)\\.log"
        max_number = 0

        try:
            if not os.path.exists(directory):
                return 1

            for filename in os.listdir(directory):
                match = re.match(pattern, filename)
                if match:
                    number = int(match.group(1))
                    if number > max_number:
                        max_number = number

            return max_number + 1

        except Exception:
            return 1

    def _start_continuous_checks(self):
        """Start continuous monitoring for each service in separate threads"""
        print("🚀 Starting continuous service checks...")

        for service_name, check in self.service_checks.items():
            thread = threading.Thread(
                target=self._run_service_continuously,
                args=(service_name, check),
                name=f"ServiceCheck-{service_name}",
                daemon=True
            )
            thread.start()
            print(f"  ♾️ {service_name} check started")

    def _run_service_continuously(self, service_name, check):
        """Run service checks continuously in background"""
        while True:
            try:
                result = check.run_check()
                self.latest_results[service_name] = result
                self.service_ready_events[service_name].set()
            except Exception as e:
                error_result = {'status': 'ERROR', 'error': str(e), 'response_time': 0}
                self.latest_results[service_name] = error_result
                self.service_ready_events[service_name].set()

            # Use heartbeat interval
            heartbeat_interval = getattr(self.config.settings, 'heartbeat_requests_services', 4)
            time.sleep(heartbeat_interval)

    def collect_metrics(self):
        """Collect latest metrics from all services"""
        snapshot = {'timestamp': time.time()}

        # Wait for all services to have at least one result
        for service_name, event in self.service_ready_events.items():
            if not event.is_set():
                event.wait(timeout=30)

        snapshot.update(self.latest_results.copy())
        return snapshot

    def _write_log(self, message):
        """Write message to log file"""
        if self.log_handle:
            self.log_handle.write(f"{time.ctime()}: {message}\n")
            self.log_handle.flush()

    def run(self):
        """Main monitoring loop - collects snapshots periodically"""
        print("🚀 Starting OpenStack Pulse monitoring...")
        print(f"📊 Enabled checks: {', '.join(self.config.settings.check_services)}")

        # Setup logging
        if self.log_file:
            try:
                self.log_handle = open(self.log_file, 'a')
                self._write_log("🚀 OpenStack Pulse started")
                print(f"💾 Log file: {self.log_file}")
            except Exception as e:
                print(f"❌ Failed to open log file: {e}")
                self.log_file = None
                self.log_handle = None

        # Determine operation mode
        if self.single_mode:
            total_iterations = 1
            print("🔍 Single-shot mode: collecting one snapshot")
        else:
            duration = (self.duration
                        if self.duration is not None
                        else self.config.settings.intervals.duration)
            check_interval = self.config.settings.intervals.check_interval

            total_iterations = duration // check_interval

            source = "CLI argument" if self.duration is not None else "config"
            print(f"⏱️ Collection: {total_iterations} snapshots over {duration}s (from {source})")

        try:
            for cycle in range(total_iterations):
                cycle_start = time.time()

                # Collect and display snapshot
                snapshot = self.collect_metrics()
                self._display_snapshot(snapshot, cycle + 1, total_iterations)

                # Log collection
                if self.log_handle:
                    self._write_log(f"📸 Snapshot {cycle + 1}/{total_iterations} collected")

                cycle_work_time = time.time() - cycle_start
                print(f"📸 Snapshot {cycle + 1} collection time: {cycle_work_time:.1f}s")

                # Wait for next snapshot (except last one)
                if cycle < total_iterations - 1:
                    interval = self.config.settings.intervals.check_interval
                    print(f"💤 Waiting {interval}s for next snapshot...")
                    time.sleep(interval)

            print(f"🎉 Collection completed. Total snapshots: {total_iterations}")
            if self.log_handle:
                self._write_log(f"🎉 Collection completed. Total snapshots: {total_iterations}")

        except KeyboardInterrupt:
            print("\n🛑 Monitoring stopped by user")
            if self.log_handle:
                self._write_log("🛑 Monitoring stopped by user")
        except Exception as e:
            print(f"\n❌ Monitoring error: {e}")
            if self.log_handle:
                self._write_log(f"❌ Monitoring error: {e}")
        finally:
            self._cleanup()

    def _display_snapshot(self, snapshot, current_cycle, total_cycles):
        """Display current snapshot to console AND log"""
        # Capture all output
        output_buffer = io.StringIO()

        with redirect_stdout(output_buffer):
            timestamp = time.ctime(snapshot['timestamp'])
            print("=" * 50)
            print(f"  Cycle {current_cycle}/{total_cycles} - {timestamp}")
            print("=" * 50)

            for service_name in self.config.settings.check_services:
                if service_name in snapshot:
                    self._display_service_status(service_name, snapshot[service_name])

        # Output to console and log
        output_text = output_buffer.getvalue()
        print(output_text, end='')

        if self.log_handle:
            for line in output_text.strip().split('\n'):
                if line.strip():
                    self._write_log(line)

    def _display_service_status(self, service_name, service_data):
        """Display individual service status"""
        status = service_data.get('status', 'UNKNOWN')
        response_time = service_data.get('response_time', 0)

        if status == 'OK':
            status_icon = "✅"
            display_status = 'OK'
        elif status == 'DEGRADED':
            status_icon = "⚠️"
            display_status = 'DEGRADED'
        else:
            status_icon = "❌"
            display_status = status

        print(f"{status_icon} {service_name.upper()}: {display_status} ({response_time}s)")

        check = self.service_checks[service_name]
        if hasattr(check, 'display_details') and status != 'ERROR':
            check.display_details(service_data)
        elif status == 'ERROR':
            error_message = service_data.get('error', 'Unknown error')
            print(f"  Error: {error_message}")

    def run_single_mode_checks(self):
        """Execute additional single-mode checks"""
        if not self.single_mode:
            return

        print("\n" + "=" * 50)
        print("🔍 SINGLE-MODE CHECKS")
        print("=" * 50)

        single_checks = self._init_single_mode_checks()

        for check_name, check_instance in single_checks.items():
            try:
                # Execute single check (one-time)
                result = check_instance.run_single_check()

                # Display results
                self._display_single_check_result(check_name, result, check_instance)

            except Exception as e:
                print(f"❌ {check_name.upper()}: ERROR - {str(e)}")

    def _display_single_check_result(self, check_name, result, check_instance):
        """Display single check result with proper formatting"""
        status = result.get('status', 'UNKNOWN')
        response_time = result.get('response_time', 0)

        status_icon = "✅" if status == 'OK' else "❌"
        print(f"{status_icon} {check_name.upper()}: {status} ({response_time}s)")

        if status == 'OK' and hasattr(check_instance, 'display_placement_report'):
            check_instance.display_placement_report(result)
        elif status == 'ERROR':
            error_message = result.get('error', 'Unknown error')
            print(f"  Error: {error_message}")

    def _cleanup(self):
        """Cleanup resources"""
        # Close service sessions
        for service_name, check in self.service_checks.items():
            if hasattr(check, 'close_sessions'):
                try:
                    check.close_sessions()
                    print(f"🔒 Closed sessions for {service_name}")
                except Exception as e:
                    print(f"⚠️ Failed to close sessions for {service_name}: {e}")

        # Close log file
        if self.log_handle:
            self._write_log("🛑 OpenStack Pulse stopped")
            self.log_handle.close()
            print(f"💾 Log file closed: {self.log_file}")


def get_launch_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='OpenStack Pulse Monitoring')
    parser.add_argument('--inventory', '-i', help='Path to inventory file')
    parser.add_argument('--config', '-c', help='Path to config.yml file')
    parser.add_argument('--output', '-o', help='Path to output file')
    parser.add_argument('--debug', '-d', action='store_true', help='Enable debug mode')
    parser.add_argument('--single', action='store_true', help='Run once and exit')
    parser.add_argument('--duration', type=int, help='Duration in seconds')
    return parser.parse_args()


def main():
    """Main entry point for OpenStack Pulse"""
    args = get_launch_args()

    # Create Pulse instance
    pulse = Pulse(
        inventory_path=args.inventory,
        config_path=args.config,
        debug=args.debug,
        output_path=args.output,
        single_mode=args.single,
        duration=args.duration
    )

    # Always run main monitoring
    pulse.run()

    # Run single-mode checks only if requested
    pulse.run_single_mode_checks()


if __name__ == "__main__":
    main()

