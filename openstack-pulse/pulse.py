#!/usr/bin/env python3
"""
OpenStack Pulse - Lightweight diagnostic tool
"""

import time
import sys
import os

# Add project directories to Python path
sys.path.append(os.path.join(os.path.dirname(__file__), 'services'))
sys.path.append(os.path.join(os.path.dirname(__file__), 'config'))

from config.config import Config
from services.nova import NovaCheck


class Pulse:
    def __init__(self):
        # Load configuration
        self.config = Config()

        # Initialize Nova check with session
        self.nova_check = NovaCheck(self.config.session)

        # Storage for snapshots
        self.snapshots = []

    def collect_metrics(self):
        """Collect metrics from all services"""
        snapshot = {
            'timestamp': time.time(),
            'nova': self.nova_check.run_check()
        }
        return snapshot

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
        print(f"\n[{time.ctime(snapshot['timestamp'])}] Cycle {current_cycle}/{total_cycles}")

        for service_name in self.config.settings.check_services:
            if service_name in snapshot:
                service_data = snapshot[service_name]
                self._display_service_status(service_name, service_data)

    def _display_service_status(self, service_name, service_data):
        """Display status for specific service"""
        status_icon = "✅" if service_data['status'] == 'OK' else "❌"
        print(f"{status_icon} {service_name.upper()}: {service_data['status']} ({service_data['response_time']}s)")

        # Service-specific display logic
        if service_name == 'nova' and service_data['status'] == 'OK':
            self._display_nova_details(service_data)
        # Add other services here: keystone, neutron, rabbitmq, galera
        # elif service_name == 'keystone' and service_data['status'] == 'OK':
        #     self._display_keystone_details(service_data)

    @staticmethod
    def _display_nova_details(nova_data):
        """Display Nova-specific details"""
        services = nova_data['services']
        critical = services['critical_services']
        hypervisors = nova_data['hypervisors']

        # Critical services status
        # Выводим все сервисы по типам
        print("  Critical Services:")
        for service_key, info in critical.items():
            # Извлекаем binary из ключа (новый формат) или из данных (старый формат)
            binary = info.get('binary', service_key)  # Пробуем оба варианта
            status_icon = "✅" if info['state'] == 'up' else "❌"
            print(f"    {status_icon} {binary}: {info['state']} on {info['host']}")

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
