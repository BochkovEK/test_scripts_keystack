"""
AdminUI Web Portal monitoring
Checks portal availability, authentication and OpenStack services status
"""

import requests
import time
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from config.config import ServiceType


class AdminUICheck:
    """
    AdminUI portal health monitoring.

    Provides:
    - Portal authentication via /api/login endpoint
    - Token-based access to status pages
    - OpenStack services status checking via /api/{region}/status_page/os_services
    - Parallel health checks across all portal nodes
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
        self.nodes = auth_params.get('nodes', [])
        self.timeout = 3
        self.region = os.getenv('OS_REGION_NAME', 'RegionOne')

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
        self.os_domain = os.getenv('OS_DOMAIN', 'Default')
        self.os_auth_url = os.getenv('OS_AUTH_URL')
        self.region = os.getenv('OS_REGION_NAME', 'RegionOne')

        # Extract FQDN from OS_AUTH_URL (without port 5000)
        self.fqdn = self._extract_fqdn_from_auth_url()

        if self.debug:
            print(f"🔧 [ADMINUI_DEBUG] Config params: port={self.port}, scheme={self.scheme}")
            print(f"🔧 [ADMINUI_DEBUG] OS_ credentials: username={self.os_username}, domain={self.os_domain}")
            print(f"🔧 [ADMINUI_DEBUG] OS_AUTH_URL={self.os_auth_url} → FQDN={self.fqdn}")
            print(f"🔧 [ADMINUI_DEBUG] Region: {self.region}")
            print(f"🔧 [ADMINUI_DEBUG] Nodes: {[n[0] for n in self.nodes] if self.nodes else 'not specified'}")

        # Initialize HTTP sessions for each node
        self.sessions = {}
        self._init_sessions()

    def _extract_fqdn_from_auth_url(self):
        """
        Extract FQDN from OS_AUTH_URL.

        Examples:
        https://portal.example.com:5000 → portal.example.com
        https://portal.example.com:5000/v3 → portal.example.com

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

    def _get_base_url_for_node(self, node_hostname):
        """
        Build base URL for specific portal node.

        Args:
            node_hostname: Node hostname (overrides FQDN from OS_AUTH_URL if provided)

        Returns:
            str: Base URL like https://hostname:12999
        """
        if node_hostname:
            host = node_hostname
        else:
            host = self.fqdn

        return f"{self.scheme}://{host}:{self.port}"

    def _init_sessions(self):
        """Initialize HTTP sessions for each portal node."""
        for display_name, connect_host in self.nodes:
            base_url = self._get_base_url_for_node(connect_host)

            session = requests.Session()
            session.verify = self.verify

            # Default headers
            session.headers.update({
                'User-Agent': 'AdminUI-Monitor/1.0',
                'Accept': 'application/json',
                'Content-Type': 'application/json'
            })

            self.sessions[connect_host] = {
                'session': session,
                'base_url': base_url,
                'display_name': display_name
            }

            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Created session for {display_name} → {base_url}")

    def _login_and_get_token(self, session_info):
        """
        Authenticate on portal and get access token.

        Args:
            session_info: Dictionary with session and node URL info

        Returns:
            str: Access token or None on error
        """
        session = session_info['session']
        base_url = session_info['base_url']
        display_name = session_info['display_name']

        login_url = f"{base_url}/api/login"

        login_data = {
            "login": self.os_username,
            "password": self.os_password,
            "user_domain_name": self.os_domain
        }

        try:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] {display_name}: Authenticating to {login_url}")

            response = session.post(login_url, json=login_data, timeout=self.timeout)

            if response.status_code == 200:
                # Try to get token from response body first, then from headers
                token = None
                response_json = response.json()

                if 'token' in response_json:
                    token = response_json['token']
                elif 'access_token' in response_json:
                    token = response_json['access_token']
                elif 'X-Subject-Token' in response.headers:
                    token = response.headers['X-Subject-Token']

                if token:
                    if self.debug:
                        print(f"🔧 [ADMINUI_DEBUG] {display_name}: Authentication successful, token obtained")
                    return token
                else:
                    if self.debug:
                        print(f"🔧 [ADMINUI_DEBUG] {display_name}: Token not found in response")
                    return None
            else:
                if self.debug:
                    print(f"🔧 [ADMINUI_DEBUG] {display_name}: Authentication failed with status {response.status_code}")
                return None

        except requests.exceptions.Timeout:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] {display_name}: Authentication timeout after {self.timeout}s")
            return None
        except requests.exceptions.ConnectionError:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] {display_name}: Connection error during authentication")
            return None
        except Exception as e:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] {display_name}: Authentication exception: {str(e)}")
            return None

    def _check_services_status(self, session_info, token):
        """
        Check OpenStack services status page.

        Args:
            session_info: Dictionary with session and node URL info
            token: Access token for authentication

        Returns:
            Dictionary with status information or None on error
        """
        session = session_info['session']
        base_url = session_info['base_url']
        display_name = session_info['display_name']

        status_url = f"{base_url}/api/{self.region}/status_page/os_services"

        headers = {
            'X-Auth-Token': token
        }

        try:
            start_time = time.time()

            response = session.get(status_url, headers=headers, timeout=self.timeout)
            response_time = time.time() - start_time

            if response.status_code == 200:
                services_data = response.json()

                if self.debug:
                    print(f"🔧 [ADMINUI_DEBUG] {display_name}: Status check completed in {response_time:.3f}s")

                return {
                    'status_code': response.status_code,
                    'response_time': round(response_time, 3),
                    'data': services_data
                }
            else:
                if self.debug:
                    print(f"🔧 [ADMINUI_DEBUG] {display_name}: Status check failed with HTTP {response.status_code}")
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

    def _check_single_node(self, display_name, connect_host):
        """
        Check single portal node - authenticate and get services status.

        Args:
            display_name: Human-readable node identifier
            connect_host: Network address for connection

        Returns:
            Dictionary containing node reachability and service information
        """
        session_info = self.sessions.get(connect_host)
        if not session_info:
            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] No session found for {display_name}")
            return {'reachable': False, 'error': 'No session available'}

        # Step 1: Login and get token
        token = self._login_and_get_token(session_info)

        if not token:
            return {
                'reachable': False,
                'error': 'Authentication failed - check credentials'
            }

        # Step 2: Check services status with token
        status_result = self._check_services_status(session_info, token)

        if status_result.get('error'):
            return {
                'reachable': True,  # Node is reachable but status check failed
                'authenticated': True,
                'status_error': status_result['error']
            }

        return {
            'reachable': True,
            'authenticated': True,
            'response_time': status_result['response_time'],
            'status_code': status_result['status_code'],
            'services_data': status_result.get('data', {})
        }

    def _check_adminui_cluster(self):
        """
        Perform parallel health checks across all portal nodes.

        Returns:
            Dictionary containing cluster status and node details
        """
        status = {
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'node_details': {},
            'cluster_errors': []
        }

        # Configure thread pool for parallel node checks
        max_workers = min(5, len(self.nodes))

        if self.debug:
            print(f"🔧 [ADMINUI_DEBUG] Starting cluster check with {max_workers} workers, timeout={self.timeout}s")

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit node check tasks to thread pool
            future_to_node = {
                executor.submit(self._check_single_node, display_name, connect_host):
                    (display_name, connect_host)
                for display_name, connect_host in self.nodes
            }

            # Process completed node checks as they finish
            for future in as_completed(future_to_node):
                display_name, connect_host = future_to_node[future]
                try:
                    node_result = future.result()

                    if node_result.get('reachable'):
                        status['reachable_nodes'].append(display_name)
                        status['node_details'][display_name] = node_result
                        if self.debug:
                            print(f"🔧 [ADMINUI_DEBUG] ✓ {display_name} is reachable")
                    else:
                        status['unreachable_nodes'].append(display_name)
                        error_msg = node_result.get('error', 'Unknown error')
                        status['cluster_errors'].append(f"{display_name}: {error_msg}")
                        if self.debug:
                            print(f"🔧 [ADMINUI_DEBUG] ✗ {display_name} is unreachable: {error_msg}")
                except Exception as e:
                    status['unreachable_nodes'].append(display_name)
                    error_msg = f"Exception: {str(e)}"
                    status['cluster_errors'].append(f"{display_name}: {error_msg}")
                    if self.debug:
                        print(f"🔧 [ADMINUI_DEBUG] ✗ {display_name} failed with exception: {error_msg}")

        if self.debug:
            print(
                f"🔧 [ADMINUI_DEBUG] Cluster check completed: {len(status['reachable_nodes'])} reachable, {len(status['unreachable_nodes'])} unreachable")

        return status

    def display_details(self, data):
        """
        Display AdminUI portal details in formatted output.

        Args:
            data: Dictionary containing cluster status and node information
        """
        cluster = data['cluster']
        total_nodes = data['total_nodes']
        reachable_nodes = data['reachable_nodes']

        # Display node reachability summary
        print(f"  Nodes: {reachable_nodes}/{total_nodes} reachable")

        # Display unreachable nodes with detailed error information
        if cluster.get('cluster_errors'):
            for error in cluster['cluster_errors']:
                node_name = error.split(':')[0] if ':' in error else error
                error_message = error.split(':', 1)[1] if ':' in error else error
                print(f"    ❌ {node_name}: {error_message.strip()}")

        # Display detailed status for each reachable node
        for node_name, details in cluster['node_details'].items():
            response_time = details.get('response_time', '?')
            status_code = details.get('status_code', '?')

            print(f"    🟢 ({response_time}s) {node_name}:")
            print(f"      HTTP Status: {status_code}")

            # Display services status if available
            services_data = details.get('services_data', {})
            if services_data:
                # Try to extract useful information from services data
                if isinstance(services_data, dict):
                    # Count services if it's a list or dict
                    if 'services' in services_data:
                        services_list = services_data['services']
                        if isinstance(services_list, list):
                            print(f"      Services: {len(services_list)} total")

                            # Optionally show unhealthy services
                            unhealthy = [s for s in services_list if isinstance(s, dict) and s.get('status') != 'up']
                            if unhealthy:
                                print(f"      ⚠️  Unhealthy services: {len(unhealthy)}")
                    elif isinstance(services_data, list):
                        print(f"      Services: {len(services_data)} total")
                    else:
                        print(f"      Response contains {len(str(services_data))} bytes of data")
                else:
                    print(f"      Response: {str(services_data)[:100]}...")

            # Display authentication errors if any
            if details.get('status_error'):
                print(f"      ⚠️  Status check failed: {details['status_error']}")
            elif not details.get('authenticated'):
                print(f"      🔴 Not authenticated")

    def run_check(self):
        """
        Execute AdminUI portal health check.

        Returns:
            Dictionary containing check results:
            - status: Overall cluster status ('OK', 'DEGRADED', 'ERROR')
            - response_time: Total check execution time
            - cluster: Detailed cluster status information
            - reachable_nodes: Count of reachable nodes
            - total_nodes: Total number of configured nodes
        """
        start_time = time.time()

        if self.debug:
            print(f"🔧 [ADMINUI_DEBUG] Starting portal health check with timeout={self.timeout}s")

        try:
            cluster_status = self._check_adminui_cluster()

            reachable_count = len(cluster_status['reachable_nodes'])
            total_count = len(self.nodes)

            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Cluster status: {reachable_count}/{total_count} nodes reachable")

            # Handle complete cluster unreachable scenario
            if reachable_count == 0 and cluster_status.get('cluster_errors'):
                main_error = cluster_status['cluster_errors'][0]
                if self.debug:
                    print(f"🔧 [ADMINUI_DEBUG] All nodes unreachable, using error: {main_error}")

                return {
                    'status': 'ERROR',
                    'response_time': round(time.time() - start_time, 2),
                    'error': main_error,
                    'cluster': cluster_status,
                    'reachable_nodes': reachable_count,
                    'total_nodes': total_count
                }

            # Determine overall cluster status based on node availability
            if reachable_count == total_count:
                status = 'OK'
            elif reachable_count > 0:
                status = 'DEGRADED'
            else:
                status = 'ERROR'

            result = {
                'status': status,
                'response_time': round(time.time() - start_time, 2),
                'cluster': cluster_status,
                'reachable_nodes': reachable_count,
                'total_nodes': total_count
            }

            if self.debug:
                print(f"🔧 [ADMINUI_DEBUG] Check completed in {result['response_time']}s, status: {status}")

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
        """Close all HTTP sessions to free resources."""
        for node_host, session_info in self.sessions.items():
            session_info['session'].close()
        self.sessions.clear()

        if self.debug:
            print(f"🔧 [ADMINUI_DEBUG] Closed all sessions")