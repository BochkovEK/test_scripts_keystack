import sys
import sushy
from sushy import auth, PowerState


def fence_redfish(hostname, power_state='on', username='root', password='r00tme'):
    basic_auth = auth.BasicAuth(username=username, password=password)
    url = "https://" + hostname + "/redfish/v1"
    verify = False

    s = sushy.Sushy(url, auth=basic_auth, verify=verify)
    system = s.get_system()
    current_state = system.power_state
    if power_state == 'on':
        power_on = system.reset_system(sushy.RESET_ON)
        return power_on


# hostname1 = '10.3.17.115'
print(fence_redfish(sys.argv[1], sys.argv[2]), sys.argv[3], sys.argv[4])

