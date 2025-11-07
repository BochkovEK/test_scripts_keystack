#!/usr/bin/env python3
"""
OpenStack Pulse - Lightweight diagnostic tool
"""
import threading
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
                    print(f"✅ {service_name} initialized")
                except Exception as e:
                    print(f"⚠️  Failed to initialize {service_name}: {e}")
            else:
                print(f"⚠️  Service '{service_name}' not supported")

    # def collect_metrics(self):
    #     """Collect metrics from all enabled services in parallel"""
    #     snapshot = {'timestamp': time.time()}
    #
    #     # Проверяем что есть сервисы для проверки
    #     if not self.service_checks:
    #         print("❌ No services initialized! Check _init_service_checks()")
    #         return snapshot
    #
    #     with ThreadPoolExecutor(max_workers=len(self.service_checks)) as executor:
    #         future_to_service = {}
    #         for service_name, check in self.service_checks.items():
    #             future = executor.submit(check.run_check)
    #             future_to_service[future] = service_name
    #
    #         for future in as_completed(future_to_service):
    #             service_name = future_to_service[future]
    #             try:
    #                 snapshot[service_name] = future.result()
    #             except Exception as e:
    #                 snapshot[service_name] = {
    #                     'status': 'ERROR',
    #                     'response_time': 0,
    #                     'error': str(e)
    #                 }
    #
    #     return snapshot

    # threading
    # def collect_metrics(self):
    #     """Collect metrics using threading instead of ThreadPoolExecutor"""
    #     snapshot = {'timestamp': time.time()}
    #     threads = []
    #     results = {}
    #     exceptions = {}
    #
    #     def run_service(service_name, check):
    #         try:
    #             print(f"🕐 Starting {service_name} at {time.time()}")
    #             result = check.run_check()
    #             print(f"🕐 Finished {service_name} at {time.time()}: {result['response_time']}s")
    #             results[service_name] = result
    #         except Exception as e:
    #             exceptions[service_name] = e
    #
    #     # Запускаем потоки для каждого сервиса
    #     for service_name, check in self.service_checks.items():
    #         thread = threading.Thread(target=run_service, args=(service_name, check))
    #         thread.daemon = True
    #         thread.start()
    #         threads.append(thread)
    #
    #     # Ждем завершения всех потоков
    #     for thread in threads:
    #         thread.join()
    #
    #     # Собираем результаты
    #     for service_name in self.service_checks:
    #         if service_name in results:
    #             snapshot[service_name] = results[service_name]
    #         elif service_name in exceptions:
    #             snapshot[service_name] = {'status': 'ERROR', 'error': str(exceptions[service_name])}
    #         else:
    #             snapshot[service_name] = {'status': 'ERROR', 'error': 'Thread failed'}
    #
    #     return snapshot

    # multy
    # def collect_metrics(self):
    #     snapshot = {'timestamp': time.time()}
    #
    #     with ThreadPoolExecutor(max_workers=len(self.service_checks)) as executor:
    #         future_to_service = {}
    #         for service_name, check in self.service_checks.items():
    #             print(f"🕐 Starting {service_name} at {time.time()}")
    #             future = executor.submit(check.run_check)
    #             future_to_service[future] = service_name
    #
    #         for future in as_completed(future_to_service):
    #             service_name = future_to_service[future]
    #             try:
    #                 result = future.result()
    #                 print(f"🕐 Finished {service_name} at {time.time()}: {result['response_time']}s")
    #                 snapshot[service_name] = result
    #             except Exception as e:
    #                 snapshot[service_name] = {'status': 'ERROR', 'error': str(e)}
    #
    #     return snapshot

    # single
    def collect_metrics(self):
        """Collect metrics sequentially without threading"""
        snapshot = {'timestamp': time.time()}

        for service_name, check in self.service_checks.items():
            print(f"🕐 Starting {service_name} at {time.time()}")
            try:
                result = check.run_check()
                print(f"🕐 Finished {service_name} at {time.time()}: {result['response_time']}s")
                snapshot[service_name] = result
            except Exception as e:
                snapshot[service_name] = {'status': 'ERROR', 'error': str(e)}

        return snapshot

    # def run(self):
    #     """Main monitoring loop without sleep"""
    #     print("Starting OpenStack Pulse monitoring...")
    #     print(f"Enabled checks: {', '.join(self.config.settings.check_services)}")
    #
    #     total_iterations = (self.config.settings.intervals.collection_window //
    #                         self.config.settings.intervals.check_interval)
    #     print(f"Collection: {total_iterations} cycles")
    #
    #     try:
    #         for cycle in range(total_iterations):
    #             cycle_start_time = time.time()
    #
    #             # Собираем метрики
    #             snapshot = self.collect_metrics()
    #
    #             # Сразу выводим на экран
    #             self._display_snapshot(snapshot, cycle + 1, total_iterations)
    #
    #             cycle_time = time.time() - cycle_start_time
    #             print(f"Cycle {cycle + 1} took {cycle_time:.2f}s")
    #
    #         print(f"\nCollection completed. Total cycles: {total_iterations}")
    #
    #     except KeyboardInterrupt:
    #         print("\nMonitoring stopped by user")
    #     finally:
    #         self._close_sessions()

    def run(self):
        """Main monitoring loop - simplified with automatic heartbeat"""
        print("Starting OpenStack Pulse monitoring...")
        print(f"Enabled checks: {', '.join(self.config.settings.check_services)}")

        total_iterations = (self.config.settings.intervals.collection_window //
                            self.config.settings.intervals.check_interval)
        print(f"Collection: {total_iterations} cycles")

        try:
            for cycle in range(total_iterations):
                # if cycle >= 1 and 'rabbitmq' in self.service_checks:
                #     self.service_checks['rabbitmq'].stop_heartbeat()
                cycle_start = time.time()

                # Собираем метрики
                snapshot = self.collect_metrics()

                # Сразу выводим на экран
                self._display_snapshot(snapshot, cycle + 1, total_iterations)

                cycle_work_time = time.time() - cycle_start
                print(f"🕒 Cycle {cycle + 1} WORK time: {cycle_work_time:.1f}s")

                # Ждем перед следующим циклом (кроме последнего)

                if cycle < total_iterations - 1:
                    interval = getattr(getattr(self.config.settings, 'intervals', None), 'check_interval', 5)
                    rabbitmq_requests_heartbeat = getattr(getattr(self.config.settings, 'rabbitmq', None), 'rabbitmq_requests_heartbeat', 4)

                    # Запускаем heartbeat на время sleep (если интервал > 4 сек)
                    if interval > 4 and 'rabbitmq' in self.service_checks:
                        print(f"💤 Sleeping {interval}s with heartbeat {rabbitmq_requests_heartbeat}s")
                        self.service_checks['rabbitmq'].start_heartbeat()
                    else:
                        print(f"💤 Sleeping {interval}s...")

                    time.sleep(interval)

            self.service_checks['rabbitmq'].stop_heartbeat()
            print(f"\nCollection completed. Total cycles: {total_iterations}")

        except KeyboardInterrupt:
            print("\nMonitoring stopped by user")
        finally:
            # Гарантируем остановку heartbeat при завершении
            if 'rabbitmq' in self.service_checks:
                self.service_checks['rabbitmq'].stop_heartbeat()
            self._close_sessions()

    def _delayed_heartbeat(self, rabbit_check, delay):
        """Execute heartbeat after delay"""
        time.sleep(delay)
        rabbit_check._heartbeat()

    def _close_sessions(self):
        """Close all sessions to free resources"""
        for service_name, check in self.service_checks.items():
            if hasattr(check, 'close_sessions'):
                check.close_sessions()
                print(f"Closed sessions for {service_name}")

    def _display_snapshot(self, snapshot, current_cycle, total_cycles):
        """Display current snapshot to console"""
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
        total_nodes = rabbit_data['total_nodes']
        reachable_nodes = rabbit_data['reachable_nodes']

        print(f"   Nodes: {reachable_nodes}/{total_nodes} reachable")

        # Статус репликации с пояснением
        if total_nodes == 1:
            repl_status = "Single node (no replication)"
        elif total_nodes == 2:
            repl_status = "2-node cluster (needs both)"
        else:
            quorum = (total_nodes // 2) + 1
            repl_status = f"{total_nodes}-node cluster (needs {quorum} for quorum)"

        print("   Cluster Health:")
        print(f"     {'✅' if health['replication_ok'] else '❌'} Replication: {repl_status}")
        print(
            f"     {'✅' if health['uptime_ok'] else '⚠️ '} Uptime: {'All nodes >10min' if health['uptime_ok'] else 'Some nodes <10min'}")

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
                # print(f"    {status_icon} {service_type}: {instance['state']} on {instance['host']}")

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

            # print(f"    {status_icon} {hv['name']}{instances_info}")


if __name__ == "__main__":
    pulse = Pulse()
    pulse.run()