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
            # print(f"DEBUG RabbitMQ: Starting check...")
            urls = self._get_rabbitmq_urls()
            # print(f"DEBUG RabbitMQ: URLs to check: {urls}")
            #
            cluster_status = self._check_rabbitmq_cluster(urls)
            # print(f"DEBUG RabbitMQ: Cluster status: {cluster_status}")

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
        # print(f"DEBUG RabbitMQ: Controllers from inventory: {self.config.nodes['control']}")

        urls = []
        for controller in self.config.nodes['control']:
            url = f"http://{controller}:{self.port}"
            urls.append(url)

        # print(f"DEBUG RabbitMQ: Generated URLs: {urls}")
        return urls

    def _check_rabbitmq_cluster(self, urls):
        """Check RabbitMQ cluster in parallel"""
        status = {
            'healthy': False,
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'cluster_health': {'replication_ok': False, 'uptime_ok': True, 'processes_ok': True},
            'node_details': {}
        }

        with ThreadPoolExecutor(max_workers=len(urls)) as executor:
            # Запускаем проверку всех узлов параллельно
            future_to_url = {executor.submit(self._check_single_node, url): url for url in urls}

            for future in as_completed(future_to_url):
                url = future_to_url[future]
                try:
                    node_result = future.result()
                    if node_result['reachable']:
                        status['reachable_nodes'].append(url)
                        status['node_details'][url] = node_result['details']
                        # Анализируем здоровье
                        self._analyze_node_health(node_result['details'], status['cluster_health'])
                    else:
                        status['unreachable_nodes'].append(url)
                except Exception:
                    status['unreachable_nodes'].append(url)

        # Анализ репликации
        total_nodes = len(urls)
        reachable_count = len(status['reachable_nodes'])
        status['cluster_health']['replication_ok'] = self._check_replication(total_nodes, reachable_count)
        status['healthy'] = reachable_count > total_nodes // 2

        return status

    def _check_single_node(self, url):
        """Check single RabbitMQ node (runs in parallel)"""
        try:
            response = requests.get(f"{url}/api/nodes", auth=self.auth, timeout=5)
            if response.status_code == 200:
                nodes_data = response.json()
                if nodes_data:
                    node_info = nodes_data[0]
                    return {
                        'reachable': True,
                        'details': {
                            'uptime': node_info.get('uptime', 0),
                            'processes_used': node_info.get('proc_used', 0),
                            'processes_limit': node_info.get('proc_total', 0),
                            'running': node_info.get('running', True)
                        }
                    }
        except Exception:
            pass

        return {'reachable': False}

    def _analyze_node_health(self, node_info, cluster_health):
        """Analyze health metrics during main loop"""
        # Uptime
        if node_info.get('uptime', 0) < 600000:
            cluster_health['uptime_ok'] = False

        # Processes
        proc_used = node_info.get('proc_used', 0)
        proc_limit = node_info.get('proc_total', 1)
        if proc_used >= proc_limit * 0.8:
            cluster_health['processes_ok'] = False

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
            'processes_ok': True
        }

        total_nodes = len(status['reachable_nodes']) + len(status['unreachable_nodes'])
        reachable_count = len(status['reachable_nodes'])

        # Логика репликации для RabbitMQ кластера:
        if total_nodes == 1:
            # Одна нода - репликации нет, но это нормально
            health['replication_ok'] = True
        elif total_nodes == 2:
            # Две ноды - нужны обе для кворума
            health['replication_ok'] = (reachable_count == 2)
        elif total_nodes >= 3:
            # Три и более нод - нужен кворум N/2 + 1
            quorum = (total_nodes // 2) + 1
            health['replication_ok'] = (reachable_count >= quorum)
        else:
            health['replication_ok'] = False

        # Проверка uptime и процессов
        uptime_ok = True
        processes_ok = True

        for url, details in status['node_details'].items():
            if 'error' not in details:
                # Uptime > 10 минут (600000 ms в RabbitMQ)
                if details.get('uptime', 0) < 600000:
                    uptime_ok = False

                # Processes used < limit (80% от лимита как предупреждение)
                proc_used = details.get('processes_used', 0)
                proc_limit = details.get('processes_limit', 1)
                if proc_used >= proc_limit * 0.8:  # 80% лимита
                    processes_ok = False

        health['uptime_ok'] = uptime_ok
        health['processes_ok'] = processes_ok

        return health