import requests
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from config.config import ServiceType
import threading


class RabbitCheck:
    """RabbitMQ cluster health monitoring with optimized sessions"""

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
        urls = self._get_rabbitmq_urls()
        for url in urls:
            host = self._extract_host_from_url(url)
            session = requests.Session()
            session.auth = self.auth
            self.sessions[host] = session

    def _extract_host_from_url(self, url):
        """Extract hostname from URL"""
        return url.replace('http://', '').replace('https://', '').split(':')[0]

    def _get_session_for_url(self, url):
        """Get dedicated session for specific URL"""
        host = self._extract_host_from_url(url)
        return self.sessions.get(host)

    def run_check(self):
        """Execute RabbitMQ cluster health check"""
        start_time = time.time()

        try:
            urls = self._get_rabbitmq_urls()
            cluster_status = self._check_rabbitmq_cluster(urls)

            return {
                'status': 'OK' if cluster_status['healthy'] else 'DEGRADED',
                'response_time': round(time.time() - start_time, 2),
                'cluster': cluster_status,
                'reachable_nodes': len(cluster_status['reachable_nodes']),
                'total_nodes': len(urls)
            }

        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

    def _check_single_node(self, url):
        """
        Check health of single RabbitMQ node

        Args:
            url: RabbitMQ node API URL

        Returns:
            Dictionary with node status and details
        """
        session = self._get_session_for_url(url)
        if not session:
            return {'reachable': False}

        try:
            start_time = time.time()
            response = session.get(f"{url}/api/overview", timeout=3)
            response_time = time.time() - start_time

            if response.status_code == 200:
                data = response.json()
                return {
                    'reachable': True,
                    'details': {
                        'queues': data.get('object_totals', {}).get('queues', 0),
                        'messages': data.get('queue_totals', {}).get('messages', 0),
                        'response_time': round(response_time, 3)
                    }
                }
        except Exception:
            pass

        return {'reachable': False}

    def _get_rabbitmq_urls(self):
        """Generate RabbitMQ API URLs from inventory nodes"""
        urls = []
        for node in self.nodes:
            url = f"http://{node}:{self.port}"
            urls.append(url)
        return urls

    def _check_rabbitmq_cluster(self, urls):
        """
        Check RabbitMQ cluster nodes in parallel

        Args:
            urls: List of RabbitMQ node URLs

        Returns:
            Dictionary with cluster status
        """
        status = {
            'healthy': False,
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'cluster_health': {
                'replication_ok': False,
                'uptime_ok': True,
            },
            'node_details': {}
        }

        with ThreadPoolExecutor(max_workers=len(urls)) as executor:
            future_to_url = {
                executor.submit(self._check_single_node, url): url
                for url in urls
            }

            for future in as_completed(future_to_url):
                url = future_to_url[future]
                try:
                    node_result = future.result()
                    if node_result['reachable']:
                        status['reachable_nodes'].append(url)
                        status['node_details'][url] = node_result['details']
                    else:
                        status['unreachable_nodes'].append(url)
                except Exception:
                    status['unreachable_nodes'].append(url)

        total_nodes = len(urls)
        reachable_count = len(status['reachable_nodes'])
        status['cluster_health']['replication_ok'] = self._check_replication_quorum(total_nodes, reachable_count)
        status['healthy'] = status['cluster_health']['replication_ok']

        return status

    def _check_replication_quorum(self, total_nodes, reachable_count):
        """
        Verify cluster has sufficient nodes for replication

        Args:
            total_nodes: Total number of nodes in cluster
            reachable_count: Number of reachable nodes

        Returns:
            Boolean indicating if replication is healthy
        """
        if total_nodes == 1:
            return True  # Single node setup
        elif total_nodes == 2:
            return reachable_count == 2  # Need both nodes
        else:
            quorum = (total_nodes // 2) + 1
            return reachable_count >= quorum  # Need quorum majority

    def close_sessions(self):
        """Close all sessions to free resources"""
        for host, session in self.sessions.items():
            session.close()
        self.sessions.clear()