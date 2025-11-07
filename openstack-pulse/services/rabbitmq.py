import requests
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed


class RabbitCheck:
    """RabbitMQ cluster health monitoring with optimized sessions and heartbeat"""

    def __init__(self, config):
        self.config = config
        self.auth = (self.config.auth['rabbit_user'], self.config.auth['rabbit_pass'])
        self.port = getattr(getattr(self.config.settings, 'endpoints', None), 'rabbitmq_port', 15672)
        self.rabbitmq_requests_heartbeat = getattr(getattr(self.config.settings, 'rabbitmq', None), 'rabbitmq_requests_heartbeat', 4)
        self.sessions = {}
        self._init_sessions()

        # Heartbeat
        self.heartbeat_stop_event = threading.Event()
        self.heartbeat_thread = threading.Thread(target=self._heartbeat_worker)
        self.heartbeat_thread.daemon = True
        self.heartbeat_thread.start()

    def _init_sessions(self):
        """Initialize separate sessions for each node"""
        urls = self._get_rabbitmq_urls()
        for url in urls:
            host = self._extract_host_from_url(url)
            session = requests.Session()
            session.auth = self.auth
            self.sessions[host] = session

    def _heartbeat_worker(self):
        """Continuous heartbeat worker"""
        while not self.heartbeat_stop_event.is_set():
            self._heartbeat()
            self.heartbeat_stop_event.wait(self.rabbitmq_requests_heartbeat)  # wait 3 sec or until stop

    def _heartbeat(self):
        """Send heartbeat to all nodes to keep connections alive"""
        for url in self._get_rabbitmq_urls():
            session = self._get_session_for_url(url)
            if session:
                try:
                    session.get(f"{url}/api/aliveness-test/%2F", timeout=1)
                except:
                    pass  # Ignore heartbeat errors

    def _extract_host_from_url(self, url):
        """Extract host from URL"""
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
        """Check health of single RabbitMQ node"""
        session = self._get_session_for_url(url)
        if not session:
            return {'reachable': False}

        try:
            response = session.get(f"{url}/api/overview", timeout=3)

            if response.status_code == 200:
                data = response.json()
                return {
                    'reachable': True,
                    'details': {
                        'queues': data.get('object_totals', {}).get('queues', 0),
                        'messages': data.get('queue_totals', {}).get('messages', 0),
                    }
                }
        except Exception:
            pass

        return {'reachable': False}

    def _get_rabbitmq_urls(self):
        """Generate RabbitMQ API URLs from inventory nodes"""
        urls = []
        for controller in self.config.nodes['control']:
            url = f"http://{controller}:{self.port}"
            urls.append(url)
        return urls

    def _check_rabbitmq_cluster(self, urls):
        """Check RabbitMQ cluster nodes in parallel with dedicated sessions"""
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
        """Verify cluster has sufficient nodes for replication"""
        if total_nodes == 1:
            return True  # Single node setup
        elif total_nodes == 2:
            return reachable_count == 2  # Need both nodes
        else:
            quorum = (total_nodes // 2) + 1
            return reachable_count >= quorum  # Need quorum majority

    def close_sessions(self):
        """Close all sessions and stop heartbeat"""
        self.heartbeat_stop_event.set()
        if self.heartbeat_thread.is_alive():
            self.heartbeat_thread.join(timeout=5)

        for host, session in self.sessions.items():
            session.close()
        self.sessions.clear()