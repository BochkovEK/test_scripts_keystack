"""
Cinder Block Storage service monitoring
Checks volume services, scheduler services and storage backends
"""

import openstack
import time
from typing import Dict, Any
from config.config import ServiceType


class CinderCheck:
    """
    Cinder Block Storage service health monitoring class.

    Provides comprehensive monitoring of Cinder services including:
    - Volume services (cinder-volume)
    - Scheduler services (cinder-scheduler)
    - Backup services (cinder-backup)
    - Storage backends health and status
    """

    def __init__(self, config, debug=False):
        """
        Initialize Cinder health check.

        Args:
            config: Config object providing service authentication
            debug: Enable debug output for troubleshooting
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(**auth_params)

        if self.debug:
            print(f"🔧 [CINDER_DEBUG] Initialized with auth_url: {auth_params['auth_url']}")

    def display_details(self, data):
        """
        Display Cinder service details in a formatted output.

        Args:
            data: Dictionary containing service and backend statistics
        """
        services = data['services']
        backends = data['backends']

        print(f"  Services: {services['up']}/{services['total']} up")

        # Display service status with smart formatting
        for binary, stats in services['by_binary'].items():
            if stats['total'] > 0:
                up_count = stats['up']
                down_count = stats['down']

                if down_count == 0:
                    # All services healthy - show compact format
                    print(f"    🟢 {binary}: {up_count} up")
                else:
                    # Services with issues - show detailed breakdown
                    print(f"    ⚠️ {binary}:")
                    for detail in stats['details']:
                        status_icon = self._get_service_status_icon(detail['state'], detail['status'])
                        status_text = f": state - {detail['state']}, status - {detail['status']}"
                        print(f"      {status_icon} {detail['host']}{status_text}")

        # Display storage backend information
        if backends['details']:
            print(f"  Storage Backends: {backends['total']} backends")
            for backend in backends['details']:
                status_icon = "🟢" if backend['state'] == 'up' else "🔴"
                print(f"    {status_icon} {backend['backend']} ({backend['vendor']}) - {backend['state']}")

    def _get_service_status_icon(self, state: str, status: str) -> str:
        """
        Determine appropriate status icon based on service state and status.

        Args:
            state: Service state ('up', 'down')
            status: Service status ('enabled', 'disabled')

        Returns:
            Status icon string
        """
        if state == 'down':
            return "🔴"
        elif status == 'disabled':
            return "⚠️"
        else:
            return "🟢"

    def run_check(self):
        """
        Execute comprehensive Cinder services health check.

        Returns:
            Dictionary containing check results including:
            - Overall status
            - Response time
            - Service statistics
            - Backend statistics
        """
        start_time = time.time()

        try:
            # Retrieve all Cinder services from OpenStack
            services = list(self.conn.block_storage.services())
            service_stats = self._analyze_services(services)
            backend_stats = self._analyze_backends(services)

            result = {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'services': service_stats,
                'backends': backend_stats
            }

            if self.debug:
                print(f"🔧 [CINDER_DEBUG] Check completed: {len(services)} services, {backend_stats['total']} backends")

            return result

        except Exception as e:
            error_result = {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

            if self.debug:
                print(f"🔧 [CINDER_DEBUG] Check failed: {error_result}")

            return error_result

    def _analyze_services(self, services) -> Dict[str, Any]:
        """
        Analyze Cinder service status and generate statistics.

        Args:
            services: List of Cinder service objects from OpenStack

        Returns:
            Dictionary containing service statistics organized by binary type
        """
        stats = {
            'total': len(services),
            'up': 0,
            'down': 0,
            'by_binary': {
                'cinder-volume': {'total': 0, 'up': 0, 'down': 0, 'details': []},
                'cinder-scheduler': {'total': 0, 'up': 0, 'down': 0, 'details': []},
                'cinder-backup': {'total': 0, 'up': 0, 'down': 0, 'details': []}
            }
        }

        for service in services:
            binary = service.binary
            host = service.host
            state = service.state
            status = service.status

            # Update overall service statistics
            if state == 'up':
                stats['up'] += 1
            else:
                stats['down'] += 1

            # Update statistics by service type
            if binary in stats['by_binary']:
                stats['by_binary'][binary]['total'] += 1
                if state == 'up':
                    stats['by_binary'][binary]['up'] += 1
                else:
                    stats['by_binary'][binary]['down'] += 1

                stats['by_binary'][binary]['details'].append({
                    'host': host,
                    'state': state,
                    'status': status,
                    'zone': getattr(service, 'zone', 'unknown')
                })

        return stats

    def _analyze_backends(self, services) -> Dict[str, Any]:
        """
        Analyze storage backends from cinder-volume services.

        Args:
            services: List of Cinder service objects

        Returns:
            Dictionary containing backend statistics and details
        """
        stats = {
            'total': 0,
            'details': []
        }

        # Filter and process only cinder-volume services (storage backends)
        volume_services = [s for s in services if s.binary == 'cinder-volume']
        stats['total'] = len(volume_services)

        for service in volume_services:
            backend_info = {
                'host': service.host,
                'backend': self._extract_backend_name(service.host),
                'vendor': self._detect_vendor(service.host),
                'state': service.state,
                'status': service.status,
                'zone': getattr(service, 'zone', 'unknown')
            }
            stats['details'].append(backend_info)

        return stats

    def _extract_backend_name(self, hostname: str) -> str:
        """
        Extract backend name from host string.

        Handles backend naming conventions like "vendor@backend_name".

        Args:
            hostname: Service host string from OpenStack

        Returns:
            Extracted backend name
        """
        # Handle vendor@backend naming convention
        if '@' in hostname:
            return hostname.split('@')[1]
        return hostname

    def _detect_vendor(self, hostname: str) -> str:
        """
        Detect storage vendor from hostname patterns.

        Args:
            hostname: Service hostname string

        Returns:
            Detected vendor name
        """
        hostname_lower = hostname.lower()

        if 'huawei' in hostname_lower or 'dorado' in hostname_lower:
            return 'Huawei Dorado'
        elif 'lvm' in hostname_lower:
            return 'LVM'
        elif 'ceph' in hostname_lower:
            return 'Ceph'
        else:
            return 'Unknown'

    def close_sessions(self):
        """Close OpenStack connection sessions to free resources."""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [CINDER_DEBUG] Connections closed")

