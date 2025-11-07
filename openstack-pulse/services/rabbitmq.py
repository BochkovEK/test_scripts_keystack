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
        print(f"DEBUG RabbitMQ: Controllers from inventory: {self.config.nodes['controllers']}")

        urls = []
        for controller in self.config.nodes['controllers']:
            url = f"http://{controller}:{self.port}"
            urls.append(url)

        print(f"DEBUG RabbitMQ: Generated URLs: {urls}")
        return urls

    def _check_rabbitmq_cluster(self, urls):
        """Check RabbitMQ cluster health"""
        print(f"DEBUG RabbitMQ: Checking {len(urls)} nodes...")

        status = {
            'healthy': False,
            'reachable_nodes': [],
            'unreachable_nodes': []
        }

        for url in urls:
            try:
                print(f"DEBUG RabbitMQ: Testing {url}...")
                response = requests.get(f"{url}/api/overview",
                                        auth=self.auth, timeout=5)
                print(f"DEBUG RabbitMQ: Response status: {response.status_code}")

                if response.status_code == 200:
                    status['reachable_nodes'].append(url)
                    print(f"DEBUG RabbitMQ: ✅ {url} is reachable")
                else:
                    status['unreachable_nodes'].append(url)
                    print(f"DEBUG RabbitMQ: ❌ {url} returned {response.status_code}")

            except Exception as e:
                status['unreachable_nodes'].append(url)
                print(f"DEBUG RabbitMQ: ❌ {url} failed: {e}")

        # Кластер здоров если больше половины узлов работают
        total = len(urls)
        reachable = len(status['reachable_nodes'])
        status['healthy'] = reachable > total // 2

        print(f"DEBUG RabbitMQ: Final status - {reachable}/{total} reachable, healthy: {status['healthy']}")
        return status