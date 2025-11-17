"""
Neutron Network Service monitoring
Checks network agents status and connectivity
"""

import openstack
import time
from config.config import ServiceType


class NeutronCheck:
    def __init__(self, config, debug=False):
        """
        Initialize Neutron health check

        Args:
            config: Config object providing service authentication
            debug: Enable debug output
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(
            **auth_params,
            compute_api_version='2.1'
        )

        if self.debug:
            print(f"🔧 [NEUTRON_DEBUG] Initialized with compute API v2.1")

    def display_details(self, data):
        """Display Neutron-specific details"""
        agents = data['agents']

        print(f"  Agents: {agents['up']}/{agents['total']} up")

        # Smart display for critical agents - show details only if problems
        if 'critical_agents' in agents:
            for agent_type, stats in agents['critical_agents'].items():
                up_count = stats['up']
                down_count = stats['down']

                if down_count == 0:
                    # All agents up - show compact
                    print(f"    🟢 {agent_type}: {up_count} up")
                else:
                    # Some agents down - show detailed breakdown
                    print(f"    ⚠️ {agent_type}:")

                    # Get actual agent objects for this type
                    all_agents = list(self.conn.network.agents())
                    type_agents = [agent for agent in all_agents if agent.agent_type == agent_type]

                    for agent in type_agents:
                        if agent.is_alive:
                            status_icon = "🟢"
                            status_text = ""
                        else:
                            status_icon = "🔴"
                            status_text = ": down"

                        # Show host and status
                        host_info = agent.host
                        print(f"      {status_icon} {host_info}{status_text}")

    def run_check(self):
        """Execute Neutron network status check"""
        start_time = time.time()

        try:
            # Get agents via OpenStackSDK
            agents = list(self.conn.network.agents())

            # Analyze agent status
            agent_stats = self._analyze_agents(agents)

            result = {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'agents': agent_stats,
                'total_agents': len(agents)
            }

            if self.debug:
                print(f"🔧 [NEUTRON_DEBUG] Check completed: {len(agents)} agents")

            return result

        except Exception as e:
            error_result = {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

            if self.debug:
                print(f"🔧 [NEUTRON_DEBUG] Check failed: {error_result}")

            return error_result

    def _analyze_agents(self, agents):
        """
        Analyze Neutron agents by type and status

        Args:
            agents: List of Neutron agent objects

        Returns:
            Dictionary with agent statistics
        """
        stats = {
            'total': len(agents),
            'up': 0,
            'down': 0,
            'by_type': {}
        }

        # Critical agent types
        critical_agents = ['L3 agent', 'DHCP agent', 'Open vSwitch agent']

        for agent in agents:
            # Count by status
            if agent.is_alive:
                stats['up'] += 1
            else:
                stats['down'] += 1

            # Count by type
            agent_type = agent.agent_type
            if agent_type not in stats['by_type']:
                stats['by_type'][agent_type] = {'total': 0, 'up': 0, 'down': 0}

            stats['by_type'][agent_type]['total'] += 1
            if agent.is_alive:
                stats['by_type'][agent_type]['up'] += 1
            else:
                stats['by_type'][agent_type]['down'] += 1

        # Extract critical agents
        stats['critical_agents'] = {}
        for agent_type in critical_agents:
            if agent_type in stats['by_type']:
                stats['critical_agents'][agent_type] = stats['by_type'][agent_type]

        return stats

    def close_sessions(self):
        """Close OpenStack connection sessions"""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [NEUTRON_DEBUG] Connections closed")