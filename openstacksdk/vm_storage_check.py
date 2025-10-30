#!/usr/bin/env python3

import openstack
import sys


def main():
    try:
        conn = openstack.connect()
        conn.authorize()
        print("✅ Аутентификация успешна")

        servers = list(conn.compute.servers())
        print(f"✅ Найдено ВМ: {len(servers)}")
        print("\n" + "=" * 80)

        for server in servers:
            server_details = conn.compute.get_server(server.id)

            print(f"📦 {server.name}")
            print(f"   Status: {server.status} | Hypervisor: {server.hypervisor_hostname}")

            # Детальная диагностика
            print(f"   Image: {getattr(server_details, 'image', 'None')}")
            print(f"   Volumes attached: {getattr(server_details, 'volumes_attached', 'None')}")
            print(f"   OS-EXT-STS:vm_state: {getattr(server_details, 'vm_state', 'None')}")
            print(f"   OS-EXT-SRV-ATTR:root_device_name: {getattr(server_details, 'root_device_name', 'None')}")

            # Проверяем блок устройства
            if hasattr(server_details, 'attached_volumes'):
                print(f"   Attached volumes: {server_details.attached_volumes}")

            print("-" * 40)

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()