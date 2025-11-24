"""
Neutron Network Service monitoring
Checks network agents status and connectivity
"""

import openstack
import time
from config.config import ServiceType


class NeutronCheck:
    """
    Neutron Network Service health monitoring class.

    Provides comprehensive monitoring of Neutron networking services including:
    - Network agent status and availability
    - Critical agent types monitoring (L3, DHCP, Open vSwitch)
    - Agent health and connectivity checks
    - Service response time measurement
    """

    def __init__(self, config, debug=False):
        """
        Initialize Neutron health check.

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
            print(f"🔧 [NEUTRON_DEBUG] Initialized with compute API v2.1")

    def display_details(self, data):
        """
        Display Neutron network service details in formatted output.

        Args:
            data: Dictionary containing agent statistics and status information
        """
        agents = data['agents']

        print(f"  Agents: {agents['up']}/{agents['total']} up")

        if 'by_type' in agents:
            for agent_type, stats in agents['by_type'].items():
                up_count = stats['up']
                down_count = stats['down']

                if down_count == 0:
                    agent_emoji = "🟢"
                    print(f"    {agent_emoji} {agent_type}: {up_count} up")
                elif up_count == 0:
                    agent_emoji = "🔴"
                    print(f"    {agent_emoji} {agent_type}:")
                else:
                    agent_emoji = "🟡"
                    print(f"    {agent_emoji} {agent_type}:")

                if down_count > 0:
                    all_agents = list(self.conn.network.agents())
                    type_agents = [agent for agent in all_agents if agent.agent_type == agent_type]

                    for agent in type_agents:
                        status_icon = "🟢" if agent.is_alive else "🔴"
                        status_text = "" if agent.is_alive else ": down"
                        host_info = agent.host
                        print(f"      {status_icon} {host_info}{status_text}")

    def run_check(self):
        """
        Execute Neutron network service health check.

        Returns:
            Dictionary containing check results:
            - status: Overall check status ('OK' or 'ERROR')
            - response_time: API response time in seconds
            - agents: Detailed agent statistics
            - total_agents: Total number of discovered agents
        """
        start_time = time.time()

        try:
            agents = list(self.conn.network.agents())
            agent_stats = self._analyze_agents(agents)

            if agent_stats['up'] < agent_stats['total']:
                status = 'DEGRADED'
            else:
                status = 'OK'

            result = {
                'status': status,
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
        Analyze Neutron agents by type and operational status.

        Args:
            agents: List of Neutron agent objects from OpenStack

        Returns:
            Dictionary containing agent statistics organized by type and status
        """
        stats = {
            'total': len(agents),
            'up': 0,
            'down': 0,
            'by_type': {}
        }

        # Define critical agent types for network functionality
        critical_agents = ['L3 agent', 'DHCP agent', 'Open vSwitch agent']

        # Process each agent and categorize by type and status
        for agent in agents:
            # Count overall agent status
            if agent.is_alive:
                stats['up'] += 1
            else:
                stats['down'] += 1

            # Categorize agents by type with detailed counts
            agent_type = agent.agent_type
            if agent_type not in stats['by_type']:
                stats['by_type'][agent_type] = {'total': 0, 'up': 0, 'down': 0}

            stats['by_type'][agent_type]['total'] += 1
            if agent.is_alive:
                stats['by_type'][agent_type]['up'] += 1
            else:
                stats['by_type'][agent_type]['down'] += 1

        # Extract critical agents for focused monitoring
        stats['critical_agents'] = {}
        for agent_type in critical_agents:
            if agent_type in stats['by_type']:
                stats['critical_agents'][agent_type] = stats['by_type'][agent_type]

        return stats

    def close_sessions(self):
        """Close OpenStack connection sessions to free resources."""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [NEUTRON_DEBUG] Connections closed")

