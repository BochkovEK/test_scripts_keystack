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

            # Детальная информация об image
            image_info = getattr(server_details, 'image', {})
            if image_info:
                print(f"   Image ID: {image_info.get('id', 'Unknown')}")
                print(
                    f"   Image Name: {conn.image.get_image(image_info['id']).name if image_info.get('id') else 'Unknown'}")
            else:
                print(f"   Image: No image (boot from volume)")

            # Актуальная информация о volumes
            print(
                f"   Attached volumes: {len(server_details.attached_volumes) if hasattr(server_details, 'attached_volumes') else 0}")
            if hasattr(server_details, 'attached_volumes') and server_details.attached_volumes:
                for vol_attach in server_details.attached_volumes:
                    print(
                        f"     - Volume ID: {vol_attach.id}, Delete on termination: {vol_attach.delete_on_termination}")

            # Проверка миграции
            migratable = hasattr(server_details, 'attached_volumes') and server_details.attached_volumes
            print(f"   Live migration: {'✅ Possible' if migratable else '❌ Not possible'}")
            print("-" * 40)

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()