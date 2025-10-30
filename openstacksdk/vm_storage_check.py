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
            print(f"📦 {server.name}")
            print(f"   Status: {server.status} | Hypervisor: {server.hypervisor_hostname}")

            # Получаем volume attachments
            if hasattr(server, 'attached_volumes') and server.attached_volumes:
                for vol_attach in server.attached_volumes:
                    print(f"   Volume Attachment ID: {vol_attach.id}")

                    # Получаем информацию о volume
                    try:
                        volume = conn.block_storage.get_volume(vol_attach.id)
                        print(f"   Volume Name: {volume.name}")
                        print(f"   Volume Type: {volume.volume_type}")

                        # Image metadata from volume
                        if hasattr(volume, 'volume_image_metadata') and volume.volume_image_metadata:
                            image_name = volume.volume_image_metadata.get('image_name')
                            print(f"   Source Image: {image_name}")
                        else:
                            print(f"   Source Image: No image metadata")

                    except Exception as e:
                        print(f"   Error getting volume info: {e}")
            else:
                print(f"   No volume attachments found")

            print("-" * 40)

    except Exception as e:
        print(f"❌ Ошибка: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()