#!/usr/bin/env python3
"""
OpenStack Pulse - Lightweight diagnostic tool
"""

import time
import sys
import os
from concurrent.futures import ThreadPoolExecutor, as_completed

# Add project directories to Python path
sys.path.append(os.path.join(os.path.dirname(__file__), 'services'))
sys.path.append(os.path.join(os.path.dirname(__file__), 'config'))

from config.config import Config
from services.nova import NovaCheck
from services.keystone import KeystoneCheck
from services.neutron import NeutronCheck
from services.rabbitmq import RabbitCheck


class Pulse:

    def __init__(self):
        self.config = Config()
        self.service_checks = {}
        self._init_service_checks()
        self.snapshots = []

    # def _init_service_checks(self):
    #     """Initialize enabled service checks using dictionary"""
    #     service_map = {
    #         'nova': (NovaCheck, 'session'),
    #         'keystone': (KeystoneCheck, 'session'),
    #         'neutron': (NeutronCheck, 'session'),
    #         'rabbitmq': (RabbitCheck, 'config'),
    #         # 'galera': (GaleraCheck, 'config')
    #     }
    #
    #     for service_name in self.config.settings.check_services:
    #         if service_name in service_map:
    #             check_class, param_type = service_map[service_name]
    #
    #             # Определяем параметр для конструктора
    #             if param_type == 'session':
    #                 param = self.config.session
    #             elif param_type == 'config':
    #                 param = self.config
    #             else:
    #                 # Логируем ошибку и пропускаем сервис
    #                 print(f"⚠️  Unknown parameter type '{param_type}' for service '{service_name}'")
    #                 continue
    #
    #             # Создаем экземпляр проверки
    #             self.service_checks[service_name] = check_class(param)
    #
    #         else:
    #             print(f"⚠️  Service '{service_name}' not found in service_map")

    # def _init_service_checks(self):
    #     """Initialize enabled service checks with full error handling"""
    #     service_map = {
    #         'nova': (NovaCheck, 'session'),
    #         'keystone': (KeystoneCheck, 'session'),
    #         'neutron': (NeutronCheck, 'session'),
    #         'rabbitmq': (RabbitCheck, 'config'),
    #     }
    #
    #     print(f"DEBUG: check_services from config: {self.config.settings.check_services}")
    #
    #     initialized_services = []
    #
    #     for service_name in self.config.settings.check_services:
    #         try:
    #             print(f"DEBUG: Processing service: {service_name}")
    #
    #             if service_name not in service_map:
    #                 print(f"❌ Service '{service_name}' not supported. Available: {list(service_map.keys())}")
    #                 continue
    #
    #             check_class, param_type = service_map[service_name]
    #             print(f"DEBUG: check_class: {check_class}, param_type: {param_type}")
    #
    #             # Определяем параметр для конструктора
    #             if param_type == 'session':
    #                 param = self.config.session
    #             elif param_type == 'config':
    #                 param = self.config
    #             else:
    #                 raise ValueError(f"Unknown parameter type: {param_type}")
    #
    #             # Создаем экземпляр проверки
    #             self.service_checks[service_name] = check_class(param)
    #             initialized_services.append(service_name)
    #             print(f"DEBUG: Successfully created {service_name}_check")
    #
    #         except Exception as e:
    #             print(f"❌ Failed to initialize {service_name}: {e}")
    #
    #     print(f"✅ Initialized services: {', '.join(initialized_services)}")
    #     print(f"DEBUG: service_checks keys: {list(self.service_checks.keys())}")

    # def _init_service_checks(self):
    #     """Simple test initialization"""
    #     print("=== DEBUG _init_service_checks ===")
    #
    #     # Простой тест - создаем один сервис вручную
    #     try:
    #         print("Trying to create NovaCheck...")
    #         nova_check = NovaCheck(self.config.session)
    #         self.service_checks['nova'] = nova_check
    #         print("✅ NovaCheck created successfully")
    #     except Exception as e:
    #         print(f"❌ Failed to create NovaCheck: {e}")
    #
    #     print(f"service_checks: {self.service_checks}")
    #     print("==================================")

    # def _init_service_checks(self):
    #     """Initialize enabled service checks"""
    #     service_map = {
    #         'nova': (NovaCheck, 'session'),
    #         'keystone': (KeystoneCheck, 'session'),
    #         'neutron': (NeutronCheck, 'session'),
    #         'rabbitmq': (RabbitCheck, 'config'),  # ← config для RabbitCheck!
    #     }
    #
    #     print("=== DEBUG _init_service_checks ===")
    #
    #     for service_name in self.config.settings.check_services:
    #         try:
    #             print(f"Processing {service_name}...")
    #
    #             if service_name not in service_map:
    #                 print(f"❌ Service '{service_name}' not in service_map")
    #                 continue
    #
    #             check_class, param_type = service_map[service_name]
    #             print(f"check_class: {check_class}, param_type: {param_type}")
    #
    #             if param_type == 'session':
    #                 param = self.config.session
    #             elif param_type == 'config':
    #                 param = self.config  # ← ВАЖНО: config для RabbitCheck!
    #             else:
    #                 print(f"❌ Unknown param_type: {param_type}")
    #                 continue
    #
    #             self.service_checks[service_name] = check_class(param)
    #             print(f"✅ {service_name} initialized")
    #
    #         except Exception as e:
    #             print(f"❌ Failed to initialize {service_name}: {e}")
    #
    #     print(f"Final service_checks: {list(self.service_checks.keys())}")
    #     print("==================================")

    def _init_service_checks(self):
        """Initialize enabled service checks with warnings"""
        service_map = {
            'nova': (NovaCheck, 'session'),
            'keystone': (KeystoneCheck, 'session'),
            'neutron': (NeutronCheck, 'session'),
            'rabbitmq': (RabbitCheck, 'config'),
        }

        for service_name in self.config.settings.check_services:
            if service_name in service_map:
                try:
                    check_class, param_type = service_map[service_name]
                    param = self.config.session if param_type == 'session' else self.config
                    self.service_checks[service_name] = check_class(param)
                except Exception as e:
                    print(f"⚠️  Failed to initialize {service_name}: {e}")
            else:
                print(f"⚠️  Service '{service_name}' not supported")

    def collect_metrics(self):
        """Collect metrics from all enabled services in parallel"""
        snapshot = {'timestamp': time.time()}

        # Проверяем что есть сервисы для проверки
        if not self.service_checks:
            print("❌ No services initialized! Check _init_service_checks()")
            return snapshot

        with ThreadPoolExecutor(max_workers=len(self.service_checks)) as executor:
            future_to_service = {}
            for service_name, check in self.service_checks.items():
                future = executor.submit(check.run_check)
                future_to_service[future] = service_name

            for future in as_completed(future_to_service):
                service_name = future_to_service[future]
                try:
                    snapshot[service_name] = future.result()
                except Exception as e:
                    snapshot[service_name] = {
                        'status': 'ERROR',
                        'response_time': 0,
                        'error': str(e)
                    }

        return snapshot

    # def collect_metrics(self):
    #     """Collect metrics in parallel"""
    #     snapshot = {'timestamp': time.time()}
    #
    #     with ThreadPoolExecutor(max_workers=5) as executor:
    #         # Запускаем все проверки параллельно
    #         future_to_service = {}
    #         for service_name in self.config.settings.check_services:
    #             if hasattr(self, f'{service_name}_check'):
    #                 check = getattr(self, f'{service_name}_check')
    #                 future = executor.submit(check.run_check)
    #                 future_to_service[future] = service_name
    #
    #         # Собираем результаты
    #         for future in as_completed(future_to_service):
    #             service_name = future_to_service[future]
    #             snapshot[service_name] = future.result()
    #
    #     return snapshot

    def run(self):
        """Main monitoring loop with limited collection window"""
        print("Starting OpenStack Pulse monitoring...")
        print(f"Enabled checks: {', '.join(self.config.settings.check_services)}")

        # Calculate number of iterations based on collection window and interval
        total_iterations = (self.config.settings.intervals.collection_window //
                            self.config.settings.intervals.check_interval)
        print(
            f"Collection: {total_iterations} cycles ({self.config.settings.intervals.collection_window}s window, "
            f"{self.config.settings.intervals.check_interval}s interval)")

        try:
            for cycle in range(total_iterations):
                # Собираем метрики
                snapshot = self.collect_metrics()

                # Сразу выводим на экран
                self._display_snapshot(snapshot, cycle + 1, total_iterations)

                # Ждем следующий цикл (кроме последнего)
                if cycle < total_iterations - 1:
                    time.sleep(self.config.settings.intervals.check_interval)

            print(f"\nCollection completed. Total cycles: {total_iterations}")

        except KeyboardInterrupt:
            print("\nMonitoring stopped by user")

    def _display_snapshot(self, snapshot, current_cycle, total_cycles):
        """Display current snapshot to console"""
        # print(f"\n[{time.ctime(snapshot['timestamp'])}] Cycle {current_cycle}/{total_cycles}")
        timestamp = time.ctime(snapshot['timestamp'])
        print("=" * 45)
        print(f"    Cycle {current_cycle}/{total_cycles} - {timestamp}")
        print("=" * 45)

        for service_name in self.config.settings.check_services:
            if service_name in snapshot:
                service_data = snapshot[service_name]
                self._display_service_status(service_name, service_data)

    def _display_service_status(self, service_name, service_data):
        status_icon = "✅" if service_data['status'] == 'OK' else "❌"
        print(f"{status_icon} {service_name.upper()}: {service_data['status']} ({service_data['response_time']}s)")

        display_methods = {
            'nova': self._display_nova_details,
            'keystone': self._display_keystone_details,
            'neutron': self._display_neutron_details,
            'rabbitmq': self._display_rabbitmq_details
        }

        if service_data['status'] == 'OK' and service_name in display_methods:
            display_methods[service_name](service_data)
        elif service_data['status'] == 'ERROR':
            print(f"   Error: {service_data['error']}")

    def _display_rabbitmq_details(self, rabbit_data):
        """Display RabbitMQ cluster health details"""
        cluster = rabbit_data['cluster']
        health = cluster['cluster_health']

        print(f"   Nodes: {rabbit_data['reachable_nodes']}/{rabbit_data['total_nodes']} reachable")

        # Статус здоровья
        print("   Cluster Health:")
        print(
            f"     {'✅' if health['replication_ok'] else '❌'} Replication: {'OK' if health['replication_ok'] else 'CRITICAL'}")
        print(f"     {'✅' if health['uptime_ok'] else '⚠️ '} Uptime: {'>10min' if health['uptime_ok'] else '<10min'}")
        print(f"     {'✅' if health['processes_ok'] else '❌'} Processes: {'OK' if health['processes_ok'] else 'LIMIT'}")

        # Детали по узлам
        if cluster['node_details']:
            print("   Node Details:")
            for url, details in cluster['node_details'].items():
                if 'error' not in details:
                    status = "🟢" if url in cluster['reachable_nodes'] else "🔴"
                    print(f"     {status} {url}")
                    print(f"       Queues: {details.get('queues', 0)}, Messages: {details.get('messages', 0)}")
                    print(
                        f"       Uptime: {details.get('uptime', 0) / 1000:.0f}s, Processes: {details.get('processes_used', 0)}/{details.get('processes_limit', 0)}")

    def _display_neutron_details(self, neutron_data):
        """Display Neutron-specific details"""
        agents = neutron_data['agents']
        print(f"   Agents: {agents['up']}/{agents['total']} up")

        if 'critical_agents' in agents:
            print("   Critical Agents:")
            for agent_type, stats in agents['critical_agents'].items():
                # Определяем цвет иконки
                if stats['down'] == 0:
                    status_icon = "🟢"  # Все работает
                    status_info = f"{stats['up']} up"
                elif stats['up'] == 0:
                    status_icon = "🔴"  # Все упало
                    status_info = f"{stats['down']} down"
                else:
                    status_icon = "🟡"  # Частичный отказ
                    status_info = f"{stats['up']} up, {stats['down']} down"

                print(f"     {status_icon} {agent_type}: {status_info}")

        # print(f"   Networks: {neutron_data['networks_count']} available")

    def _display_keystone_details(self, keystone_data):
        """Display Keystone-specific details"""
        if keystone_data.get('token_valid'):
            print("   Token: ✅ valid")
        if keystone_data.get('services_count'):
            print(f"   Services: {keystone_data['services_count']} available")

    @staticmethod
    def _display_nova_details(nova_data):
        """Display Nova-specific details"""
        services = nova_data['services']
        critical = services['critical_services']
        hypervisors = nova_data['hypervisors']

        print("  Critical Services:")

        # Теперь critical - это Dict[str, List[Dict]]
        for service_type, instances in critical.items():
            for instance in instances:
                status_icon = "✅" if instance['state'] == 'up' else "❌"
                print(f"    {status_icon} {service_type}: {instance['state']} on {instance['host']}")

        # Hypervisors with instances
        print(f"  Hypervisors: {hypervisors['up']}/{hypervisors['total']} up")
        for hv in hypervisors['details']:
            # Определяем эмодзи статуса
            if hv['state'] == 'up':
                if hv['instances_count'] > 0:
                    status_icon = "🟢"
                    instances_info = f" 📦{hv['instances_count']} VM"
                else:
                    status_icon = "🔵"
                    instances_info = ""
            else:
                status_icon = "🔴"
                instances_info = " (down)"

            print(f"    {status_icon} {hv['name']}{instances_info}")


if __name__ == "__main__":
    pulse = Pulse()
    pulse.run()
