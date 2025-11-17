"""
Keystone Identity Service monitoring
Checks token validation and service catalog
"""

import openstack
import time
from config.config import ServiceType


class KeystoneCheck:
    def __init__(self, config, debug=False):
        """
        Initialize Keystone health check

        Args:
            config: Config object providing service authentication
            debug: Enable debug output
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(**auth_params)

        if self.debug:
            print(f"🔧 [KEYSTONE_DEBUG] Initialized with auth_url: {auth_params['auth_url']}")

    def run_check(self):
        """Execute Keystone health check"""
        start_time = time.time()

        try:
            # Check token validation
            token_info = self.conn.auth_token
            token_valid = bool(token_info and hasattr(token_info, 'expires_at'))

            # Check service catalog
            services = list(self.conn.identity.services())
            services_count = len(services)

            result = {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'token_valid': token_valid,
                'services_count': services_count
            }

            if self.debug:
                print(f"🔧 [KEYSTONE_DEBUG] Check completed: {result}")

            return result

        except Exception as e:
            error_result = {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

            if self.debug:
                print(f"🔧 [KEYSTONE_DEBUG] Check failed: {error_result}")

            return error_result

    def display_details(self, data):
        """Display Keystone-specific details"""
        if data.get('token_valid'):
            print("  Token: ✅ valid")
        else:
            print("  Token: ❌ invalid")

        if data.get('services_count'):
            print(f"  Services: {data['services_count']} available")

    def close_sessions(self):
        """Close OpenStack connection sessions"""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [KEYSTONE_DEBUG] Connections closed")