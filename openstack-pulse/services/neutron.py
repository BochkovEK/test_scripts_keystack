import openstack
import time


class NeutronCheck:
    def __init__(self, session):
        # Создаем клиент OpenStackSDK
        self.conn = openstack.connection.Connection(
            session=session,
            compute_api_version='2.1'
        )

    def run_check(self):
        """Quick Neutron network status check using OpenStackSDK"""
        start_time = time.time()

        try:
            # Получаем агенты через OpenStackSDK
            agents = list(self.conn.network.agents())

            # Анализ состояния агентов
            agent_stats = self._analyze_agents(agents)

            # Быстрая проверка сетей
            # networks = list(self.conn.network.networks(limit=5))

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'agents': agent_stats,
                'total_agents': len(agents)
                # 'networks_count': len(networks),
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
            if agent.is_alive:
                stats['up'] += 1
            else:
                stats['down'] += 1

            # Счетчики по типам
            agent_type = agent.agent_type
            if agent_type not in stats['by_type']:
                stats['by_type'][agent_type] = {'total': 0, 'up': 0, 'down': 0}

            stats['by_type'][agent_type]['total'] += 1
            if agent.is_alive:
                stats['by_type'][agent_type]['up'] += 1
            else:
                stats['by_type'][agent_type]['down'] += 1

        # Выделяем критичные агенты
        stats['critical_agents'] = {}
        for agent_type in critical_agents:
            if agent_type in stats['by_type']:
                stats['critical_agents'][agent_type] = stats['by_type'][agent_type]

        return stats