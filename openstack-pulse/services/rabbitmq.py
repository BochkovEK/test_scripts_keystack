import requests
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from config.config import ServiceType


class RabbitCheck:
    """RabbitMQ cluster health monitoring with detailed node information"""

    def __init__(self, config):
        """
        Initialize RabbitMQ health check

        Args:
            config: Config object providing service authentication
        """
        self.config = config
        auth_params = config.get_service_auth(ServiceType.RABBITMQ)

        self.auth = (auth_params['username'], auth_params['password'])
        self.port = auth_params['port']
        self.nodes = auth_params['nodes']

        self.sessions = {}
        self._init_sessions()

    def _init_sessions(self):
        """Initialize separate sessions for each node"""
        urls_with_info = self._get_rabbitmq_urls()
        for display_name, connect_host, url in urls_with_info:
            session = requests.Session()
            session.auth = self.auth
            self.sessions[connect_host] = session

    # def _extract_host_from_url(self, url):
    #     """Extract hostname from URL"""
    #     return url.replace('http://', '').replace('https://', '').split(':')[0]

    # def _get_session_for_host(self, connect_host):
    #     """Get dedicated session for specific connect host"""
    #     return self.sessions.get(connect_host)

    def run_check(self):
        """Execute RabbitMQ cluster health check"""
        start_time = time.time()

        try:
            urls = self._get_rabbitmq_urls()
            cluster_status = self._check_rabbitmq_cluster(urls)

            # Determine overall status based on node availability
            reachable_count = len(cluster_status['reachable_nodes'])
            total_count = len(urls)

            if reachable_count == total_count:
                status = 'OK'
            elif reachable_count > 0:
                status = 'DEGRADED'
            else:
                status = 'ERROR'

            return {
                'status': status,
                'response_time': round(time.time() - start_time, 2),
                'cluster': cluster_status,
                'reachable_nodes': reachable_count,
                'total_nodes': total_count
            }

        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

    # def _check_single_node(self, hostname, url):
    #     """
    #     Check health of single RabbitMQ node with sequential API calls
    #
    #     Args:
    #         url: RabbitMQ node API URL
    #
    #     Returns:
    #         Dictionary with node status and detailed metrics
    #     """
    #     session = self._get_session_for_url(url)
    #     if not session:
    #         return {'reachable': False}
    #
    #     try:
    #         start_time = time.time()
    #
    #         overview_response = session.get(f"{url}/api/overview", timeout=3)
    #         nodes_response = session.get(f"{url}/api/nodes", timeout=3)
    #         queues_response = session.get(f"{url}/api/queues", timeout=3)
    #
    #         response_time = time.time() - start_time
    #
    #         if overview_response.status_code == 200:
    #             node_info = self._extract_node_details(nodes_response.json(), hostname)
    #             overview_info = self._extract_overview_details(overview_response.json())
    #             queues_info = self._extract_queues_details(queues_response.json())
    #
    #             return {
    #                 'reachable': True,
    #                 'details': {
    #                     'response_time': round(response_time, 3),
    #                     'node_status': node_info['status'],
    #                     'resources': node_info['resources'],
    #                     'replication': queues_info['replication'],
    #                     'queues': overview_info['queues']
    #                 }
    #             }
    #     except Exception:
    #         pass
    #
    #     return {'reachable': False}

    def _check_single_node(self, display_name, connect_host, url):
        """
        Check health of single RabbitMQ node with sequential API calls
        """
        session = self.sessions.get(connect_host)  # ← сессия по connect_host
        if not session:
            return {'reachable': False}

        try:
            start_time = time.time()

            overview_response = session.get(f"{url}/api/overview", timeout=3)
            nodes_response = session.get(f"{url}/api/nodes", timeout=3)
            queues_response = session.get(f"{url}/api/queues", timeout=3)

            response_time = time.time() - start_time

            if overview_response.status_code == 200:
                # Используем display_name для поиска в API данных
                node_info = self._extract_node_details(nodes_response.json(), display_name)
                overview_info = self._extract_overview_details(overview_response.json())
                queues_info = self._extract_queues_details(queues_response.json())

                return {
                    'reachable': True,
                    'details': {
                        'response_time': round(response_time, 3),
                        'node_status': node_info['status'],
                        'resources': node_info['resources'],
                        'replication': queues_info['replication'],
                        'queues': overview_info['queues']
                    }
                }
        except Exception as e:
            print(f"🔍 DEBUG: {url} exception: {e}")

        return {'reachable': False}

    # def _extract_node_details(self, nodes_data, hostname):
    #     """
    #     Extract node status and resource information from /api/nodes response
    #
    #     Args:
    #         nodes_data: JSON response from /api/nodes endpoint
    #         hostname: Target node hostname
    #
    #     Returns:
    #         Dictionary with node status and resource metrics
    #     """
    #     for node in nodes_data:
    #         if node.get('name') == hostname or node.get('name', '').startswith(hostname):
    #
    #             running = node.get('running', False)
    #             status = 'running' if running else 'not_running'
    #
    #             return {
    #                 'status': status,
    #                 'resources': {
    #                     'proc_used': node.get('proc_used', 0),
    #                     'proc_total': node.get('proc_total', 0),
    #                     'mem_used': node.get('mem_used', 0),
    #                     'mem_limit': node.get('mem_limit', 0),
    #                     'fd_used': node.get('fd_used', 0),
    #                     'fd_total': node.get('fd_total', 0),
    #                     'disk_free': node.get('disk_free', 0)
    #                 }
    #             }
    #
    #     return {
    #         'status': 'unknown',
    #         'resources': {}
    #     }

    def _extract_node_details(self, nodes_data, display_name):
        """
        Extract node status and resource information from /api/nodes response
        """
        # Варианты имен для поиска (на основе диагностики)
        search_names = [
            f"rabbit@{display_name.split('.')[0]}",  # rabbit@ctrl1
            display_name,  # ctrl1.foo.bar.com
            display_name.split('.')[0]  # ctrl1
        ]

        for node in nodes_data:
            node_name = node.get('name', '')
            for search_name in search_names:
                if node_name == search_name or search_name in node_name:
                    running = node.get('running', False)
                    status = 'running' if running else 'not_running'

                    # print(f"🔍 DEBUG: Found node {node_name} for {display_name} (status: {status})")

                    return {
                        'status': status,
                        'resources': {
                            'proc_used': node.get('proc_used', 0),
                            'proc_total': node.get('proc_total', 0),
                            'mem_used': node.get('mem_used', 0),
                            'mem_limit': node.get('mem_limit', 0),
                            'fd_used': node.get('fd_used', 0),
                            'fd_total': node.get('fd_total', 0),
                            'disk_free': node.get('disk_free', 0)
                        }
                    }

        # print(f"🔍 DEBUG: No node found for {display_name}. Tried: {search_names}")
        return {
            'status': 'unknown',
            'resources': {}
        }

    def _extract_overview_details(self, overview_data):
        """
        Extract queue information from /api/overview response

        Args:
            overview_data: JSON response from /api/overview endpoint

        Returns:
            Dictionary with queue statistics
        """
        return {
            'queues': {
                'total': overview_data.get('object_totals', {}).get('queues', 0),
                'messages': overview_data.get('queue_totals', {}).get('messages', 0)
            }
        }

    def _extract_queues_details(self, queues_data):
        """
        Extract replication information from /api/queues response

        Args:
            queues_data: JSON response from /api/queues endpoint

        Returns:
            Dictionary with replication metrics
        """
        mirrored_queues = 0
        synchronized_queues = 0

        for queue in queues_data:
            if queue.get('arguments', {}).get('x-ha-policy') == 'all':
                mirrored_queues += 1
                # Simplified synchronization check
                if queue.get('messages') == queue.get('messages_ready', 0):
                    synchronized_queues += 1

        return {
            'replication': {
                'mirrored_queues': mirrored_queues,
                'synchronized_queues': synchronized_queues,
                'unsynchronized_queues': mirrored_queues - synchronized_queues
            }
        }

    def _get_rabbitmq_urls(self):
        """Generate RabbitMQ API URLs with hostnames"""
        urls_with_info = []
        for display_name, connect_host in self.nodes:
            url = f"http://{connect_host}:{self.port}"
            urls_with_info.append((display_name, connect_host, url))
        return urls_with_info

    def _check_rabbitmq_cluster(self, urls_with_info):
        status = {
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'node_details': {}
        }

        with ThreadPoolExecutor(max_workers=min(5, len(urls_with_info))) as executor:
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
                    else:
                        status['unreachable_nodes'].append(display_name)
                except Exception:
                    status['unreachable_nodes'].append(display_name)

        return status

    def close_sessions(self):
        """Close all sessions to free resources"""
        for host, session in self.sessions.items():
            session.close()
        self.sessions.clear()