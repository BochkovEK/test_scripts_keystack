#!/usr/bin/env python3

import openstack
import sys
from prettytable import PrettyTable


def main():
    try:
        conn = openstack.connect()
        print("✅ Authentication successful")

        # 1. Получаем ресурсные провайдеры через Placement API
        print("\n" + "=" * 80)
        print("📊 RESOURCE PROVIDERS")
        print("=" * 80)

        # Правильный способ получения ресурсных провайдеров
        rps = list(conn.placement.resource_providers())
        print(f"✅ Found resource providers: {len(rps)}")

        rp_table = PrettyTable()
        rp_table.field_names = ["Name", "UUID", "Generation"]

        for rp in rps:
            # Используем правильные атрибуты из Placement API
            rp_table.add_row([
                rp.get('name', 'N/A'),
                rp.get('uuid', 'N/A'),
                rp.get('generation', 'N/A')
            ])

        print(rp_table)

        # 2. Детальная проверка проблемного провайдера
        print("\n" + "=" * 80)
        print("🔍 DETAILED ANALYSIS")
        print("=" * 80)

        for rp in rps:
            if rp.get('name') == 'cdm-bl-pca11':
                print("📋 Found problematic resource provider:")
                print(f"   Name: {rp.get('name')}")
                print(f"   UUID: {rp.get('uuid')}")
                print(f"   Generation: {rp.get('generation')}")

                # Проверяем инвентарь через Placement API
                try:
                    inventory = conn.placement.get_resource_provider_inventory(rp['uuid'])
                    print(f"   Inventory: {inventory}")
                except Exception as e:
                    print(f"   Inventory error: {e}")
                break
        else:
            print("❌ Resource provider 'cdm-bl-pca11' not found")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()