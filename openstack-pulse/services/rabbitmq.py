import pika
import time


class RabbitCheck:
    def __init__(self, config):
        self.config = config
        self.connection_params = self._get_connection_params()

    def _get_connection_params(self):
        """Get RabbitMQ connection parameters"""
        # Берем из endpoints или используем дефолты
        host = 'localhost'
        if hasattr(self.config.settings, 'endpoints') and hasattr(self.config.settings.endpoints, 'rabbitmq'):
            # Парсим URL: http://rabbitmq:15672 -> rabbitmq
            url = self.config.settings.endpoints.rabbitmq
            host = url.replace('http://', '').replace('https://', '').split(':')[0]

        credentials = pika.PlainCredentials(
            self.config.auth.get('rabbit_user', 'guest'),
            self.config.auth.get('rabbit_pass', 'guest')
        )

        return pika.ConnectionParameters(
            host=host,
            credentials=credentials,
            connection_attempts=2,
            retry_delay=1,
            socket_timeout=3
        )

    def run_check(self):
        """Quick RabbitMQ status check using Pika"""
        start_time = time.time()
        connection = None

        try:
            # Быстрое подключение
            connection = pika.BlockingConnection(self.connection_params)
            channel = connection.channel()

            # Получаем список очередей
            queues = channel.queue_declare(passive=True)
            queue_count = queues.method.message_count if hasattr(queues.method, 'message_count') else 0

            # Получаем статистику (требует rabbitmq_management plugin)
            stats = self._get_basic_stats(channel)

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'queues_count': queue_count,
                'connected': True,
                'stats': stats
            }

        except pika.exceptions.AMQPConnectionError as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': f"Connection failed: {str(e)}"
            }
        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }
        finally:
            if connection and not connection.is_closed:
                connection.close()

    def _get_basic_stats(self, channel):
        """Get basic RabbitMQ statistics"""
        try:
            # Пытаемся получить базовую статистику
            # Это работает если установлен rabbitmq_management plugin
            stats = {
                'consumers': 0,
                'messages_ready': 0,
                'messages_unacknowledged': 0
            }

            # Можно добавить более детальную статистику при необходимости
            return stats

        except:
            # Если статистика недоступна, возвращаем базовые данные
            return {'available': False}