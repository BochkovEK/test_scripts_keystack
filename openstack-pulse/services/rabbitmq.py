import requests
import time


class RabbitCheck:
    def __init__(self, config):
        self.config = config
        self.auth = (
            self.config.auth['rabbit_user'],
            self.config.auth['rabbit_pass']
        )
        # Безопасное получение порта через getattr
        self.port = getattr(
            getattr(self.config.settings, 'endpoints', None),
            'rabbitmq_port',
            15672
        )

    # def _get_rabbitmq_urls(self):
    #     """Generate RabbitMQ URLs for all controller nodes"""
    #     return [f"http://{controller}:{self.port}"
    #             for controller in self.config.nodes['controllers']]

    def run_check(self):
        """Check RabbitMQ on all controller nodes"""
        start_time = time.time()

        try:
            print(f"DEBUG RabbitMQ: Starting check...")
            urls = self._get_rabbitmq_urls()
            print(f"DEBUG RabbitMQ: URLs to check: {urls}")

            cluster_status = self._check_rabbitmq_cluster(urls)
            print(f"DEBUG RabbitMQ: Cluster status: {cluster_status}")

            return {
                'status': 'OK' if cluster_status['healthy'] else 'DEGRADED',
                'response_time': round(time.time() - start_time, 2),
                'cluster': cluster_status,
                'reachable_nodes': len(cluster_status['reachable_nodes']),
                'total_nodes': len(urls)
            }

        except Exception as e:
            print(f"DEBUG RabbitMQ: Exception: {e}")
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

    def _get_rabbitmq_urls(self):
        """Generate RabbitMQ URLs for all controller nodes"""
        print(f"DEBUG RabbitMQ: Controllers from inventory: {self.config.nodes['control']}")

        urls = []
        for controller in self.config.nodes['control']:
            url = f"http://{controller}:{self.port}"
            urls.append(url)

        print(f"DEBUG RabbitMQ: Generated URLs: {urls}")
        return urls

    def _check_rabbitmq_cluster(self, urls):
        """Check RabbitMQ cluster health with deep diagnostics"""
        status = {
            'healthy': False,
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'cluster_health': {
                'replication_ok': False,
                'uptime_ok': False,
                'processes_ok': False
            },
            'node_details': {}
        }

        for url in urls:
            try:
                response = requests.get(f"{url}/api/overview", auth=self.auth, timeout=5)

                if response.status_code == 200:
                    overview = response.json()
                    status['reachable_nodes'].append(url)

                    # Получаем детальную информацию по узлу
                    node_stats = self._get_node_stats(url)
                    status['node_details'][url] = node_stats

                else:
                    status['unreachable_nodes'].append(url)

            except Exception as e:
                status['unreachable_nodes'].append(url)
                status['node_details'][url] = {'error': str(e)}

        # Анализ здоровья кластера
        if status['reachable_nodes']:
            status['cluster_health'] = self._analyze_cluster_health(status)

        total = len(urls)
        reachable = len(status['reachable_nodes'])
        status['healthy'] = reachable > total // 2

        return status

    def _get_node_stats(self, url):
        """Get detailed node statistics"""
        try:
            # Overview для базовой информации
            overview = requests.get(f"{url}/api/overview", auth=self.auth, timeout=5).json()

            # Nodes для информации о процессах и uptime
            nodes = requests.get(f"{url}/api/nodes", auth=self.auth, timeout=5).json()

            if nodes:
                node_info = nodes[0]  # Берем первый узел (текущий)

                return {
                    'queues': overview.get('object_totals', {}).get('queues', 0),
                    'messages': overview.get('queue_totals', {}).get('messages', 0),
                    'uptime': node_info.get('uptime', 0),
                    'processes_used': node_info.get('proc_used', 0),
                    'processes_limit': node_info.get('proc_total', 0),
                    'replication_status': 'unknown'  # Нужна отдельная проверка
                }

        except Exception as e:
            return {'error': str(e)}

        return {}

    def _analyze_cluster_health(self, status):
        """Analyze cluster health metrics"""
        health = {
            'replication_ok': False,
            'uptime_ok': False,
            'processes_ok': True  # По умолчанию True, если нет данных
        }

        # Проверка репликации (для 3 нод должно быть 2 реплики)
        reachable_count = len(status['reachable_nodes'])
        health['replication_ok'] = reachable_count >= 2  # Минимум кворум

        # Проверка uptime и процессов для каждого узла
        for url, details in status['node_details'].items():
            if 'error' not in details:
                # Uptime > 10 минут (600000 ms в RabbitMQ)
                if details.get('uptime', 0) < 600000:
                    health['uptime_ok'] = False

                # Processes used < limit
                proc_used = details.get('processes_used', 0)
                proc_limit = details.get('processes_limit', 1)
                if proc_used >= proc_limit:
                    health['processes_ok'] = False

        # Если все узлы имеют uptime > 10min
        if health['uptime_ok'] is not False:  # Не было установлено в False
            health['uptime_ok'] = True

        return health