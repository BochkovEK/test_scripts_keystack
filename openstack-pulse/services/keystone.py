import time
from keystoneauth1.exceptions import ClientException
from keystoneclient.v3 import client as keystone_client


class KeystoneCheck:
    def __init__(self, session):
        self.session = session

    def run_check(self):
        """Quick Keystone API check"""
        start_time = time.time()

        try:
            # Простая проверка токена
            token = self.session.get_token()
            token_valid = bool(token and len(token) > 10)

            # Проверка сервис-каталога

            keystone = keystone_client.Client(session=self.session)
            services = keystone.services.list()

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'token_valid': token_valid,
                'services_count': len(services),
                'endpoints_available': True
            }

        except ClientException as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': f"Auth failed: {str(e)}"
            }
        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }