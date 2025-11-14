import openstack
import time
from config.config import ServiceType


class KeystoneCheck:
    def __init__(self, config, debug=False):
        """
        Initialize Keystone health check

        Args:
            config: Config object providing service authentication
        """
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(
            **auth_params,
            identity_api_version='3'
        )

    def run_check(self):
        """Execute Keystone API health check"""
        start_time = time.time()

        try:
            # Authentication check (automatically performed during Connection creation)
            current_user = self.conn.current_user_id
            token_valid = bool(current_user)

            # Get services via OpenStackSDK
            services = list(self.conn.identity.services())

            # Get endpoints
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