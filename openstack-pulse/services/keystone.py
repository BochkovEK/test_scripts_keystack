"""
Keystone Identity Service monitoring
Checks token validation and service catalog
"""

import openstack
import time
from config.config import ServiceType


class KeystoneCheck:
    """
    Keystone Identity Service health monitoring class.

    Provides authentication and service catalog validation for OpenStack:
    - Token validation and authentication
    - Service catalog availability
    - Identity service health checking
    """

    def __init__(self, config, debug=False):
        """
        Initialize Keystone health check.

        Args:
            config: Config object providing service authentication
            debug: Enable debug output for troubleshooting
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(**auth_params)

        if self.debug:
            print(f"🔧 [KEYSTONE_DEBUG] Initialized with auth_url: {auth_params['auth_url']}")

    def run_check(self):
        """
        Execute Keystone health check including token validation and service discovery.

        Returns:
            Dictionary containing check results:
            - status: Overall check status ('OK' or 'ERROR')
            - response_time: API response time in seconds
            - token_valid: Boolean indicating token validity
            - services_count: Number of available identity services
        """
        start_time = time.time()

        try:
            # Get authentication token (primarily for connection validation)
            token_info = self.conn.auth_token

            if self.debug:
                print(f"🔧 [KEYSTONE_DEBUG] Token type: {type(token_info)}")

            # Retrieve available identity services
            services = list(self.conn.identity.services())
            services_count = len(services)

            # Token is considered valid if we successfully retrieved services
            token_valid = True

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
        """
        Display Keystone service details in formatted output.

        Args:
            data: Dictionary containing token validity and service count information
        """
        if self.debug:
            print(f"🔧 [KEYSTONE_DEBUG] display_details data: {data}")

        # Display token validation status
        if data.get('token_valid'):
            print("  Token: ✅ valid")
        else:
            print("  Token: ❌ invalid")

        # Display available services count
        if data.get('services_count'):
            print(f"  Services: {data['services_count']} available")

    def close_sessions(self):
        """Close OpenStack connection sessions to free resources."""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [KEYSTONE_DEBUG] Connections closed")

