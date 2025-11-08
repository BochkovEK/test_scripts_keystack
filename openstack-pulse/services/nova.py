import openstack
import time


class NovaCheck:
    def __init__(self, session):
        self.conn = openstack.connection.Connection(
            session=session,
            compute_api_version='2.1'
        )

    def run_check(self):
        """Nova services status check"""
        start_time = time.time()

        try:
            services = list(self.conn.compute.services())
            service_stats = self._analyze_services(services)

            hypervisors = list(self.conn.compute.hypervisors())
            hypervisor_stats = self._analyze_hypervisors(hypervisors)

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
        """Analyze Nova services"""
        stats = {
            'total': len(services),
            'up': 0,
            'down': 0,
            'critical_services': {}
        }

        critical_services = ['nova-conductor', 'nova-scheduler', 'nova-compute']

        for service in services:
            if service.state == 'up':
                stats['up'] += 1
            else:
                stats['down'] += 1

            if service.binary in critical_services:
                if service.binary not in stats['critical_services']:
                    stats['critical_services'][service.binary] = []

                stats['critical_services'][service.binary].append({
                    'host': service.host,
                    'state': service.state,
                    'status': service.status
                })

        return stats

    def _analyze_hypervisors(self, hypervisors):
        """Analyze hypervisors with instance counts"""
        stats = {
            'total': len(hypervisors),
            'up': 0,
            'down': 0,
            'details': []
        }

        for hv in hypervisors:
            running_vms = hv.running_vms if hv.running_vms is not None else 0

            hv_info = {
                'name': hv.name,
                'state': hv.state,
                'instances_count': running_vms
            }
            stats['details'].append(hv_info)

            if hv.state == 'up':
                stats['up'] += 1
            else:
                stats['down'] += 1

        return stats