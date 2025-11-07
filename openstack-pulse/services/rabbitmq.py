import requests
import time
from concurrent.futures import ThreadPoolExecutor, as_completed


class RabbitCheck:
    """RabbitMQ cluster health monitoring"""

    def __init__(self, config):
        self.config = config
        self.auth = (self.config.auth['rabbit_user'], self.config.auth['rabbit_pass'])
        self.port = getattr(getattr(self.config.settings, 'endpoints', None), 'rabbitmq_port', 15672)
        # Session для reuse соединений
        self.session = requests.Session()
        self.session.auth = self.auth

    def run_check(self):
        """Execute RabbitMQ cluster health check"""
        start_time = time.time()
        print(f"DEBUG Rabbit: Starting check at {time.time()}")

        try:
            urls = self._get_rabbitmq_urls()
            print(f"DEBUG Rabbit: URLs to check: {urls}")

            cluster_status = self._check_rabbitmq_cluster(urls)
            print(f"DEBUG Rabbit: Cluster check completed at {time.time()}")

            return {
                'status': 'OK' if cluster_status['healthy'] else 'DEGRADED',
                'response_time': round(time.time() - start_time, 2),
                'cluster': cluster_status,
                'reachable_nodes': len(cluster_status['reachable_nodes']),
                'total_nodes': len(urls)
            }

        except Exception as e:
            print(f"DEBUG Rabbit: Exception: {e}")
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

    # def _check_single_node(self, url):
    #     """Check health of single RabbitMQ node (optimized)"""
    #     print(f"DEBUG Rabbit: Checking {url} at {time.time()}")
    #     try:
    #         # Single API call to overview endpoint
    #         response = requests.get(f"{url}/api/overview", auth=self.auth, timeout=3)
    #         print(f"DEBUG Rabbit: {url} response at {time.time()}")
    #
    #         if response.status_code == 200:
    #             data = response.json()
    #             return {
    #                 'reachable': True,
    #                 'details': {
    #                     'queues': data.get('object_totals', {}).get('queues', 0),
    #                     'messages': data.get('queue_totals', {}).get('messages', 0),
    #                 }
    #             }
    #     except Exception as e:
    #         print(f"DEBUG Rabbit: {url} failed: {e}")
    #         pass
    #
    #     return {'reachable': False}

    def _check_single_node(self, url):
        """Check health of single RabbitMQ node with session"""
        try:
            # Используем сессию для reuse соединений
            response = self.session.get(f"{url}/api/overview", timeout=3)

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

    # def _check_rabbitmq_cluster(self, urls):
    #     """Check RabbitMQ cluster nodes in parallel"""
    #     status = {
    #         'healthy': False,
    #         'reachable_nodes': [],
    #         'unreachable_nodes': [],
    #         'cluster_health': {
    #             'replication_ok': False,
    #             'uptime_ok': True,
    #         },
    #         'node_details': {}
    #     }
    #
    #     with ThreadPoolExecutor(max_workers=len(urls)) as executor:
    #         future_to_url = {
    #             executor.submit(self._check_single_node, url): url
    #             for url in urls
    #         }
    #
    #         for future in as_completed(future_to_url):
    #             url = future_to_url[future]
    #             try:
    #                 node_result = future.result()
    #                 if node_result['reachable']:
    #                     status['reachable_nodes'].append(url)
    #                     status['node_details'][url] = node_result['details']
    #                     # self._analyze_node_health(node_result['details'], status['cluster_health'])
    #                 else:
    #                     status['unreachable_nodes'].append(url)
    #             except Exception:
    #                 status['unreachable_nodes'].append(url)
    #
    #     total_nodes = len(urls)
    #     reachable_count = len(status['reachable_nodes'])
    #     status['cluster_health']['replication_ok'] = self._check_replication_quorum(total_nodes, reachable_count)
    #     status['healthy'] = status['cluster_health']['replication_ok']
    #
    #     return status

    def _check_rabbitmq_cluster(self, urls):
        """Check RabbitMQ cluster nodes in parallel with session"""
        status = {
            'healthy': False,
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'cluster_health': {
                'replication_ok': False,
                'uptime_ok': True,  # ← ВОССТАНОВИТЬ uptime_ok
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

    def _analyze_node_health(self, node_details, cluster_health):
        """Analyze node-specific health metrics"""
        # Check uptime (RabbitMQ reports uptime in milliseconds)
        if node_details.get('uptime', 0) < 600000:  # 10 minutes
            cluster_health['uptime_ok'] = False

        # Check process usage (warn at 80% limit)
        proc_used = node_details.get('processes_used', 0)
        proc_limit = node_details.get('processes_limit', 1)
        if proc_used >= proc_limit * 0.8:
            cluster_health['processes_ok'] = False