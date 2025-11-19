#!/usr/bin/env python3

import openstack
import sys
from prettytable import PrettyTable


def main():
    try:
        conn = openstack.connect()
        conn.authorize()
        print("✅ Authentication successful")

        # 1. Gather resource provider information
        print("\n" + "=" * 80)
        print("📊 RESOURCE PROVIDERS")
        print("=" * 80)

        rps = list(conn.placement.resource_providers())
        print(f"✅ Found resource providers: {len(rps)}")

        rp_table = PrettyTable()
        rp_table.field_names = ["Name", "UUID", "Generation"]

        for rp in rps:
            rp_table.add_row([
                rp.get('name', 'N/A'),
                rp.get('uuid', 'N/A'),
                rp.get('generation', 'N/A')
            ])

        print(rp_table)

        # 2. Check resource inventory
        print("\n" + "=" * 80)
        print("💾 RESOURCE INVENTORY")
        print("=" * 80)

        inventory_table = PrettyTable()
        inventory_table.field_names = ["Provider Name", "Resource Class", "Total", "Reserved", "Allocated", "Step Size"]

        for rp in rps:
            rp_uuid = rp.get('uuid')
            rp_name = rp.get('name', 'N/A')
            try:
                inventory = conn.placement.get_resource_provider_inventory(rp_uuid)
                if inventory:
                    for res_class, res_data in inventory.items():
                        inventory_table.add_row([
                            rp_name,
                            res_class,
                            res_data.get('total', 0),
                            res_data.get('reserved', 0),
                            res_data.get('allocated', 0),
                            res_data.get('step_size', 1)
                        ])
                else:
                    inventory_table.add_row([rp_name, "No inventory", "", "", "", ""])
            except Exception as e:
                inventory_table.add_row([rp_name, f"ERROR: {str(e)[:50]}...", "", "", "", ""])

        print(inventory_table)

        # 3. Check allocations
        print("\n" + "=" * 80)
        print("🔗 RESOURCE ALLOCATIONS")
        print("=" * 80)

        allocations_table = PrettyTable()
        allocations_table.field_names = ["Consumer UUID", "Provider Name", "Resource Class", "Used"]

        allocation_found = False
        for rp in rps:
            rp_uuid = rp.get('uuid')
            rp_name = rp.get('name', 'N/A')
            try:
                allocations = conn.placement.get_resource_provider_allocations(rp_uuid)
                if allocations:
                    for consumer_uuid, alloc_data in allocations.items():
                        resources = alloc_data.get('resources', {})
                        for res_class, amount in resources.items():
                            allocations_table.add_row([
                                consumer_uuid[:8] + "..." if len(consumer_uuid) > 8 else consumer_uuid,
                                rp_name,
                                res_class,
                                amount
                            ])
                            allocation_found = True
            except Exception as e:
                allocations_table.add_row([
                    f"ERROR: {str(e)[:30]}...",
                    rp_name,
                    "",
                    ""
                ])

        if allocation_found:
            print(allocations_table)
        else:
            print("No resource allocations found")

        # 4. Check compute services
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

        # 5. Find specific problematic resource provider
        print("\n" + "=" * 80)
        print("🔍 PROBLEMATIC RESOURCE PROVIDER ANALYSIS")
        print("=" * 80)

        problematic_rp = None
        for rp in rps:
            if rp.get('name') == 'cdm-bl-pca11':
                problematic_rp = rp
                break

        if problematic_rp:
            print(f"🚨 Found problematic resource provider:")
            print(f"   Name: {problematic_rp.get('name')}")
            print(f"   UUID: {problematic_rp.get('uuid')}")
            print(f"   Generation: {problematic_rp.get('generation')}")

            # Check if this UUID matches what nova-compute expects
            print(f"\n📋 Checking if this matches the error UUID from logs...")
            print(f"   Current UUID: {problematic_rp.get('uuid')}")
            print(f"   Expected UUID in error: 2a61c6dd-d045-408a-b4e6-9b0358f0a13a")

            if problematic_rp.get('uuid') != '2a61c6dd-d045-408a-b4e6-9b0358f0a13a':
                print(f"   ❌ UUID MISMATCH - This is the conflict!")
            else:
                print(f"   ✅ UUID matches")
        else:
            print("❌ Resource provider 'cdm-bl-pca11' not found in placement")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()