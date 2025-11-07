import openstack
import time


class KeystoneCheck:
    def __init__(self, session):
        self.conn = openstack.connection.Connection(
            session=session,
            identity_api_version='3'
        )

    def run_check(self):
        """Quick Keystone API check using OpenStackSDK"""
        start_time = time.time()

        try:
            # Проверка аутентификации (автоматически делается при создании Connection)
            current_user = self.conn.current_user_id
            token_valid = bool(current_user)

            # Получение сервисов через OpenStackSDK
            services = list(self.conn.identity.services())

            # Получение эндпоинтов
            endpoints = list(self.conn.identity.endpoints())

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'token_valid': token_valid,
                'current_user_id': current_user,
                'services_count': len(services),
                'endpoints_count': len(endpoints)
            }

        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }