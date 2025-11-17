"""
RabbitMQ Message Queue monitoring
Checks cluster health, nodes status, queues and resources
"""

import requests
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from config.config import ServiceType


class RabbitCheck:
    """RabbitMQ cluster health monitoring with detailed node information"""

    def __init__(self, config, debug=False):
        """
        Initialize RabbitMQ health check

        Args:
            config: Config object providing service authentication
            debug: Enable debug output
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.RABBITMQ)

        self.auth = (auth_params['username'], auth_params['password'])
        self.port = auth_params['port']
        self.nodes = auth_params['nodes']

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Initialized with {len(self.nodes)} nodes: {[node[0] for node in self.nodes]}")
            print(f"🔧 [RABBIT_DEBUG] Auth: user={auth_params['username']}, port={self.port}")

        self.sessions = {}
        self._init_sessions()

    def display_details(self, data):
        """Display RabbitMQ-specific details"""
        cluster = data['cluster']
        total_nodes = data['total_nodes']
        reachable_nodes = data['reachable_nodes']

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
                    print(f"        {' | '.join(alarms)}")

    def _init_sessions(self):
        """Initialize separate sessions for each node"""
        urls_with_info = self._get_rabbitmq_urls()
        for display_name, connect_host, url in urls_with_info:
            session = requests.Session()
            session.auth = self.auth
            self.sessions[connect_host] = session

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Created session for {display_name} -> {url}")

    def run_check(self):
        """Execute RabbitMQ cluster health check"""
        start_time = time.time()

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Starting cluster health check")

        try:
            urls = self._get_rabbitmq_urls()
            cluster_status = self._check_rabbitmq_cluster(urls)

            # Determine overall status based on node availability
            reachable_count = len(cluster_status['reachable_nodes'])
            total_count = len(urls)

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Cluster status: {reachable_count}/{total_count} nodes reachable")
                print(f"🔧 [RABBIT_DEBUG] Reachable: {cluster_status['reachable_nodes']}")
                print(f"🔧 [RABBIT_DEBUG] Unreachable: {cluster_status['unreachable_nodes']}")

            if reachable_count == total_count:
                status = 'OK'
            elif reachable_count > 0:
                status = 'DEGRADED'
            else:
                status = 'ERROR'

            result = {
                'status': status,
                'response_time': round(time.time() - start_time, 2),
                'cluster': cluster_status,
                'reachable_nodes': reachable_count,
                'total_nodes': total_count
            }

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Check completed in {result['response_time']}s, status: {status}")

            return result

        except Exception as e:
            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Check failed with error: {str(e)}")
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

    def _check_single_node(self, display_name, connect_host, url):
        """
        Check health of single RabbitMQ node and collect data about ALL nodes
        """
        session = self.sessions.get(connect_host)
        if not session:
            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] No session found for {display_name}")
            return {'reachable': False}

        try:
            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Checking node {display_name} at {url}")

            start_time = time.time()

            overview_response = session.get(f"{url}/api/overview", timeout=3)
            nodes_response = session.get(f"{url}/api/nodes", timeout=3)
            queues_response = session.get(f"{url}/api/queues", timeout=3)

            response_time = time.time() - start_time

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] {display_name} responded in {response_time:.3f}s")

            if overview_response.status_code == 200:
                # Extract data about ALL nodes from this node's perspective
                all_nodes_info = self._extract_all_nodes_details(nodes_response.json())
                overview_info = self._extract_overview_details(overview_response.json())

                if self.debug:
                    print(f"🔧 [RABBIT_DEBUG] {display_name} sees {len(all_nodes_info)} total nodes")
                    print(f"🔧 [RABBIT_DEBUG] {display_name} queues: {overview_info['queues']}")

                return {
                    'reachable': True,
                    'details': {
                        'response_time': round(response_time, 3),
                        'all_nodes': all_nodes_info,
                        'queues': overview_info['queues'],
                    }
                }
            else:
                if self.debug:
                    print(f"🔧 [RABBIT_DEBUG] {display_name} returned status {overview_response.status_code}")

        except Exception as e:
            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] {display_name} check failed: {str(e)}")

        return {'reachable': False}

    def _extract_all_nodes_details(self, nodes_data):
        """Extract status and resources for ALL nodes from /api/nodes response"""
        all_nodes = {}

        for node in nodes_data:
            node_name = self._extract_short_node_name(node.get('name', ''))
            running = node.get('running', False)
            status = 'running' if running else 'not_running'

            all_nodes[node_name] = {
                'status': status,
                'resources': {
                    'proc_used': node.get('proc_used', 0),
                    'proc_total': node.get('proc_total', 0),
                    'mem_used': node.get('mem_used', 0),
                    'mem_limit': node.get('mem_limit', 0),
                    'mem_alarm': node.get('mem_alarm', False),
                    'disk_free_alarm': node.get('disk_free_alarm', False)
                }
            }

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Extracted {len(all_nodes)} nodes from cluster view")

        return all_nodes

    def _extract_short_node_name(self, full_node_name):
        """
        Extract short node name from full RabbitMQ node name
        Example: 'rabbit@ctrl1' -> 'ctrl1'
        """
        if '@' in full_node_name:
            return full_node_name.split('@')[1]
        return full_node_name

    def _extract_overview_details(self, overview_data):
        """
        Extract queue information from /api/overview response
        """
        object_totals = overview_data.get('object_totals', {})
        queue_totals = overview_data.get('queue_totals', {})

        return {
            'queues': {
                'total': object_totals.get('queues', 0),
                'messages': queue_totals.get('messages', 0),
                'messages_ready': queue_totals.get('messages_ready', 0),
                'messages_unacknowledged': queue_totals.get('messages_unacknowledged', 0)
            }
        }

    def _extract_queues_details(self, queues_data):
        pass

    def _get_rabbitmq_urls(self):
        """Generate RabbitMQ API URLs with hostnames"""
        urls_with_info = []
        for display_name, connect_host in self.nodes:
            url = f"http://{connect_host}:{self.port}"
            urls_with_info.append((display_name, connect_host, url))
        return urls_with_info

    def _check_rabbitmq_cluster(self, urls_with_info):
        """Check entire RabbitMQ cluster using thread pool"""
        status = {
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'node_details': {}
        }

        max_workers = min(5, len(urls_with_info))

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Starting cluster check with {max_workers} workers")

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            future_to_info = {
                executor.submit(self._check_single_node, display_name, connect_host, url):
                    (display_name, connect_host, url)
                for display_name, connect_host, url in urls_with_info
            }

            for future in as_completed(future_to_info):
                display_name, connect_host, url = future_to_info[future]
                try:
                    node_result = future.result()

                    if node_result['reachable']:
                        status['reachable_nodes'].append(display_name)
                        status['node_details'][display_name] = node_result['details']
                        if self.debug:
                            print(f"🔧 [RABBIT_DEBUG] ✓ {display_name} is reachable")
                    else:
                        status['unreachable_nodes'].append(display_name)
                        if self.debug:
                            print(f"🔧 [RABBIT_DEBUG] ✗ {display_name} is unreachable")
                except Exception as e:
                    status['unreachable_nodes'].append(display_name)
                    if self.debug:
                        print(f"🔧 [RABBIT_DEBUG] ✗ {display_name} failed with exception: {str(e)}")

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Cluster check completed: {len(status['reachable_nodes'])} reachable, {len(status['unreachable_nodes'])} unreachable")

        return status

    def close_sessions(self):
        """Close all sessions to free resources"""
        for session in self.sessions.values():
            session.close()
        self.sessions.clear()

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Closed all sessions")