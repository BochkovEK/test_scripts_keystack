import openstack
import time
from config.config import ServiceType


class NeutronCheck:
    def __init__(self, config, debug=False):
        """
        Initialize Neutron health check

        Args:
            config: Config object providing service authentication
        """
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(
            **auth_params,
            compute_api_version='2.1'
        )

    def run_check(self):
        """Execute Neutron network status check"""
        start_time = time.time()

        try:
            # Get agents via OpenStackSDK
            agents = list(self.conn.network.agents())

            # Analyze agent status
            agent_stats = self._analyze_agents(agents)

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'agents': agent_stats,
                'total_agents': len(agents)
            }

        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

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