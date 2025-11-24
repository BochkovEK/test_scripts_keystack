"""
Nova Compute Service monitoring
Checks compute services, hypervisors and instance states
"""

import openstack
import time
from config.config import ServiceType


class NovaCheck:
    """
    Nova Compute Service health monitoring class.

    Provides comprehensive monitoring of Nova compute services including:
    - Compute service status (nova-compute, nova-scheduler, nova-conductor)
    - Hypervisor availability and health
    - Virtual machine instance counts and distribution
    - Service response time and availability metrics
    """

    def __init__(self, config, debug=False):
        """
        Initialize Nova health check.

        Args:
            config: Config object providing service authentication
            debug: Enable debug output for troubleshooting
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(
            **auth_params,
            compute_api_version='2.1'
        )

        if self.debug:
            print(f"🔧 [NOVA_DEBUG] Initialized with compute API v2.1")

    def run_check(self):
        """
        Execute Nova compute services health check.

        Returns:
            Dictionary containing check results:
            - status: Overall check status ('OK' or 'ERROR')
            - response_time: API response time in seconds
            - services: Compute service statistics
            - hypervisors: Hypervisor availability and metrics
        """
        start_time = time.time()

        try:
            services = list(self.conn.compute.services())
            service_stats = self._analyze_services(services)

            hypervisors = list(self.conn.compute.hypervisors())
            hypervisor_stats = self._analyze_hypervisors(hypervisors)

            if service_stats['up'] < service_stats['total']:
                status = 'DEGRADED'
            elif any(service.status == 'disabled' for service in services):
                status = 'DEGRADED'
            elif hypervisor_stats['up'] < hypervisor_stats['total']:
                status = 'DEGRADED'
            else:
                status = 'OK'

            result = {
                'status': status,
                'response_time': round(time.time() - start_time, 2),
                'services': service_stats,
                'hypervisors': hypervisor_stats
            }

            if self.debug:
                print(f"🔧 [NOVA_DEBUG] Check completed: {len(services)} services, {len(hypervisors)} hypervisors")

            return result

        except Exception as e:
            error_result = {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

            if self.debug:
                print(f"🔧 [NOVA_DEBUG] Check failed: {error_result}")

            return error_result

    def display_details(self, data):
        """
        Display Nova compute service details in formatted output.

        Args:
            data: Dictionary containing service and hypervisor statistics
        """
        services = data.get('services', {})
        hypervisors = data.get('hypervisors', {})

        # Display service summary and detailed status
        print(f"  Services: {services.get('up', 0)}/{services.get('total', 0)} up")

        # Display critical services with smart formatting
        critical_services = services.get('critical_services', {})
        for service_name, service_nodes in critical_services.items():
            up_count = sum(1 for node in service_nodes if node.get('state') == 'up')
            total_count = len(service_nodes)
            down_count = total_count - up_count
            disabled_count = sum(1 for node in service_nodes if node.get('status') == 'disabled')

            # Smart display: compact for healthy services, detailed for problematic ones
            if down_count == 0 and disabled_count == 0:
                # All services healthy - show compact format
                print(f"    🟢 {service_name}: {up_count} up")
            else:
                # Services with issues - show detailed breakdown
                print(f"    ⚠️ {service_name}:")
                for node_info in service_nodes:
                    status_icon = self._get_service_status_icon(
                        node_info.get('state'),
                        node_info.get('status')
                    )
                    status_text = f": state - {node_info.get('state', 'unknown')}, status - {node_info.get('status', 'unknown')}"
                    print(f"      {status_icon} {node_info.get('host', 'unknown')}{status_text}")

        # Display hypervisor summary and details
        print(f"  Hypervisors: {hypervisors.get('up', 0)}/{hypervisors.get('total', 0)} up")
        for hv_info in hypervisors.get('details', []):
            status_icon, instances_info = self._get_hypervisor_display_info(hv_info)
            print(f"    {status_icon} {hv_info.get('name', 'unknown')}{instances_info}")

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

    def _get_hypervisor_display_info(self, hypervisor_info: dict) -> tuple:
        """
        Determine display icon and instance information for hypervisor.

        Args:
            hypervisor_info: Dictionary containing hypervisor state and instance count

        Returns:
            Tuple of (status_icon, instances_info_string)
        """
        if hypervisor_info.get('state') == 'up':
            instances_count = hypervisor_info.get('instances_count', 0)
            if instances_count > 0:
                return "🟢", f" 📦{instances_count} VM"
            else:
                return "🔵", ""
        else:
            return "🔴", ""

    def _analyze_services(self, services):
        """
        Analyze Nova service status and categorize critical services.

        Args:
            services: List of Nova service objects from OpenStack

        Returns:
            Dictionary containing service statistics organized by critical service types
        """
        stats = {
            'total': len(services),
            'up': 0,
            'down': 0,
            'critical_services': {}
        }

        # Define critical Nova services for compute functionality
        critical_services = ['nova-conductor', 'nova-scheduler', 'nova-compute']

        for service in services:
            # Count overall service availability
            if service.state == 'up':
                stats['up'] += 1
            else:
                stats['down'] += 1

            # Track critical services with detailed information
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
        """
        Analyze hypervisor availability and instance distribution.

        Args:
            hypervisors: List of hypervisor objects from OpenStack

        Returns:
            Dictionary containing hypervisor statistics and detailed information
        """
        stats = {
            'total': len(hypervisors),
            'up': 0,
            'down': 0,
            'details': []
        }

        for hv in hypervisors:
            # Get running VM count using multiple fallback methods
            running_vms = self._get_running_vms_count(hv)

            hv_info = {
                'name': hv.name,
                'state': hv.state,
                'instances_count': running_vms
            }
            stats['details'].append(hv_info)

            # Count hypervisors by operational state
            if hv.state == 'up':
                stats['up'] += 1
            else:
                stats['down'] += 1

        return stats

    def _get_running_vms_count(self, hypervisor):
        """
        Get running VMs count using multiple fallback methods.

        Args:
            hypervisor: Hypervisor object from OpenStack

        Returns:
            Number of running virtual machines on the hypervisor
        """
        try:
            # Method 1: Try to get detailed hypervisor statistics
            hv_details = self.conn.compute.get_hypervisor(hypervisor.id)
            if hasattr(hv_details, 'running_vms') and hv_details.running_vms is not None:
                return hv_details.running_vms

            # Method 2: Try alternative attribute names on base hypervisor object
            if hasattr(hypervisor, 'running_vms') and hypervisor.running_vms is not None:
                return hypervisor.running_vms

            # Method 3: Fallback to counting VMs via compute API
            servers = list(self.conn.compute.servers(all_projects=True, host=hypervisor.name))
            return len([s for s in servers if s.status == 'ACTIVE'])

        except Exception as e:
            if self.debug:
                print(f"🔧 [NOVA_DEBUG] Failed to get VM count for {hypervisor.name}: {e}")

        return 0

    def close_sessions(self):
        """Close OpenStack connection sessions to free resources."""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [NOVA_DEBUG] Connections closed")