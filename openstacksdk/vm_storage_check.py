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
            # Получаем детальную информацию о ВМ
            server_details = conn.compute.get_server(server.id)

            print(f"📦 {server.name}")
            print(f"   Status: {server.status} | Hypervisor: {server.hypervisor_hostname}")

            # Проверяем тип загрузки
            if hasattr(server_details, 'image') and server_details.image:
                print(f"   Boot: from Image (local disk)")
            else:
                print(f"   Boot: from Volume")

            # Проверяем прикрепленные volumes
            if hasattr(server_details, 'volumes_attached') and server_details.volumes_attached:
                print(f"   Volumes attached: {len(server_details.volumes_attached)}")
                for vol in server_details.volumes_attached:
                    print(f"     - Volume ID: {vol['id']}")
            else:
                print(f"   Volumes attached: None")

            # Проверяем возможность миграции
            migratable = hasattr(server_details, 'volumes_attached') and server_details.volumes_attached
            print(f"   Live migration: {'✅ Possible' if migratable else '❌ Not possible'}")
            print("-" * 40)

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()