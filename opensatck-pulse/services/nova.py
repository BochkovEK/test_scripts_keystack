import novaclient
import time


class NovaCheck:
    def __init__(self, session):
        # Create Nova client using modern python-novaclient
        self.nova = novaclient.client.Client(
            version='2.1',
            session=session
        )

    def run_check(self):
        """
        Quick Nova services status check
        Returns: dict with service counts and status
        """
        start_time = time.time()

        try:
            # Get all services - modern API
            services = self.nova.services.list()

            # Simple counting
            up_services = [s for s in services if s.state == 'up']
            down_services = [s for s in services if s.state == 'down']
            disabled_services = [s for s in services if s.status == 'disabled']

            # Get hypervisors count
            hypervisors = self.nova.hypervisors.list()

            return {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'services_total': len(services),
                'services_up': len(up_services),
                'services_down': len(down_services),
                'services_disabled': len(disabled_services),
                'hypervisors_count': len(hypervisors)
            }

        except Exception as e:
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }