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

    def _get_rabbitmq_urls(self):
        """Generate RabbitMQ URLs for all controller nodes"""
        return [f"http://{controller}:{self.port}"
                for controller in self.config.nodes['controllers']]

    def run_check(self):
        """Check RabbitMQ cluster health via HTTP API"""
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

    def _check_rabbitmq_cluster(self, urls):
        """Check RabbitMQ cluster health with detailed info"""
        status = {
            'healthy': False,
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'node_details': {}  # ← Добавляем детали по узлам
        }

        for url in urls:
            try:
                response = requests.get(f"{url}/api/overview",
                                        auth=self.auth, timeout=5)
                if response.status_code == 200:
                    overview = response.json()
                    status['reachable_nodes'].append(url)
                    status['node_details'][url] = {
                        'queues': overview.get('object_totals', {}).get('queues', 0),
                        'messages': overview.get('queue_totals', {}).get('messages', 0)
                    }
                else:
                    status['unreachable_nodes'].append(url)
            except:
                status['unreachable_nodes'].append(url)

        # Кластер здоров если больше половины узлов работают
        total = len(urls)
        reachable = len(status['reachable_nodes'])
        status['healthy'] = reachable > total // 2

        return status