import openstack
import time
from config.config import ServiceType


class NovaCheck:
    def __init__(self, config, debug=False):
        """
        Initialize Nova health check

        Args:
            config: Config object providing service authentication
        """
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(
            **auth_params,
            compute_api_version='2.1'
        )

    def run_check(self):
        """Execute Nova services health check"""
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
        """
        Analyze Nova service status

        Args:
            services: List of Nova service objects

        Returns:
            Dictionary with service statistics
        """
        stats = {
            'total': len(services),
            'up': 0,
            'down': 0,
            'critical_services': {}
        }

        critical_services = ['nova-conductor', 'nova-scheduler', 'nova-compute']

        for service in services:
            # Count services by state
            if service.state == 'up':
                stats['up'] += 1
            else:
                stats['down'] += 1

            # Track critical services
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
            # Try multiple ways to get running VMs count
            running_vms = self._get_running_vms_count(hv)

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

    def _get_running_vms_count(self, hypervisor):
        """Get running VMs count using hypervisor statistics"""
        try:
            # Method 1: Try to get detailed hypervisor stats
            hv_details = self.conn.compute.get_hypervisor(hypervisor.id)
            if hasattr(hv_details, 'running_vms') and hv_details.running_vms is not None:
                return hv_details.running_vms

            # Method 2: Try alternative attribute names
            if hasattr(hypervisor, 'running_vms') and hypervisor.running_vms is not None:
                return hypervisor.running_vms

            # Method 3: Try to get VMs via compute API
            servers = list(self.conn.compute.servers(all_projects=True, host=hypervisor.name))
            return len([s for s in servers if s.status == 'ACTIVE'])

        except Exception as e:
            print(f"⚠️  Failed to get VM count for {hypervisor.name}: {e}")

        return 0