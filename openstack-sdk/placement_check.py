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

        rps = list(conn.placement.resource_providers())
        print(f"✅ Found resource providers: {len(rps)}")

        rp_table = PrettyTable()
        rp_table.field_names = ["Name", "UUID", "Generation"]

        for provider in rps:
            # Используем правильные атрибуты как в официальном примере
            rp_table.add_row([
                provider.name,
                provider.id,
                provider.generation
            ])

        print(rp_table)

        # 2. Ищем проблемный ресурсный провайдер
        print("\n" + "=" * 80)
        print("🔍 PROBLEMATIC RESOURCE PROVIDER ANALYSIS")
        print("=" * 80)

        # Способ 1: Ищем в списке
        problematic_provider = None
        for provider in rps:
            if provider.name == 'cdm-bl-pca11':
                problematic_provider = provider
                break

        # Способ 2: Используем find_resource_provider (как в официальном примере)
        if not problematic_provider:
            try:
                problematic_provider = conn.placement.find_resource_provider('cdm-bl-pca11')
            except Exception as e:
                print(f"❌ Error finding resource provider: {e}")

        if problematic_provider:
            print(f"📋 Found problematic resource provider:")
            print(f"   Name: {problematic_provider.name}")
            print(f"   UUID: {problematic_provider.id}")
            print(f"   Generation: {problematic_provider.generation}")

            # Проверяем соответствие UUID
            expected_uuid = "2a61c6dd-d045-408a-b4e6-9b0358f0a13a"
            print(f"\n🔍 UUID Comparison:")
            print(f"   Current UUID in Placement: {problematic_provider.id}")
            print(f"   Expected UUID from error:  {expected_uuid}")

            if problematic_provider.id != expected_uuid:
                print(f"   ❌ UUID MISMATCH DETECTED!")
                print(f"   💡 This is the root cause of the conflict")
            else:
                print(f"   ✅ UUID matches")

            # Пробуем получить дополнительную информацию
            try:
                print(f"\n📦 Getting inventory...")
                inventory = conn.placement.get_resource_provider_inventory(problematic_provider.id)
                print(f"   Inventory: {inventory}")
            except Exception as e:
                print(f"   Inventory error: {e}")

            try:
                print(f"\n🔗 Getting allocations...")
                allocations = conn.placement.get_resource_provider_allocations(problematic_provider.id)
                print(f"   Allocations: {allocations}")
            except Exception as e:
                print(f"   Allocations error: {e}")

        else:
            print("❌ Resource provider 'cdm-bl-pca11' not found in placement")

        # 3. Проверяем compute services
        print("\n" + "=" * 80)
        print("🖥️ COMPUTE SERVICES")
        print("=" * 80)

        services = list(conn.compute.services(binary='nova-compute'))
        services_table = PrettyTable()
        services_table.field_names = ["Host", "Status", "State", "Disabled Reason"]

        for service in services:
            services_table.add_row([
                service.host,
                service.status,
                service.state,
                service.disabled_reason or "N/A"
            ])

        print(services_table)

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()