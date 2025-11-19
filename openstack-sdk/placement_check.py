#!/usr/bin/env python3

import openstack
import sys
from prettytable import PrettyTable


def main():
    try:
        conn = openstack.connect()
        print("✅ Authentication successful")

        # 1. Get resource providers
        print("\n" + "=" * 80)
        print("📊 RESOURCE PROVIDERS")
        print("=" * 80)

        rps = list(conn.placement.resource_providers())
        print(f"✅ Found resource providers: {len(rps)}")

        rp_table = PrettyTable()
        rp_table.field_names = ["Name", "UUID", "Generation"]

        for provider in rps:
            rp_table.add_row([
                provider.name,
                provider.id,
                provider.generation
            ])

        print(rp_table)

        # 2. Analyze problematic resource provider
        print("\n" + "=" * 80)
        print("🔍 PROBLEMATIC RESOURCE PROVIDER ANALYSIS")
        print("=" * 80)

        problematic_provider = None
        for provider in rps:
            if provider.name == 'cdm-bl-pca11':
                problematic_provider = provider
                break

        if problematic_provider:
            print(f"📋 Found problematic resource provider:")
            print(f"   Name: {problematic_provider.name}")
            print(f"   UUID: {problematic_provider.id}")
            print(f"   Generation: {problematic_provider.generation}")

            # UUID comparison
            expected_uuid = "2a61c6dd-d045-408a-b4e6-9b0358f0a13a"
            print(f"\n🔍 UUID Comparison:")
            print(f"   Current UUID in Placement: {problematic_provider.id}")
            print(f"   Expected UUID from error:  {expected_uuid}")

            if problematic_provider.id != expected_uuid:
                print(f"   ❌ UUID MISMATCH DETECTED!")
                print(f"   💡 This is the root cause of the conflict")
            else:
                print(f"   ✅ UUID matches")

            # Get inventory using correct method
            print(f"\n📦 Getting inventory...")
            try:
                # Correct way to get inventory
                inventory = conn.placement.get(f"/resource_providers/{problematic_provider.id}/inventories")
                if inventory:
                    print("   Inventory found:")
                    for res_class, res_data in inventory['inventories'].items():
                        print(f"     {res_class}: total={res_data.get('total')}, used={res_data.get('allocated')}")
                else:
                    print("   No inventory found")
            except Exception as e:
                print(f"   Inventory error: {e}")

            # Get allocations using correct method
            print(f"\n🔗 Getting allocations...")
            try:
                # Correct way to get allocations
                allocations = conn.placement.get(f"/resource_providers/{problematic_provider.id}/allocations")
                if allocations and 'allocations' in allocations:
                    alloc_data = allocations['allocations']
                    if alloc_data:
                        print(f"   Found {len(alloc_data)} allocation(s):")
                        for consumer_id, alloc in alloc_data.items():
                            print(f"     Consumer: {consumer_id}")
                            for resource, amount in alloc.get('resources', {}).items():
                                print(f"       {resource}: {amount}")
                    else:
                        print("   No allocations found")
                else:
                    print("   No allocations data")
            except Exception as e:
                print(f"   Allocations error: {e}")

        else:
            print("❌ Resource provider 'cdm-bl-pca11' not found")

        # 3. Check compute services
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