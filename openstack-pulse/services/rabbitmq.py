"""
RabbitMQ Message Queue monitoring
Checks cluster health, nodes status, queues and resources
"""

import requests
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from config.config import ServiceType
import os

class RabbitCheck:
    """
    RabbitMQ cluster health monitoring with detailed node information.

    Provides comprehensive monitoring of RabbitMQ clusters including:
    - Node connectivity and response times
    - Cluster-wide node status from multiple perspectives
    - Queue statistics and message counts
    - Resource utilization (memory, processes, disk alarms)
    - Parallel health checks across all cluster nodes
    """

    def __init__(self, config, debug=False):
        """
        Initialize RabbitMQ health check.

        Args:
            config: Config object providing service authentication
            debug: Enable debug output for troubleshooting
        """
        self.config = config
        self.debug = debug

        auth_params = config.get_service_auth(ServiceType.RABBITMQ)

        self.auth = (auth_params['username'], auth_params['password'])
        self.port = auth_params.get('port', 15672)
        self.nodes = auth_params['nodes']
        self.timeout = 3

        scheme_from_config = (
                auth_params.get('rabbitmq_scheme') or
                auth_params.get('scheme') or
                auth_params.get('protocol')
        )
        self.scheme = scheme_from_config.lower().strip() if scheme_from_config else "https"

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Raw auth_params keys: {list(auth_params.keys())}")
            print(f"🔧 [RABBIT_DEBUG] Raw auth_params content: {auth_params}")

        # ca_cert
        cacert_path = auth_params.get('cacert_path') or auth_params.get('path_to_cacert')

        if cacert_path:
            abs_cacert_path = os.path.abspath(cacert_path)

            if os.path.exists(abs_cacert_path):
                self.verify = abs_cacert_path
                if self.debug:
                    print(f"🔒 [RABBIT_DEBUG] SSL verification enabled using CA: {self.verify}")
            else:
                self.verify = False
                if self.debug:
                    print(f"⚠️ [RABBIT_DEBUG] CA cert file NOT FOUND. "
                          f"Tried to find it at: {abs_cacert_path} → SSL verification is DISABLED.")
        else:
            self.verify = False
            if self.debug:
                print(f"⚠️ [RABBIT_DEBUG] CA cert path not provided in config. SSL verification is DISABLED.")

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Initialized with {len(self.nodes)} nodes: {[n[0] for n in self.nodes]}")
            print(f"🔧 [RABBIT_DEBUG] Final settings → Scheme={self.scheme}, "
                  f"Port={self.port}, Verify={self.verify}, Timeout={self.timeout}s")

        self.sessions = {}
        self._init_sessions()

    def display_details(self, data):
        """
        Display RabbitMQ cluster details in formatted output.

        Args:
            data: Dictionary containing cluster status and node information
        """
        cluster = data['cluster']
        total_nodes = data['total_nodes']
        reachable_nodes = data['reachable_nodes']

        # Display node reachability summary
        print(f"  Nodes: {reachable_nodes}/{total_nodes} reachable")

        # Display unreachable nodes with detailed error information
        if cluster.get('cluster_errors'):
            for error in cluster['cluster_errors']:
                # Extract node name and error message from formatted error string
                node_name = error.split(':')[0] if ':' in error else error
                error_message = error.split(':', 1)[1] if ':' in error else error
                print(f"    ❌ {node_name}: {error_message.strip()}")
                print(f"      Status: Unknown")

        # Display detailed status for each reachable node's perspective
        for source_hostname, details in cluster['node_details'].items():
            response_time = details.get('response_time', '?')

            print(f"    🟢 ({response_time}s) {source_hostname}:")

            # Display queue statistics from this node's perspective
            queues = details.get('queues', {})
            print(f"      📊 Queues: {queues.get('total', 0)} total, "
                  f"{queues.get('messages', 0)} messages "
                  f"({queues.get('messages_ready', 0)} ready, "
                  f"{queues.get('messages_unacknowledged', 0)} unacked)")

            # Display all nodes in cluster from this node's perspective
            all_nodes = details.get('all_nodes', {})
            for target_hostname, node_info in all_nodes.items():
                node_status = node_info.get('status', 'unknown')
                status_emoji = "🟢" if node_status == 'running' else "🔴"

                print(f"      {status_emoji} {target_hostname} ({node_status}):")

                # Display resource utilization for running nodes
                resources = node_info.get('resources', {})
                if resources and node_status == 'running':
                    proc_used = resources.get('proc_used', 0)
                    proc_total = resources.get('proc_total', 0)
                    mem_used_mb = resources.get('mem_used', 0) // 1024 // 1024
                    mem_limit_mb = resources.get('mem_limit', 0) // 1024 // 1024
                    print(f"        📈 Resources: {proc_used}/{proc_total} procs, "
                          f"{mem_used_mb}MB/{mem_limit_mb}MB memory")
                else:
                    print(f"        📈 Resources: Unknown")

                # Display alarm status for running nodes
                if node_status == 'running':
                    alarms = []
                    if resources.get('mem_alarm'):
                        alarms.append("🚨 Memory alarm")
                    if resources.get('disk_free_alarm'):
                        alarms.append("🚨 Disk alarm")

                    if alarms:
                        print(f"        {' | '.join(alarms)}")

    def _init_sessions(self):
        """Initialize separate HTTP sessions for each RabbitMQ node with proper TLS settings."""
        urls_with_info = self._get_rabbitmq_urls()
        for display_name, connect_host, url in urls_with_info:
            session = requests.Session()
            session.auth = self.auth
            session.verify = self.verify  # ← вот главное добавление

            self.sessions[connect_host] = session

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Created session for {display_name} → {url} (verify={session.verify})")

    def run_check(self):
        """
        Execute RabbitMQ cluster health check.

        Returns:
            Dictionary containing check results:
            - status: Overall cluster status ('OK', 'DEGRADED', 'ERROR')
            - response_time: Total check execution time
            - cluster: Detailed cluster status information
            - reachable_nodes: Count of reachable nodes
            - total_nodes: Total number of configured nodes
        """
        start_time = time.time()

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Starting cluster health check with timeout={self.timeout}s")

        try:
            urls_with_info = self._get_rabbitmq_urls()
            cluster_status = self._check_rabbitmq_cluster(urls_with_info)

            # Calculate node reachability statistics
            reachable_count = len(cluster_status['reachable_nodes'])
            total_count = len(urls_with_info)

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Cluster status: {reachable_count}/{total_count} nodes reachable")

            # Handle complete cluster unreachable scenario
            if reachable_count == 0 and cluster_status.get('cluster_errors'):
                main_error = cluster_status['cluster_errors'][0]
                if self.debug:
                    print(f"🔧 [RABBIT_DEBUG] All nodes unreachable, using error: {main_error}")

                return {
                    'status': 'ERROR',
                    'response_time': round(time.time() - start_time, 2),
                    'error': main_error,
                    'cluster': cluster_status,
                    'reachable_nodes': reachable_count,
                    'total_nodes': total_count
                }

            # Determine overall cluster status based on node availability
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
            error_message = str(e)

            # Map common connection errors to user-friendly messages
            if "401" in error_message or "unauthorized" in error_message.lower():
                error_message = f"Not authorized - check RabbitMQ credentials (timeout: {self.timeout}s)"
            elif "timeout" in error_message.lower():
                error_message = f"Global timeout after {self.timeout}s - check network connectivity"

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Check failed with error: {error_message}")

            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': error_message
            }

    def _check_single_node(self, display_name, connect_host, url):
        """
        Check health of single RabbitMQ node and collect cluster-wide data.

        Args:
            display_name: Human-readable node identifier
            connect_host: Network address for connection
            url: Base URL for RabbitMQ HTTP API

        Returns:
            Dictionary containing node reachability and detailed cluster information
        """
        session = self.sessions.get(connect_host)
        if not session:
            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] No session found for {display_name}")
            return {'reachable': False, 'error': 'No session available'}

        try:
            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] Checking node {display_name} at {url} (timeout: {self.timeout}s)")

            start_time = time.time()

            # Query RabbitMQ management API endpoints
            overview_response = session.get(f"{url}/api/overview", timeout=self.timeout)

            # Handle specific HTTP error responses
            if overview_response.status_code == 401:
                return {'reachable': False, 'error': f'401 Unauthorized - check credentials (timeout: {self.timeout}s)'}
            elif overview_response.status_code == 403:
                return {'reachable': False, 'error': f'403 Forbidden - insufficient permissions (timeout: {self.timeout}s)'}
            elif overview_response.status_code == 404:
                return {'reachable': False, 'error': f'404 Not Found - API endpoint unavailable (timeout: {self.timeout}s)'}
            elif overview_response.status_code >= 500:
                return {'reachable': False, 'error': f'HTTP {overview_response.status_code} - Server error (timeout: {self.timeout}s)'}

            # Additional API calls for comprehensive cluster data
            nodes_response = session.get(f"{url}/api/nodes", timeout=self.timeout)
            queues_response = session.get(f"{url}/api/queues", timeout=self.timeout)

            response_time = time.time() - start_time

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] {display_name} responded in {response_time:.3f}s")

            if overview_response.status_code == 200:
                # Extract cluster-wide information from this node's perspective
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
                return {
                    'reachable': False,
                    'error': f'HTTP {overview_response.status_code} - API request failed (timeout: {self.timeout}s)'
                }

        except requests.exceptions.ConnectTimeout:
            return {'reachable': False, 'error': f'Connection timeout after {self.timeout}s - node unreachable'}
        except requests.exceptions.ConnectionError:
            return {'reachable': False, 'error': f'Connection refused - check host/port (timeout: {self.timeout}s)'}
        except requests.exceptions.HTTPError as e:
            return {'reachable': False, 'error': f'HTTP error: {str(e)} (timeout: {self.timeout}s)'}
        except requests.exceptions.Timeout:
            return {'reachable': False, 'error': f'Request timeout after {self.timeout}s - node slow to respond'}
        except Exception as e:
            # Fallback for any other unexpected errors
            error_type = type(e).__name__
            return {'reachable': False, 'error': f'{error_type}: {str(e)} (timeout: {self.timeout}s)'}

    def _extract_all_nodes_details(self, nodes_data):
        """
        Extract status and resource information for ALL nodes from /api/nodes response.

        Args:
            nodes_data: JSON response from RabbitMQ nodes API

        Returns:
            Dictionary containing node status and resource information
        """
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
        Extract short node name from full RabbitMQ node name.

        Example: 'rabbit@ctrl1' -> 'ctrl1'

        Args:
            full_node_name: Full RabbitMQ node name with prefix

        Returns:
            Short node name without prefix
        """
        if '@' in full_node_name:
            return full_node_name.split('@')[1]
        return full_node_name

    def _extract_overview_details(self, overview_data):
        """
        Extract queue statistics from /api/overview response.

        Args:
            overview_data: JSON response from RabbitMQ overview API

        Returns:
            Dictionary containing queue statistics and message counts
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

    def _get_rabbitmq_urls(self):
        """
        Generate RabbitMQ API URLs for all configured nodes.
        """
        urls_with_info = []
        for display_name, connect_host in self.nodes:
            url = f"{self.scheme}://{connect_host}:{self.port}"

            urls_with_info.append((display_name, connect_host, url))

            if self.debug:
                print(f"🔧 [RABBIT_DEBUG] {display_name} → {url} (verify={self.verify})")

        return urls_with_info

    def _check_rabbitmq_cluster(self, urls_with_info):
        """
        Perform parallel health checks across all RabbitMQ cluster nodes.

        Args:
            urls_with_info: List of node URLs to check

        Returns:
            Dictionary containing cluster status and node details
        """
        status = {
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'node_details': {},
            'cluster_errors': []  # Collect all errors for aggregated display
        }

        # Configure thread pool for parallel node checks
        max_workers = min(5, len(urls_with_info))

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Starting cluster check with {max_workers} workers, timeout={self.timeout}s")

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit node check tasks to thread pool
            future_to_info = {
                executor.submit(self._check_single_node, display_name, connect_host, url):
                    (display_name, connect_host, url)
                for display_name, connect_host, url in urls_with_info
            }

            # Process completed node checks as they finish
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
                        error_msg = node_result.get('error', 'Unknown error')
                        status['cluster_errors'].append(f"{display_name}: {error_msg}")
                        if self.debug:
                            print(f"🔧 [RABBIT_DEBUG] ✗ {display_name} is unreachable: {error_msg}")
                except Exception as e:
                    status['unreachable_nodes'].append(display_name)
                    error_msg = f"Exception: {str(e)} (timeout: {self.timeout}s)"
                    status['cluster_errors'].append(f"{display_name}: {error_msg}")
                    if self.debug:
                        print(f"🔧 [RABBIT_DEBUG] ✗ {display_name} failed with exception: {error_msg}")

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Cluster check completed: {len(status['reachable_nodes'])} reachable, {len(status['unreachable_nodes'])} unreachable")

        return status

    def close_sessions(self):
        """Close all HTTP sessions to free resources."""
        for session in self.sessions.values():
            session.close()
        self.sessions.clear()

        if self.debug:
            print(f"🔧 [RABBIT_DEBUG] Closed all sessions")

