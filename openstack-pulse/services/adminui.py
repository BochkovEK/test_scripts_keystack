"""
AdminUI Web Portal monitoring
Checks portal availability, authentication and OpenStack services status
"""

import requests
import time
import os
from config.config import ServiceType


class AdminUICheck:
    """
    AdminUI portal health monitoring.

    Provides:
    - Portal authentication via /api/login endpoint
    - Token-based access to status pages
    - OpenStack services status checking via /api/{region}/status_page/os_services
    """

    def __init__(self, config, debug=False):
        """
        Initialize AdminUI health check.

        Args:
            config: Config object providing service authentication
            debug: Enable debug output for troubleshooting
        """
        self.config = config
        self.debug = debug

        # Get AdminUI authentication parameters from config
        auth_params = config.get_service_auth(ServiceType.ADMINUI)

        self.port = auth_params.get('port', 12999)
        self.timeout = auth_params.get('timeout', 5)

        # Determine scheme (HTTP/HTTPS)
        scheme_from_config = (
            auth_params.get('scheme') or
            auth_params.get('protocol') or
            "https"
        )
        self.scheme = scheme_from_config.lower().strip()

        # SSL certificate setup
        cacert_path = auth_params.get('cacert_path') or auth_params.get('path_to_cacert')

        if cacert_path:
            abs_cacert_path = os.path.abspath(cacert_path)
            if os.path.exists(abs_cacert_path):
                self.verify = abs_cacert_path
                if self.debug:
                    print(f"🔒 [ADMINUI_DEBUG] SSL verification enabled using CA: {self.verify}")
            else:
                self.verify = False
                if self.debug:
                    print(f"⚠️ [ADMINUI_DEBUG] CA cert file NOT FOUND at {abs_cacert_path} → SSL verification DISABLED")
        else:
            self.verify = False
            if self.debug:
                print(f"⚠️ [ADMINUI_DEBUG] CA cert path not provided → SSL verification DISABLED")

        # Get credentials from OS_ environment variables
        self.os_username = os.getenv('OS_USERNAME')
        self.os_password = os.getenv('OS_PASSWORD')
        self.os_domain = os.getenv('OS_USER_DOMAIN_NAME', 'Default')
        self.os_project_name = os.getenv('OS_PROJECT_NAME', 'admin')
        self.os_project_domain_name = os.getenv('OS_PROJECT_DOMAIN_NAME', 'Default')
        self.os_auth_url = os.getenv('OS_AUTH_URL')
        self.region = os.getenv('OS_REGION_NAME', 'RegionOne')

        # Extract FQDN from OS_AUTH_URL
        self.fqdn = self._extract_fqdn_from_auth_url()
        self.base_url = self._build_base_url()

        if self.debug:
            print(f"🔧 [ADMINUI_DEBUG] Base URL: {self.base_url}")
            print(f"🔧 [ADMINUI_DEBUG] Region: {self.region}")
            print(f"🔧 [ADMINUI_DEBUG] Username: {self.os_username}")
            print(f"🔧 [ADMINUI_DEBUG] Domain: {self.os_domain}")

        # Initialize HTTP session
        self.session = None
        self._init_session()

    def _extract_fqdn_from_auth_url(self):
        """
        Extract FQDN from OS_AUTH_URL.

        Examples:
        https://portal.example.com:5000 → portal.example.com
        https://portal.example.com:5000/v3 → portal.example.com
        http://192.168.1.10:5000 → 192.168.1.10

        Returns:
            str: FQDN or IP address without port
        """
        if not self.os_auth_url:
            raise ValueError("OS_AUTH_URL environment variable is not set")

        # Remove protocol
        url_without_protocol = self.os_auth_url.split('://')[-1]

        # Remove port and path (keep only host)
        host = url_without_protocol.split(':')[0]
        host = host.split('/')[0]

        return host

    def _build_base_url(self):
        """Build base URL for portal."""
        return f"{self.scheme}://{self.fqdn}:{self.port}"

    def _init_session(self):
        """Initialize HTTP session."""
        self.session = requests.Session()
        self.session.verify = self.verify

        # Default headers
        self.session.headers.update({
            'User-Agent': 'AdminUI-Monitor/1.0',
            'Accept': 'application/json',
            'Content-Type': 'application/json'
        })

        if self.debug:
            print(f"🔧 [ADMINUI_DEBUG] Session initialized")

    def _login_and_get_token(self):
        """
        Authenticate on portal and get access token.

        Returns:
            str: Access token or None on error
        """
        login_url = f"{self.base_url}/api/login"

        login_data = {
            "login": self.os_username,
            "password": self.os_password,
            "user_domain_name": self.os_domain,
            "project_name": self.os_project_name,
            "project_domain_name": self.os_project_domain_name
        }

        try:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Authenticating to {login_url}")
                print(
                    f"🔧 [ADMINUI_DEBUG] Login data: { {k: v for k, v in login_data.items() if k != 'password'} }")

            response = self.session.post(login_url, json=login_data, timeout=self.timeout)
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Response status: {response.status_code}")
                print(f"🔧 [ADMINUI_DEBUG] Response headers: {dict(response.headers)}")
                print(f"🔧 [ADMINUI_DEBUG] Response cookies: {dict(self.session.cookies)}")
                print(f"🔧 [ADMINUI_DEBUG] Response body: {response.text[:200]}...")
            if response.status_code == 200:
                token = response.json().get('X-Auth-Token')

                if token:
                    if self.debug:
                        print(f"🔧 [ADMINUI_DEBUG] Token from body: {token}")
                    return token
                else:
                    if self.debug:
                        print(f"🔧 [ADMINUI_DEBUG] X-Auth-Token header not found in response")
                    return None
            else:
                if self.debug:
                    print(f"🔧 [ADMINUI_DEBUG] Authentication failed with status {response.status_code}")
                return None

        except requests.exceptions.Timeout:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Authentication timeout after {self.timeout}s")
            return None
        except requests.exceptions.ConnectionError:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Connection error during authentication")
            return None
        except Exception as e:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Authentication exception: {str(e)}")
            return None

    def _check_services_status(self, token):
        """
        Check OpenStack services status page.

        Args:
            token: Access token for authentication

        Returns:
            Dictionary with status information or None on error
        """
        status_url = f"{self.base_url}/api/{self.region}/status_page/os_services"

        headers = {
            'X-Auth-Token': token
        }

        try:
            start_time = time.time()

            response = self.session.get(status_url, headers=headers, timeout=self.timeout)
            response_time = time.time() - start_time

            print(f"🔧 [ADMINUI_DEBUG] Response body from status page: {response.text[:200]}...")

            if response.status_code == 200:
                services_data = response.json()

                if self.debug:
                    print(f"🔧 [ADMINUI_DEBUG] Status check completed in {response_time:.3f}s")
                    print(f"🔧 [ADMINUI_DEBUG] Services response: {response.text}")
                return {
                    'status_code': response.status_code,
                    'response_time': round(response_time, 3),
                    'data': services_data
                }
            else:
                if self.debug:
                    print(f"🔧 [ADMINUI_DEBUG] Status check failed with HTTP {response.status_code}")
                return {
                    'status_code': response.status_code,
                    'response_time': round(response_time, 3),
                    'error': f'HTTP {response.status_code}'
                }

        except requests.exceptions.Timeout:
            return {'error': f'Request timeout after {self.timeout}s'}
        except requests.exceptions.ConnectionError:
            return {'error': 'Connection error'}
        except Exception as e:
            return {'error': f'Exception: {str(e)}'}

    def display_details(self, data):
        """
        Display AdminUI portal details in formatted output.

        Args:
            data: Dictionary containing check results
        """
        status = data.get('status', 'UNKNOWN')
        response_time = data.get('response_time', 0)
        status_code = data.get('status_code', '?')
        services_data = data.get('services_data', {})

        print(f"  Status: {status}")
        print(f"  Response time: {response_time}s")
        print(f"  HTTP Status: {status_code}")

        # Display services status if available
        if services_data:
            if isinstance(services_data, dict):
                if 'services' in services_data:
                    services_list = services_data['services']
                    if isinstance(services_list, list):
                        print(f"  Total services: {len(services_list)}")

                        # Show unhealthy services
                        unhealthy = []
                        for s in services_list:
                            if isinstance(s, dict) and s.get('status') != 'up':
                                unhealthy.append(s.get('name', 'unknown'))

                        if unhealthy:
                            print(f"  ⚠️  Unhealthy services ({len(unhealthy)}): {', '.join(unhealthy[:5])}")
                        else:
                            print(f"  ✅ All services healthy")
                elif 'status' in services_data:
                    print(f"  Portal status: {services_data['status']}")
            elif isinstance(services_data, list):
                print(f"  Services: {len(services_data)} total")

        if data.get('error'):
            print(f"  ❌ Error: {data['error']}")

    def run_check(self):
        """
        Execute AdminUI portal health check.

        Returns:
            Dictionary containing check results:
            - status: Overall status ('OK', 'ERROR')
            - response_time: Total check execution time
            - status_code: HTTP status code
            - services_data: Services information from portal
        """
        start_time = time.time()

        if self.debug:
            print(f"🔧 [ADMINUI_DEBUG] Starting portal health check with timeout={self.timeout}s")

        try:
            # Step 1: Login and get token
            token = self._login_and_get_token()

            if not token:
                return {
                    'status': 'ERROR',
                    'response_time': round(time.time() - start_time, 2),
                    'error': 'Authentication failed - check credentials'
                }

            # Step 2: Check services status with token
            status_result = self._check_services_status(token)

            if status_result.get('error'):
                return {
                    'status': 'ERROR',
                    'response_time': round(time.time() - start_time, 2),
                    'error': status_result['error'],
                    'status_code': status_result.get('status_code')
                }

            result = {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'status_code': status_result['status_code'],
                'services_data': status_result.get('data', {})
            }

            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Check completed in {result['response_time']}s, status: OK")

            return result

        except Exception as e:
            error_message = str(e)

            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Check failed with error: {error_message}")

            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': error_message
            }

    def close_sessions(self):
        """Close HTTP session to free resources."""
        if self.session:
            self.session.close()
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Session closed")