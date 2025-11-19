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
        rp_table.field_names = ["Name", "UUID", "Generation", "Root Provider"]

        for rp in rps:
            rp_table.add_row([rp['name'], rp['uuid'], rp['generation'], rp['root_provider']])

        print(rp_table)

        # 2. Check resource inventory
        print("\n" + "=" * 80)
        print("💾 RESOURCE INVENTORY")
        print("=" * 80)

        inventory_table = PrettyTable()
        inventory_table.field_names = ["Provider Name", "Resource Class", "Total", "Reserved", "Allocated", "Step Size"]

        for rp in rps:
            try:
                inventory = conn.placement.get_resource_provider_inventory(rp['uuid'])
                for res_class, res_data in inventory.items():
                    inventory_table.add_row([
                        rp['name'],
                        res_class,
                        res_data.get('total', 0),
                        res_data.get('reserved', 0),
                        res_data.get('allocated', 0),
                        res_data.get('step_size', 1)
                    ])
            except Exception as e:
                inventory_table.add_row([rp['name'], f"ERROR: {e}", "", "", "", ""])

        print(inventory_table)

        # 3. Check allocations
        print("\n" + "=" * 80)
        print("🔗 RESOURCE ALLOCATIONS")
        print("=" * 80)

        allocations_table = PrettyTable()
        allocations_table.field_names = ["Consumer UUID", "Provider Name", "Resource Class", "Used"]

        for rp in rps:
            try:
                allocations = conn.placement.get_resource_provider_allocations(rp['uuid'])
                if allocations:
                    for consumer_uuid, alloc_data in allocations.items():
                        resources = alloc_data.get('resources', {})
                        for res_class, amount in resources.items():
                            allocations_table.add_row([
                                consumer_uuid[:8] + "...",
                                rp['name'],
                                res_class,
                                amount
                            ])
            except Exception as e:
                allocations_table.add_row([f"ERROR: {e}", rp['name'], "", ""])

        print(allocations_table)

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

        # 5. Find name/UUID conflicts
        print("\n" + "=" * 80)
        print("⚠️ POTENTIAL CONFLICTS")
        print("=" * 80)

        conflicts_found = False
        for rp in rps:
            # Find compute service with same host name
            matching_services = [s for s in services if s.host == rp['name']]
            if not matching_services:
                print(f"❌ Resource provider '{rp['name']}' has no matching compute service")
                conflicts_found = True

        if not conflicts_found:
            print("✅ No conflicts detected")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()