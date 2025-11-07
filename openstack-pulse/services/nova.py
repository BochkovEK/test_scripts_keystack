import openstack
from typing import Dict, Any
import time


class NovaCheck:
    def __init__(self, session):
        self.conn = openstack.connection.Connection(
            session=session,
            compute_api_version='2.1'
        )

    # def run_check(self):
    #     start_time = time.time()
    #
    #     try:
    #         # Сервисы через OpenStackSDK
    #         services = list(self.conn.compute.services())
    #         service_stats = self._analyze_services(services)
    #
    #         # Гипервизоры через OpenStackSDK
    #         hypervisors = list(self.conn.compute.hypervisors())
    #         hypervisor_stats = self._analyze_hypervisors_with_instances(hypervisors)
    #
    #         return {
    #             'status': 'OK',
    #             'response_time': round(time.time() - start_time, 2),
    #             'services': service_stats,
    #             'hypervisors': hypervisor_stats
    #         }
    #     except Exception as e:
    #         return {
    #             'status': 'ERROR',
    #             'response_time': round(time.time() - start_time, 2),
    #             'error': str(e)
    #         }

    def run_check(self):
        """Detailed Nova services status check"""
        start_time = time.time()

        try:
            print("DEBUG Nova: Getting services...")
            services = list(self.conn.compute.services())
            print(f"DEBUG Nova: Found {len(services)} services")

            service_stats = self._analyze_services(services)

            print("DEBUG Nova: Getting hypervisors...")
            hypervisors = list(self.conn.compute.hypervisors())
            print(f"DEBUG Nova: Found {len(hypervisors)} hypervisors")

            hypervisor_stats = self._analyze_hypervisors_with_instances(hypervisors)

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'services': service_stats,
                'hypervisors': hypervisor_stats
            }

        except Exception as e:
            print(f"DEBUG Nova: ERROR - {e}")
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

            if service.binary in critical_services:
                # Инициализируем список для этого типа сервиса
                if service.binary not in stats['critical_services']:
                    stats['critical_services'][service.binary] = []

                # Добавляем сервис в список
                stats['critical_services'][service.binary].append({
                    'host': service.host,
                    'state': service.state,
                    'status': service.status
                })

        return stats

    # def _analyze_hypervisors_with_instances(self, hypervisors):
    #     """Get hypervisors with instance counts"""
    #     try:
    #         # hypervisors = self.nova.hypervisors.list()
    #
    #         stats = {
    #             'total': len(hypervisors),
    #             'up': 0,
    #             'down': 0,
    #             'details': []
    #         }
    #
    #         for hv in hypervisors:
    #             hv_info = {
    #                 'name': hv.hypervisor_hostname,
    #                 'state': hv.state,
    #                 'instances_count': hv.running_vms
    #             }
    #             stats['details'].append(hv_info)
    #
    #             if hv.state == 'up':
    #                 stats['up'] += 1
    #             else:
    #                 stats['down'] += 1
    #
    #         return stats
    #
    #     except Exception:
    #         return {'total': 0, 'up': 0, 'down': 0, 'details': []}

    def _analyze_hypervisors_with_instances(self, hypervisors):
        """Get hypervisors with instance counts"""
        print(
            f"DEBUG Nova: Hypervisor attributes: {[attr for attr in dir(hypervisors[0]) if not attr.startswith('_')]}")

        stats = {
            'total': len(hypervisors),
            'up': 0,
            'down': 0,
            'details': []
        }

        for hv in hypervisors:
            # Проверяем какие атрибуты доступны
            name = getattr(hv, 'name', getattr(hv, 'hypervisor_hostname', 'unknown'))
            state = getattr(hv, 'state', 'unknown')
            running_vms = getattr(hv, 'running_vms', 0)

            print(f"DEBUG Nova: {name} - state: {state}, vms: {running_vms}")

            hv_info = {
                'name': name,
                'state': state,
                'instances_count': running_vms
            }
            stats['details'].append(hv_info)

            if state == 'up':
                stats['up'] += 1
            else:
                stats['down'] += 1

        return stats