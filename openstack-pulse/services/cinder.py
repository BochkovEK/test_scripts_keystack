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

            # Get storage pools (backends)
            pools = self._get_storage_pools()
            pool_stats = self._analyze_pools(pools)

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'services': service_stats,
                'storage_pools': pool_stats
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

    def _get_storage_pools(self) -> List[Any]:
        """
        Get storage pools information

        Returns:
            List of storage pool objects
        """
        try:
            # Try to get pools via block storage API
            return list(self.conn.block_storage.pools())
        except Exception as e:
            print(f"⚠️  Could not retrieve storage pools: {e}")
            return []

    def _analyze_pools(self, pools) -> Dict[str, Any]:
        """
        Analyze storage pools status

        Args:
            pools: List of storage pool objects

        Returns:
            Dictionary with pool statistics
        """
        stats = {
            'total': len(pools),
            'details': []
        }

        for pool in pools:
            pool_info = {
                'name': getattr(pool, 'name', 'unknown'),
                'backend': getattr(pool, 'backend', 'unknown'),
                'vendor': self._detect_vendor(getattr(pool, 'name', '')),
                'status': 'available'
            }

            # Add capacity info if available
            if hasattr(pool, 'capabilities'):
                caps = pool.capabilities
                pool_info.update({
                    'total_capacity_gb': caps.get('total_capacity_gb', 0),
                    'free_capacity_gb': caps.get('free_capacity_gb', 0),
                    'provisioned_capacity_gb': caps.get('provisioned_capacity_gb', 0)
                })

            stats['details'].append(pool_info)

        return stats

    def _detect_vendor(self, pool_name: str) -> str:
        """
        Detect storage vendor from pool name

        Args:
            pool_name: Storage pool name

        Returns:
            Vendor name
        """
        name_lower = pool_name.lower()

        if 'huawei' in name_lower or 'dorado' in name_lower:
            return 'Huawei Dorado'
        elif 'lvm' in name_lower:
            return 'LVM'
        elif 'ceph' in name_lower:
            return 'Ceph'
        else:
            return 'Unknown'

    def close_sessions(self):
        """Close OpenStack connection sessions"""
        if hasattr(self, 'conn'):
            self.conn.close()