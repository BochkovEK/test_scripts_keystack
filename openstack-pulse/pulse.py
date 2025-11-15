import time
import sys
import os
import re
import threading
import argparse
import io
from contextlib import redirect_stdout
from concurrent.futures import ThreadPoolExecutor, as_completed

# Add project directories to Python path
sys.path.append(os.path.join(os.path.dirname(__file__), 'services'))
sys.path.append(os.path.join(os.path.dirname(__file__), 'config'))

from config.config import Config
from services.nova import NovaCheck
from services.cinder import CinderCheck
from services.keystone import KeystoneCheck
from services.neutron import NeutronCheck
from services.rabbitmq import RabbitCheck
from services.mariadb import MariaDBCheck


class Pulse:
    """OpenStack Pulse - Lightweight diagnostic tool"""

    def __init__(self, inventory_path=None, config_path=None, debug=False, output_path=None):
        self.debug = debug
        self.inventory_path = inventory_path
        self.config_path = config_path
        self.config = Config(inventory_path=self.inventory_path, config_path=self.config_path)
        self.log_handle = None
        self.service_checks = {}
        self.latest_results = {}  # Store latest service results
        self.service_ready_events = {}  # Track service readiness
        self._init_service_checks()
        self._start_continuous_checks()
        self._setup_logging(output_path)

    def _init_service_checks(self):
        """Initialize service check instances"""
        service_map = {
            'nova': NovaCheck,
            'cinder': CinderCheck,
            'neutron': NeutronCheck,
            'keystone': KeystoneCheck,
            'rabbitmq': RabbitCheck,
            'galera': MariaDBCheck,
        }

        for service_name in self.config.settings.check_services:
            if service_name in service_map:
                try:
                    # All services now receive config object
                    self.service_checks[service_name] = service_map[service_name](
                        self.config,
                        debug=self.debug
                    )
                    self.service_ready_events[service_name] = threading.Event()
                    print(f"🔷 {service_name} initialized")
                    self._write_log(f"🔷 {service_name} initialized")
                except Exception as e:
                    print(f"❌️  Failed to initialize {service_name}: {e}")
                    self._write_log(f"❌️ Failed to initialize {service_name}: {e}")
            else:
                print(f"⚠️  Service '{service_name}' not supported")
                self._write_log(f"⚠️  Service '{service_name}' not supported")

    def find_next_number(self, directory, date_str):
        """
        Find the next available log file number for the given date

        Args:
            directory: Path to log directory
            date_str: Date string in format dd_mm_yy (14_11_25)

        Returns:
            Next available number (starting from 001)
        """
        pattern = f"openstack_pulse_{date_str}_(\\d+)\\.log"
        max_number = 0

        try:
            if not os.path.exists(directory):
                return 1  # First file if directory doesn't exist

            for filename in os.listdir(directory):
                match = re.match(pattern, filename)
                if match:
                    number = int(match.group(1))
                    if number > max_number:
                        max_number = number

            return max_number + 1

        except Exception:
            return 1  # Fallback to first number on error

    def _setup_logging(self, output_path=None):
        """
        Setup log file with automatic naming
        Format: openstack_pulse_dd_mm_yy_NUMBER.log
        Priority: CLI argument → config.yml → /tmp
        """
        enable_log = False
        log_config_path = None

        try:
            enable_log = getattr(self.config.settings.log, 'enable_log', False) if hasattr(self.config.settings,
                                                                                           'log') else False
            if self.debug:
                print(f"🔧 [PULSE_DEBUG] enable_log from config: {enable_log}")

            if not enable_log:
                self.log_file = None
                if self.debug:
                    print(f"🔧 [PULSE_DEBUG] Logging disabled by config")
                print("📝 Logging: ⚠️ disabled")
                return

            if output_path is None:
                log_config_path = getattr(self.config.settings.log, 'path', None) if hasattr(self.config.settings,
                                                                                             'log') else None
                output_path = log_config_path or "/tmp"

            if self.debug:
                print(f"🔧 [PULSE_DEBUG] Final output_path: {output_path}")
                print(f"🔧 [PULSE_DEBUG] Path is directory: {os.path.isdir(output_path)}")

        except:
            pass

        if not enable_log:
            return None

        # Determine output path (CLI → config → /tmp)
        if output_path is None:
            output_path = log_config_path or "/tmp"

        if os.path.isdir(output_path):
            # Generate filename using class method
            date_str = time.strftime("%d_%m_%y")
            if self.debug:
                print(f"🔧 [PULSE_DEBUG] Date string: {date_str}")

            number = self.find_next_number(output_path, date_str)
            if self.debug:
                print(f"🔧 [PULSE_DEBUG] Next file number: {number:03d}")

            filename = f"openstack_pulse_{date_str}_{number:03d}.log"
            log_file = os.path.join(output_path, filename)
            if self.debug:
                print(f"🔧 [PULSE_DEBUG] Generated filename: {filename}")

        else:
            # Use specified file directly
            log_file = output_path
            if self.debug:
                print(f"🔧 [PULSE_DEBUG] Using direct file path: {log_file}")

        self.log_file = log_file

        if self.debug:
            print(f"🔧 [PULSE_DEBUG] Final log_file path: {self.log_file}")

        print(f"📝 Logging: enabled → {self.log_file}")

    def _start_continuous_checks(self):
        """Start continuous monitoring for each service in separate threads"""
        print("🚀 Starting continuous service checks...")
        for service_name, check in self.service_checks.items():
            thread = threading.Thread(
                target=self._run_service_continuously,
                args=(service_name, check),
                name=f"ServiceCheck-{service_name}"
            )
            thread.daemon = True
            thread.start()
            print(f"  ♾️ {service_name} check started")
            self._write_log(f"♾️ {service_name} check started")

    def _run_service_continuously(self, service_name, check):
        """Run service checks continuously in background"""
        while True:
            try:
                result = check.run_check()
                self.latest_results[service_name] = result
                self.service_ready_events[service_name].set()  # Mark as ready
            except Exception as e:
                error_result = {'status': 'ERROR', 'error': str(e), 'response_time': 0}
                self.latest_results[service_name] = error_result
                self.service_ready_events[service_name].set()
                self._write_log(f"❌ {service_name} check error: {e}")

            # Use heartbeat interval for service polling
            heartbeat_interval = getattr(self.config.settings, 'heartbeat_requests_services', 4)
            time.sleep(heartbeat_interval)

    def collect_metrics(self):
        """Collect latest metrics from all services"""
        snapshot = {'timestamp': time.time()}

        # Wait for all services to have at least one result
        for service_name, event in self.service_ready_events.items():
            if not event.is_set():
                event.wait(timeout=30)

        # Copy latest results
        snapshot.update(self.latest_results.copy())
        return snapshot

    def _write_log(self, message):
        """Write message to log file"""
        if self.log_handle:
            self.log_handle.write(f"{time.ctime()}: {message}\n")
            self.log_handle.flush()

    def run(self):
        """Main monitoring loop - collects snapshots periodically"""
        print("Starting OpenStack Pulse monitoring...")
        print(f"Enabled checks: {', '.join(self.config.settings.check_services)}")

        # Open log file if logging enabled
        if self.log_file:
            try:
                self.log_handle = open(self.log_file, 'a')
                self._write_log("🚀 OpenStack Pulse started")
                print(f"💾 Log file opened: {self.log_file}")
            except Exception as e:
                print(f"❌ Failed to open log file: {e}")
                self.log_file = None
                self.log_handle = None

        total_iterations = (self.config.settings.intervals.collection_window //
                            self.config.settings.intervals.check_interval)
        print(f"Collection: {total_iterations} snapshots")

        try:
            for cycle in range(total_iterations):
                cycle_start = time.time()

                # Collect snapshot of current state
                snapshot = self.collect_metrics()

                # Display snapshot
                self._display_snapshot(snapshot, cycle + 1, total_iterations)

                # Log snapshot collection
                if self.log_handle:
                    self._write_log(f"📸 Snapshot {cycle + 1}/{total_iterations} collected")

                cycle_work_time = time.time() - cycle_start
                print(f"📸 Snapshot {cycle + 1} collection time: {cycle_work_time:.1f}s")

                # Wait for next snapshot (except last one)
                if cycle < total_iterations - 1:
                    interval = self.config.settings.intervals.check_interval
                    print(f"💤 Waiting {interval}s for next snapshot...")
                    time.sleep(interval)

            print(f"\n🎉 Collection completed. Total snapshots: {total_iterations}")
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
            if self.log_handle:
                self._write_log("🛑 OpenStack Pulse stopped")
                self.log_handle.close()
                print(f"💾 Log file closed: {self.log_file}")
            self._close_sessions()

    def _close_sessions(self):
        """Close all sessions to free resources"""
        for service_name, check in self.service_checks.items():
            if hasattr(check, 'close_sessions'):
                check.close_sessions()
                print(f"🔒 Closed sessions for {service_name}")

    # def _format_service_details(self, service_name, service_data):
    #     """Format service-specific details for output"""
    #     lines = []
    #
    #     format_methods = {
    #         'nova': self._format_nova_details,
    #         'keystone': self._format_keystone_details,
    #         'neutron': self._format_neutron_details,
    #         'rabbitmq': self._format_rabbitmq_details,
    #         'galera': self._format_mariadb_details,
    #         'cinder': self._format_cinder_details
    #     }
    #
    #     if service_name in format_methods:
    #         lines.extend(format_methods[service_name](service_data))
    #
    #     return lines

    # def _display_snapshot(self, snapshot, current_cycle, total_cycles):
    #     """Display current snapshot to console"""
    #     output_lines = []
    #
    #     timestamp = time.ctime(snapshot['timestamp'])
    #     output_lines.append("=" * 45)
    #     output_lines.append(f"  Cycle {current_cycle}/{total_cycles} - {timestamp}")
    #     output_lines.append("=" * 45)
    #
    #     for service_name in self.config.settings.check_services:
    #         if service_name in snapshot:
    #             service_data = snapshot[service_name]
    #             self._display_service_status(service_name, service_data)
    #             output_lines.extend(self._format_service_output(service_name, service_data))
    #
    #     for line in output_lines:
    #         print(line)
    #
    #     if self.log_handle:
    #         for line in output_lines:
    #             self._write_log(line)
    def _display_snapshot(self, snapshot, current_cycle, total_cycles):
        """Display current snapshot to console AND log"""

        output_buffer = io.StringIO()

        with redirect_stdout(output_buffer):
            timestamp = time.ctime(snapshot['timestamp'])
            print("=" * 45)
            print(f"  Cycle {current_cycle}/{total_cycles} - {timestamp}")
            print("=" * 45)

            for service_name in self.config.settings.check_services:
                if service_name in snapshot:
                    service_data = snapshot[service_name]
                    self._display_service_status(service_name, service_data)

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

        status_icon = "✅" if status == 'OK' else "❌"
        print(f"{status_icon} {service_name.upper()}: {status} ({response_time}s)")

        display_methods = {
            'nova': self._display_nova_details,
            'keystone': self._display_keystone_details,
            'neutron': self._display_neutron_details,
            'rabbitmq': self._display_rabbitmq_details,
            'galera': self._display_mariadb_details,
            'cinder': self._display_cinder_details
        }

        if status == 'OK' and service_name in display_methods:
            display_methods[service_name](service_data)
        elif status == 'ERROR':
            error_message = service_data.get('error', 'Unknown error')
            print(f"  Error: {error_message}")

            # Additional debug information for RabbitMQ
            if service_name == 'rabbitmq':
                print(f"  Debug - service_data keys: {list(service_data.keys())}")
                if 'cluster' in service_data:
                    cluster = service_data['cluster']
                    print(f"  Reachable nodes: {cluster.get('reachable_nodes', [])}")
                    print(f"  Unreachable nodes: {cluster.get('unreachable_nodes', [])}")

    def _display_rabbitmq_details(self, rabbit_data):
        """Display RabbitMQ cluster health with per-source perspective"""
        cluster = rabbit_data['cluster']
        total_nodes = rabbit_data['total_nodes']
        reachable_nodes = rabbit_data['reachable_nodes']

        # Determine group status icon
        group_icon = "🟩" if reachable_nodes == total_nodes else "⚠️"
        print(f"  {group_icon} Nodes: {reachable_nodes}/{total_nodes} reachable")

        # Display each source node's perspective
        for source_hostname, details in cluster['node_details'].items():
            response_time = details.get('response_time', '?')

            print(f"    🟢 ({response_time}s) {source_hostname}:")

            # Display queues from THIS source's perspective
            queues = details.get('queues', {})
            print(f"      📊 Queues: {queues.get('total', 0)} total, "
                  f"{queues.get('messages', 0)} messages "
                  f"({queues.get('messages_ready', 0)} ready, "
                  f"{queues.get('messages_unacknowledged', 0)} unacked)")

            # Display ALL nodes from this source's perspective
            all_nodes = details.get('all_nodes', {})
            for target_hostname, node_info in all_nodes.items():
                node_status = node_info.get('status', 'unknown')
                status_emoji = "🟢" if node_status == 'running' else "🔴"

                print(f"      {status_emoji} {target_hostname} ({node_status}):")

                # Display resources
                resources = node_info.get('resources', {})
                if resources:
                    proc_used = resources.get('proc_used', 0)
                    proc_total = resources.get('proc_total', 0)
                    mem_used_mb = resources.get('mem_used', 0) // 1024 // 1024
                    mem_limit_mb = resources.get('mem_limit', 0) // 1024 // 1024
                    print(f"        📈 Resources: {proc_used}/{proc_total} procs, "
                          f"{mem_used_mb}MB/{mem_limit_mb}MB memory")

                # Display alarms
                alarms = []
                if resources.get('mem_alarm'):
                    alarms.append("🚨 Memory alarm")
                if resources.get('disk_free_alarm'):
                    alarms.append("🚨 Disk alarm")

                if alarms:
                    print(f"      {' | '.join(alarms)}")

    def _get_rabbitmq_status_emoji(self, node_status):
        """Get emoji for RabbitMQ node status"""
        emoji_map = {
            'running': '✅',
            'not_running': '⚠️',
            'unknown': '❓',
            'syncing': '🔄'
        }
        return emoji_map.get(node_status, '⚪')

    def _display_cinder_details(self, cinder_data):
        """Display Cinder-specific details"""
        services = cinder_data['services']
        backends = cinder_data['backends']

        print(f"  Services: {services['up']}/{services['total']} up")

        # Display all services with binary type
        for binary, stats in services['by_binary'].items():
            for detail in stats['details']:
                status_icon = "🟢" if detail['state'] == 'up' else "🔴"
                print(f"    {status_icon} {binary} on {detail['host']} - {detail['state']}")

        # Display storage backends
        if backends['details']:
            print(f"  Storage Backends: {backends['total']} backends")
            for backend in backends['details']:
                status_icon = "🟢" if backend['state'] == 'up' else "🔴"
                print(f"    {status_icon} {backend['backend']} ({backend['vendor']}) - {backend['state']}")

    def _display_neutron_details(self, neutron_data):
        """Display Neutron-specific details"""
        agents = neutron_data['agents']
        print(f"  Agents: {agents['up']}/{agents['total']} up")

        if 'critical_agents' in agents:
            print("  Critical Agents:")
            for agent_type, stats in agents['critical_agents'].items():
                if stats['down'] == 0:
                    status_icon = "🟢"
                    status_info = f"{stats['up']} up"
                elif stats['up'] == 0:
                    status_icon = "🔴"
                    status_info = f"{stats['down']} down"
                else:
                    status_icon = "🟡"
                    status_info = f"{stats['up']} up, {stats['down']} down"

                print(f"    {status_icon} {agent_type}: {status_info}")

    def _display_keystone_details(self, keystone_data):
        """Display Keystone-specific details"""
        if keystone_data.get('token_valid'):
            print("  Token: ✅ valid")
        if keystone_data.get('services_count'):
            print(f"  Services: {keystone_data['services_count']} available")

    @staticmethod
    def _display_nova_details(nova_data):
        """Display Nova-specific details"""
        services = nova_data['services']
        critical = services['critical_services']
        hypervisors = nova_data['hypervisors']

        print("  Critical Services:")
        for service_type, instances in critical.items():
            for instance in instances:
                status_icon = "✅" if instance['state'] == 'up' else "❌"
                print(f"    {status_icon} {service_type}: {instance['state']} on {instance['host']}")

        print(f"  Hypervisors: {hypervisors['up']}/{hypervisors['total']} up")
        for hv in hypervisors['details']:
            if hv['state'] == 'up':
                if hv['instances_count'] > 0:
                    status_icon = "🟢"
                    instances_info = f" 📦{hv['instances_count']} VM"
                else:
                    status_icon = "🔵"
                    instances_info = ""
            else:
                status_icon = "🔴"
                instances_info = " (down)"

            print(f"    {status_icon} {hv['name']}{instances_info}")

    def _display_mariadb_details(self, mariadb_data):
        """Display MariaDB/Galera cluster health details"""
        cluster = mariadb_data['cluster']
        total_nodes = mariadb_data['total_nodes']
        reachable_nodes = mariadb_data['reachable_nodes']

        # Determine group status icon
        group_icon = "🟩" if reachable_nodes == total_nodes else "⚠️"
        print(f"  {group_icon} Nodes: {reachable_nodes}/{total_nodes} reachable")

        # Display each node's status and metrics
        for node_name, details in cluster['node_details'].items():
            response_time = details.get('response_time', '?')
            metrics = details.get('metrics', {})

            # Use green circle for all reachable nodes
            print(f"    🟢 ({response_time}s) {node_name}:")

            # Display Galera metrics
            if metrics:
                print(f"      Status: {metrics.get('local_state', 'Unknown')}, "
                      f"Cluster: {metrics.get('cluster_status', 'Unknown')} "
                      f"({metrics.get('cluster_size', 0)} nodes), "
                      f"Ready: {'ON' if metrics.get('node_ready') else 'OFF'}, "
                      f"Connected: {'ON' if metrics.get('connected') else 'OFF'}")

        # Display unreachable nodes
        for node_name in cluster['unreachable_nodes']:
            print(f"    🔴 (timeout) {node_name}:")
            print(f"      Status: Unknown - Connection failed")

    def _get_mariadb_status_emoji(self, metrics):
        """Get emoji for MariaDB node status based on Galera metrics"""
        if not metrics:
            return '⚪'  # Unknown

        is_healthy = (
                metrics.get('cluster_status') == 'Primary' and
                metrics.get('node_ready') is True and
                metrics.get('connected') is True and
                metrics.get('local_state') == 'Synced'
        )

        if is_healthy:
            return '🟢'  # Healthy node - green circle
        elif metrics.get('local_state') in ['Donor', 'Joiner']:
            return '🟡'  # Syncing state - yellow circle
        else:
            return '🔴'  # Degraded or error state - red circle


def get_launch_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description='OpenStack Pulse Monitoring')
    parser.add_argument('--inventory', '-i', help='Path to inventory file')
    parser.add_argument('--config', '-c', help='Path to config.yml file')
    parser.add_argument('--output', '-o', help='Path to output file')
    parser.add_argument('--debug', '-d', action='store_true', help='Enable debug mode')
    return parser.parse_args()


if __name__ == "__main__":
    args = get_launch_args()
    pulse = Pulse(inventory_path=args.inventory, config_path=args.config, debug=args.debug, output_path=args.output)
    pulse.run()

