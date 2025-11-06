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
        """Main monitoring loop"""
        print("Starting OpenStack Pulse monitoring...")
        print(f"Check interval: {self.config.check_interval}s")

        try:
            while True:
                # Collect metrics
                snapshot = self.collect_metrics()
                self.snapshots.append(snapshot)

                # Keep only last 30 snapshots (5 minutes)
                if len(self.snapshots) > 30:
                    self.snapshots.pop(0)

                # Simple console output
                nova_status = snapshot['nova']['status']
                response_time = snapshot['nova']['response_time']
                print(f"[{time.ctime(snapshot['timestamp'])}] "
                      f"Nova: {nova_status} ({response_time}s) | "
                      f"Snapshots: {len(self.snapshots)}")

                # Check for problems
                if nova_status == 'ERROR':
                    print(f"ALERT: Nova check failed - {snapshot['nova']['error']}")

                time.sleep(self.config.check_interval)

        except KeyboardInterrupt:
            print("\nMonitoring stopped by user")
        except Exception as e:
            print(f"Fatal error: {e}")
            sys.exit(1)


if __name__ == "__main__":
    pulse = Pulse()
    pulse.run()

