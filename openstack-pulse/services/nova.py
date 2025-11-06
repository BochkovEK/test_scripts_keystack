from novaclient import client as nova_client
from typing import Dict, Any
import time


class NovaCheck:
    def __init__(self, session):
        self.nova = nova_client.Client(version='2.1', session=session)

    def run_check(self):
        """
        Detailed Nova services status check
        """
        start_time = time.time()

        try:
            # Get all services
            services = self.nova.services.list()

            # Get detailed services info
            service_stats = self._analyze_services(services)

            # Get hypervisors with instances
            hypervisor_stats = self._analyze_hypervisors_with_instances()

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'services': service_stats,
                'hypervisors': hypervisor_stats
            }

        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

    def _analyze_services(self, services):
        """Analyze Nova services by type"""

        stats: Dict[str, Any] = {
            'total': len(services),
            'by_state': {'up': 0, 'down': 0},
            'critical_services': {}  # Теперь линтер понимает, что это Any
        }

        critical_services = ['nova-conductor', 'nova-scheduler', 'nova-compute']

        for service in services:
            # Count by state
            if service.state == 'up':
                stats['by_state']['up'] += 1
            else:
                stats['by_state']['down'] += 1

            # Track critical services
            if service.binary in critical_services:
                stats['critical_services'][service.binary] = {
                    'host': service.host,
                    'state': service.state,
                    'status': service.status
                }

        return stats

    def _analyze_hypervisors_with_instances(self):
        """Get hypervisors with instance counts"""
        try:
            hypervisors = self.nova.hypervisors.list()

            stats = {
                'total': len(hypervisors),
                'up': 0,
                'down': 0,
                'details': []
            }

            for hv in hypervisors:
                hv_info = {
                    'name': hv.hypervisor_hostname,
                    'state': hv.state,
                    'instances_count': hv.running_vms
                }
                stats['details'].append(hv_info)

                if hv.state == 'up':
                    stats['up'] += 1
                else:
                    stats['down'] += 1

            return stats

        except Exception:
            return {'total': 0, 'up': 0, 'down': 0, 'details': []}