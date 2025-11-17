"""
Cinder Block Storage service monitoring
Checks volume services, scheduler services and storage backends
"""

import openstack
import time
from typing import Dict, List, Any
from config.config import ServiceType


class CinderCheck:
    def __init__(self, config, debug=False):
        """
        Initialize Cinder health check

        Args:
            config: Config object providing service authentication
            debug: Enable debug output
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(**auth_params)

        if self.debug:
            print(f"🔧 [CINDER_DEBUG] Initialized with auth_url: {auth_params['auth_url']}")

    def display_details(self, data):
        """Display Cinder-specific details"""
        services = data['services']
        backends = data['backends']

        print(f"  Services: {services['up']}/{services['total']} up")

        # Smart display for service types - show details only if problems
        for binary, stats in services['by_binary'].items():
            if stats['total'] > 0:
                up_count = stats['up']
                down_count = stats['down']

                if down_count == 0:
                    # All services up - show compact
                    print(f"    🟢 {binary}: {up_count} up")
                else:
                    # Some services down - show detailed breakdown
                    print(f"    ⚠️ {binary}:")
                    for detail in stats['details']:
                        # Determine icon based on state and status
                        if detail['state'] == 'down':
                            status_icon = "🔴"
                        elif detail['status'] == 'disabled':
                            status_icon = "⚠️"
                        else:
                            status_icon = "🟢"

                        # Always show full status for all nodes in problematic service
                        status_text = f": state - {detail['state']}, status - {detail['status']}"
                        print(f"      {status_icon} {detail['host']}{status_text}")

        # Display storage backends
        if backends['details']:
            print(f"  Storage Backends: {backends['total']} backends")
            for backend in backends['details']:
                status_icon = "🟢" if backend['state'] == 'up' else "🔴"
                print(f"    {status_icon} {backend['backend']} ({backend['vendor']}) - {backend['state']}")

    def run_check(self):
        """Execute Cinder services health check"""
        start_time = time.time()

        try:
            # Get all Cinder services
            services = list(self.conn.block_storage.services())
            service_stats = self._analyze_services(services)

            # Get storage backends via service list
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
        Analyze Cinder service status

        Args:
            services: List of Cinder service objects

        Returns:
            Dictionary with service statistics
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

            # Count overall stats
            if state == 'up':
                stats['up'] += 1
            else:
                stats['down'] += 1

            # Count by binary type
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
        Analyze storage backends from cinder-volume services

        Args:
            services: List of Cinder service objects

        Returns:
            Dictionary with backend statistics
        """
        stats = {
            'total': 0,
            'details': []
        }

        # Extract backends from cinder-volume services
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
        Extract backend name from host string

        Args:
            hostname: Service host string

        Returns:
            Backend name
        """
        # Example: "huawei@huawei_storage_high" -> "huawei_storage_high"
        if '@' in hostname:
            return hostname.split('@')[1]
        return hostname

    def _detect_vendor(self, hostname: str) -> str:
        """
        Detect storage vendor from hostname

        Args:
            hostname: Service hostname

        Returns:
            Vendor name
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
        """Close OpenStack connection sessions"""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [CINDER_DEBUG] Connections closed")

