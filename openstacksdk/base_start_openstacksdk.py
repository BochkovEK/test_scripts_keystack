#!/usr/bin/env python3

import openstack
import sys
import os


def main():
    try:
        conn = openstack.connect()

        conn.authorize()
        print("✅ Аутентификация успешна")

        servers = list(conn.compute.servers())
        print(f"✅ Найдено ВМ: {len(servers)}")

        for server in servers:
            print(f"📦 {server.name} | {server.status} | {server.hypervisor_hostname}")

        return servers

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()