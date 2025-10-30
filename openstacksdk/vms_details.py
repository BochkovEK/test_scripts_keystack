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

            # Выводим все атрибуты объекта server_details
            print(f"   All attributes:")
            for attr in dir(server_details):
                if not attr.startswith('_'):  # Только публичные атрибуты
                    try:
                        value = getattr(server_details, attr)
                        if not callable(value):  # Только не-функции
                            print(f"     {attr}: {value}")
                    except:
                        print(f"     {attr}: <cannot access>")

            print("-" * 40)

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()