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

        # 2. Analyze ALL resource providers in detail
        print("\n" + "=" * 80)
        print("🔍 DETAILED RESOURCE PROVIDER ANALYSIS")
        print("=" * 80)

        for provider in rps:
            print(f"\n📋 Resource Provider: {provider.name}")
            print(f"   UUID: {provider.id}")
            print(f"   Generation: {provider.generation}")

            # Get inventory using direct API call with proper endpoint
            try:
                # Correct endpoint for inventory
                inventory = conn.placement.get(
                    f"/resource_providers/{provider.id}/inventories",
                    microversion='1.14'  # Use stable microversion
                )

                if inventory and isinstance(inventory, dict) and 'inventories' in inventory:
                    inv_data = inventory['inventories']
                    print("   📦 Inventory:")
                    for res_class, res_data in inv_data.items():
                        total = res_data.get('total', 0)
                        allocated = res_data.get('allocated', 0)
                        reserved = res_data.get('reserved', 0)
                        allocation_ratio = res_data.get('allocation_ratio', 1.0)

                        status = "🟢" if allocated == 0 else "🟡" if allocated < total else "🔴"
                        print(f"     {res_class}:")
                        print(f"       Total: {total}, Allocated: {allocated}, Reserved: {reserved}")
                        print(f"       Allocation Ratio: {allocation_ratio}")
                        print(f"       Status: {status} {allocated}/{total}")

                else:
                    print("   📦 No inventory data in response")

            except Exception as e:
                print(f"   📦 Inventory error: {e}")

            # Get allocations with proper endpoint
            try:
                allocations = conn.placement.get(
                    f"/resource_providers/{provider.id}/allocations",
                    microversion='1.14'
                )

                if allocations and isinstance(allocations, dict) and allocations.get('allocations'):
                    alloc_data = allocations['allocations']
                    print(f"   🔗 Allocations ({len(alloc_data)}):")

                    for consumer_id, alloc_info in alloc_data.items():
                        resources = alloc_info.get('resources', {})
                        print(f"     Consumer UUID: {consumer_id}")

                        if resources:
                            for resource, amount in resources.items():
                                print(f"       {resource}: {amount}")
                        else:
                            print(f"       No resources allocated")

                else:
                    print("   🔗 No allocations found")

            except Exception as e:
                print(f"   🔗 Allocations error: {e}")

        # 3. Check for the specific problematic case - used resources without VMs
        print("\n" + "=" * 80)
        print("🔎 SPECIFIC PROBLEM ANALYSIS: Used Resources without VMs")
        print("=" * 80)

        # Get all VMs to cross-reference
        try:
            servers = list(conn.compute.servers(all_projects=True))
            active_vms = [server for server in servers if server.status in ['ACTIVE', 'BUILD']]
            print(f"📊 Found {len(servers)} total VMs, {len(active_vms)} active VMs")

            # Check each provider for resource usage vs actual VMs
            for provider in rps:
                print(f"\n🔍 Checking {provider.name}:")

                # Get inventory to see used resources
                try:
                    inventory = conn.placement.get(
                        f"/resource_providers/{provider.id}/inventories",
                        microversion='1.14'
                    )

                    if inventory and 'inventories' in inventory:
                        total_used = 0
                        for res_class, res_data in inventory['inventories'].items():
                            used = res_data.get('allocated', 0)
                            if used > 0:
                                total_used += used
                                print(f"   ⚠️  {res_class}: {used} allocated")

                        # Check if there are VMs on this host
                        vms_on_host = [vm for vm in servers if getattr(vm, 'host', None) == provider.name]
                        print(f"   🖥️  VMs on host: {len(vms_on_host)}")

                        if total_used > 0 and len(vms_on_host) == 0:
                            print(f"   🚨 CRITICAL: Resources allocated but NO VMs on this host!")
                            print(f"   💡 This indicates orphaned allocations that need cleanup")

                except Exception as e:
                    print(f"   Error checking {provider.name}: {e}")

        except Exception as e:
            print(f"Error getting VMs: {e}")

        # 4. Check compute services status
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