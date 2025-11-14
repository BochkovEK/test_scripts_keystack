"""
Cinder Block Storage service monitoring
Checks volume services, scheduler services and storage backends
"""

import openstack
import time
from typing import Dict, List, Any
from config.config import ServiceType


class CinderCheck:
    def __init__(self, config):
        """
        Initialize Cinder health check

        Args:
            config: Config object providing service authentication
        """
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(
            **auth_params
        )

    def run_check(self):
        """Execute Cinder services health check"""
        start_time = time.time()

        try:
            # Get all Cinder services
            services = list(self.conn.block_storage.services())
            service_stats = self._analyze_services(services)

            # Get storage backends via service list
            backend_stats = self._analyze_backends(services)

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'services': service_stats,
                'backends': backend_stats
            }

        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

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