import time
import sys
import os
import threading
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

    def __init__(self):
        self.config = Config()
        self.service_checks = {}
        self.latest_results = {}  # Store latest service results
        self.service_ready_events = {}  # Track service readiness
        self._init_service_checks()
        self._start_continuous_checks()

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
                    self.service_checks[service_name] = service_map[service_name](self.config)
                    self.service_ready_events[service_name] = threading.Event()
                    print(f"✅ {service_name} initialized")
                except Exception as e:
                    print(f"⚠️  Failed to initialize {service_name}: {e}")
            else:
                print(f"⚠️  Service '{service_name}' not supported")

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
            print(f"  📡 {service_name} check started")

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

    def run(self):
        """Main monitoring loop - collects snapshots periodically"""
        print("Starting OpenStack Pulse monitoring...")
        print(f"Enabled checks: {', '.join(self.config.settings.check_services)}")

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

                cycle_work_time = time.time() - cycle_start
                print(f"📸 Snapshot {cycle + 1} collection time: {cycle_work_time:.1f}s")

                # Wait for next snapshot (except last one)
                if cycle < total_iterations - 1:
                    interval = self.config.settings.intervals.check_interval
                    print(f"💤 Waiting {interval}s for next snapshot...")
                    time.sleep(interval)

            print(f"\n🎉 Collection completed. Total snapshots: {total_iterations}")

        except KeyboardInterrupt:
            print("\n🛑 Monitoring stopped by user")
        finally:
            self._close_sessions()

    def _close_sessions(self):
        """Close all sessions to free resources"""
        for service_name, check in self.service_checks.items():
            if hasattr(check, 'close_sessions'):
                check.close_sessions()
                print(f"🔒 Closed sessions for {service_name}")

    def _display_snapshot(self, snapshot, current_cycle, total_cycles):
        """Display current snapshot to console"""
        timestamp = time.ctime(snapshot['timestamp'])
        print("=" * 45)
        print(f"  Cycle {current_cycle}/{total_cycles} - {timestamp}")
        print("=" * 45)

        for service_name in self.config.settings.check_services:
            if service_name in snapshot:
                service_data = snapshot[service_name]
                self._display_service_status(service_name, service_data)

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
            'galera': self._display_mariadb_details
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

        print(f"  Nodes: {reachable_nodes}/{total_nodes} reachable")

        # Display each source node's perspective
        for source_hostname, details in cluster['node_details'].items():
            response_time = details.get('response_time', '?')

            print(f"    ✅ ({response_time}s) {source_hostname}:")

            # Display queues from THIS source's perspective
            queues = details.get('queues', {})
            print(f"      Queues: {queues.get('total', 0)} total, "
                  f"{queues.get('messages', 0)} messages "
                  f"({queues.get('messages_ready', 0)} ready, "
                  f"{queues.get('messages_unacknowledged', 0)} unacked)")

            # Display ALL nodes from this source's perspective
            all_nodes = details.get('all_nodes', {})
            for target_hostname, node_info in all_nodes.items():
                node_status = node_info.get('status', 'unknown')
                status_emoji = self._get_rabbitmq_status_emoji(node_status)

                print(f"      {status_emoji} {target_hostname} ({node_status}):")

                # Display resources
                resources = node_info.get('resources', {})
                if resources:
                    proc_used = resources.get('proc_used', 0)
                    proc_total = resources.get('proc_total', 0)
                    mem_used_mb = resources.get('mem_used', 0) // 1024 // 1024
                    mem_limit_mb = resources.get('mem_limit', 0) // 1024 // 1024
                    print(f"        Resources: {proc_used}/{proc_total} procs, "
                          f"{mem_used_mb}MB/{mem_limit_mb}MB memory")

                # Display alarms
                alarms = []
                if resources.get('mem_alarm'):
                    alarms.append("🚨 Memory alarm")
                if resources.get('disk_free_alarm'):
                    alarms.append("🚨 Disk alarm")

                if alarms:
                    print(f"        {' | '.join(alarms)}")
                # else:
                #     print(f"        ✅ No alarms")

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

        # Display services by type
        for binary, stats in services['by_binary'].items():
            if stats['total'] > 0:
                status_icon = "✅" if stats['down'] == 0 else "⚠️"
                print(f"    {status_icon} {binary}: {stats['up']}/{stats['total']} up")

                # Show problematic services
                for detail in stats['details']:
                    if detail['state'] != 'up':
                        print(f"      ❌ {detail['host']} ({detail['state']})")

        # Display storage backends
        if backends['details']:
            print(f"  Storage Backends: {backends['total']} backends")
            for backend in backends['details']:
                vendor_icon = "🟦" if backend['vendor'] == 'Huawei Dorado' else "⚪"
                state_icon = "✅" if backend['state'] == 'up' else "❌"
                print(f"    {state_icon} {vendor_icon} {backend['backend']} ({backend['vendor']}) - {backend['state']}")

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

        print(f"  Nodes: {reachable_nodes}/{total_nodes} reachable")

        # Display each node's status and metrics
        for node_name, details in cluster['node_details'].items():
            response_time = details.get('response_time', '?')
            metrics = details.get('metrics', {})

            # Status emoji based on node health
            status_emoji = self._get_mariadb_status_emoji(metrics)

            print(f"    {status_emoji} ({response_time}s) {node_name}:")

            # Display Galera metrics
            if metrics:
                print(f"      Status: {metrics.get('local_state', 'Unknown')}, "
                      f"Cluster: {metrics.get('cluster_status', 'Unknown')} "
                      f"({metrics.get('cluster_size', 0)} nodes), "
                      f"Ready: {'ON' if metrics.get('node_ready') else 'OFF'}, "
                      f"Connected: {'ON' if metrics.get('connected') else 'OFF'}")

        # Display unreachable nodes
        for node_name in cluster['unreachable_nodes']:
            print(f"    ⚠️ (timeout) {node_name}:")
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
            return '✅'  # Healthy node
        elif metrics.get('local_state') in ['Donor', 'Joiner']:
            return '🔄'  # Syncing state
        else:
            return '⚠️'  # Degraded or error state


if __name__ == "__main__":
    pulse = Pulse()
    pulse.run()