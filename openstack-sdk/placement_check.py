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

        # 2. Detailed analysis for ALL resource providers
        print("\n" + "=" * 80)
        print("🔍 DETAILED RESOURCE PROVIDER ANALYSIS")
        print("=" * 80)

        # Get all VMs for cross-reference
        try:
            servers = list(conn.compute.servers(all_projects=True))
            print(f"📋 Found {len(servers)} VMs in Nova for cross-reference")
        except Exception as e:
            print(f"❌ Error getting VMs: {e}")
            servers = []

        for provider in rps:
            print(f"\n🎯 Analyzing: {provider.name} ({provider.id})")
            print("-" * 60)

            # Get inventory using direct API call (like Gemini)
            try:
                inventory_resp = conn.placement.get(f'/resource_providers/{provider.id}/inventories')
                inventory_data = inventory_resp.json()
                inventories = inventory_data.get('inventories', {})

                if inventories:
                    print("📦 INVENTORY:")
                    inventory_table = PrettyTable()
                    inventory_table.field_names = ["Resource Class", "Total", "Allocated", "Reserved",
                                                   "Allocation Ratio"]

                    for res_class, res_data in inventories.items():
                        inventory_table.add_row([
                            res_class,
                            res_data.get('total', 0),
                            res_data.get('allocated', 0),
                            res_data.get('reserved', 0),
                            res_data.get('allocation_ratio', 1.0)
                        ])

                    print(inventory_table)
                else:
                    print("📦 No inventory found")

            except Exception as e:
                print(f"📦 Inventory error: {e}")

            # Get allocations using direct API call (like Gemini)
            try:
                allocations_resp = conn.placement.get(f'/resource_providers/{provider.id}/allocations')
                allocations_data = allocations_resp.json()
                allocations = allocations_data.get('allocations', {})

                if allocations:
                    print(f"🔗 ALLOCATIONS ({len(allocations)} consumers):")

                    orphaned_count = 0
                    valid_count = 0

                    for consumer_uuid, alloc_data in allocations.items():
                        resources = alloc_data.get('resources', {})

                        print(f"\n   Consumer: {consumer_uuid}")
                        print(f"   Resources: {', '.join([f'{k}={v}' for k, v in resources.items()])}")

                        # Cross-reference with Nova (like Gemini)
                        try:
                            server = conn.compute.find_server(consumer_uuid, ignore_missing=True)
                            if server:
                                print(f"   ✅ STATUS: Valid VM - {server.name} (Status: {server.status})")
                                valid_count += 1
                            else:
                                print(f"   ❌ STATUS: ORPHANED - No VM found in Nova")
                                orphaned_count += 1

                        except Exception as e:
                            print(f"   ⚠️  STATUS: Error checking VM - {e}")
                            orphaned_count += 1

                    # Summary for this provider
                    print(f"\n   📊 SUMMARY for {provider.name}:")
                    print(f"      Valid allocations: {valid_count}")
                    print(f"      Orphaned allocations: {orphaned_count}")

                    if orphaned_count > 0:
                        print(f"      🚨 ACTION NEEDED: Cleanup {orphaned_count} orphaned allocations")

                else:
                    print("🔗 No allocations found")

            except Exception as e:
                print(f"🔗 Allocations error: {e}")

        # 3. Summary across all providers
        print("\n" + "=" * 80)
        print("📈 CLUSTER-WIDE SUMMARY")
        print("=" * 80)

        total_orphaned = 0
        total_consumers = 0

        for provider in rps:
            try:
                allocations_resp = conn.placement.get(f'/resource_providers/{provider.id}/allocations')
                allocations_data = allocations_resp.json()
                allocations = allocations_data.get('allocations', {})

                provider_orphaned = 0
                for consumer_uuid in allocations.keys():
                    try:
                        server = conn.compute.find_server(consumer_uuid, ignore_missing=True)
                        if not server:
                            provider_orphaned += 1
                            total_orphaned += 1
                    except:
                        provider_orphaned += 1
                        total_orphaned += 1

                total_consumers += len(allocations)

                status = "✅ CLEAN" if provider_orphaned == 0 else f"🚨 {provider_orphaned} ORPHANED"
                print(f"   {provider.name}: {len(allocations)} consumers - {status}")

            except Exception as e:
                print(f"   {provider.name}: Error - {e}")

        print(f"\n📊 TOTAL: {total_consumers} consumers, {total_orphaned} orphaned allocations")

        if total_orphaned > 0:
            print(f"🚨 CLUSTER ACTION NEEDED: Cleanup {total_orphaned} orphaned allocations")

        # 4. Compute services status
        print("\n" + "=" * 80)
        print("🖥️ COMPUTE SERVICES STATUS")
        print("=" * 80)

        services = list(conn.compute.services(binary='nova-compute'))
        services_table = PrettyTable()
        services_table.field_names = ["Host", "Status", "State", "Updated At"]

        for service in services:
            services_table.add_row([
                service.host,
                service.status,
                service.state,
                service.updated_at or "N/A"
            ])

        print(services_table)

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()