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
        """Check RabbitMQ cluster health with queue statistics"""
        status = {
            'healthy': False,
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'queues_count': 0,
            'total_messages': 0,
            'node_details': {}
        }

        for url in urls:
            try:
                response = requests.get(f"{url}/api/overview",
                                        auth=self.auth, timeout=5)

                if response.status_code == 200:
                    overview = response.json()
                    status['reachable_nodes'].append(url)

                    # Собираем статистику очередей
                    queue_totals = overview.get('queue_totals', {})
                    object_totals = overview.get('object_totals', {})

                    status['queues_count'] = object_totals.get('queues', 0)
                    status['total_messages'] = queue_totals.get('messages', 0)

                    status['node_details'][url] = {
                        'queues': object_totals.get('queues', 0),
                        'messages': queue_totals.get('messages', 0),
                        'consumers': object_totals.get('consumers', 0)
                    }

                else:
                    status['unreachable_nodes'].append(url)

            except Exception:
                status['unreachable_nodes'].append(url)

        # Кластер здоров если больше половины узлов работают
        total = len(urls)
        reachable = len(status['reachable_nodes'])
        status['healthy'] = reachable > total // 2

        return status