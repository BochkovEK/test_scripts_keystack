from neutronclient.v2_0 import client as neutron_client
import time


class NeutronCheck:
    def __init__(self, session):
        self.neutron = neutron_client.Client(session=session)

    def run_check(self):
        """Quick Neutron network status check"""
        start_time = time.time()

        try:
            # Проверка агентов
            agents = self.neutron.list_agents()['agents']

            # Анализ состояния агентов
            agent_stats = self._analyze_agents(agents)

            # Быстрая проверка сетей
            networks = self.neutron.list_networks(limit=5)['networks']

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'agents': agent_stats,
                'networks_count': len(networks),
                'total_agents': len(agents)
            }

        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

    def _analyze_agents(self, agents):
        """Analyze Neutron agents by type"""
        stats = {
            'total': len(agents),
            'up': 0,
            'down': 0,
            'by_type': {}
        }

        # Критичные типы агентов
        critical_agents = ['L3 agent', 'DHCP agent', 'Open vSwitch agent']

        for agent in agents:
            # Счетчики по состоянию
            if agent['alive']:
                stats['up'] += 1
            else:
                stats['down'] += 1

            # Счетчики по типам
            agent_type = agent['agent_type']
            if agent_type not in stats['by_type']:
                stats['by_type'][agent_type] = {'total': 0, 'up': 0, 'down': 0}

            stats['by_type'][agent_type]['total'] += 1
            if agent['alive']:
                stats['by_type'][agent_type]['up'] += 1
            else:
                stats['by_type'][agent_type]['down'] += 1

        # Выделяем критичные агенты
        stats['critical_agents'] = {}
        for agent_type in critical_agents:
            if agent_type in stats['by_type']:
                stats['critical_agents'][agent_type] = stats['by_type'][agent_type]

        return stats