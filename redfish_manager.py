import sys
import sushy
from sushy import auth, PowerState


def fence_redfish(hostname, power_state='on', username='root', password='r00tme'):
    basic_auth = auth.BasicAuth(username=username, password=password)
    url = "https://" + hostname + "/redfish/v1"
    verify = False

    s = sushy.Sushy(url, auth=basic_auth, verify=verify)
    system = s.get_system()
    # current_state = system.power_state
    if power_state == 'on' or power_state == 'start':
        # print(f"Try to power ON {hostname}...\nNone is ok output")
        return system.reset_system(sushy.RESET_ON)
        # return power_on
    elif power_state == 'restart':
        return system.reset_system(sushy.RESET_MANAGER_FORCE_RESTART)
    elif power_state == 'off':
        return system.reset_system(sushy.ResetType.FORCE_OFF)
    elif power_state == 'shutdown':
        return system.reset_system(sushy.ResetType.GRACEFUL_SHUTDOWN)
    elif power_state == 'check':
        print("Check power state...")
        return system.power_state

# hostname1 = '10.3.17.115'
print(fence_redfish(*sys.argv[1:]))

