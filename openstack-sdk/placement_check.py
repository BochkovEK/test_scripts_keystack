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

            # Get inventory
            try:
                inventory = conn.placement.get(f"/resource_providers/{provider.id}/inventories")
                if inventory and 'inventories' in inventory:
                    print("   📦 Inventory:")
                    inv_data = inventory['inventories']
                    for res_class, res_data in inv_data.items():
                        used = res_data.get('allocated', 0)
                        total = res_data.get('total', 0)
                        status = "🟢 OK" if used == 0 else "🟡 USED" if used < total else "🔴 FULL"
                        print(f"     {res_class}: {used}/{total} {status}")

                        # Check for anomalies (used resources but no VMs)
                        if used > 0:
                            print(f"       ⚠️  Resource consumption detected!")
                else:
                    print("   📦 No inventory found")
            except Exception as e:
                print(f"   📦 Inventory error: {e}")

            # Get allocations to see WHAT is consuming resources
            try:
                allocations = conn.placement.get(f"/resource_providers/{provider.id}/allocations")
                if allocations and 'allocations' in allocations:
                    alloc_data = allocations['allocations']
                    if alloc_data:
                        print(f"   🔗 Allocations ({len(alloc_data)}):")
                        for consumer_id, alloc in alloc_data.items():
                            resources = alloc.get('resources', {})
                            print(f"     Consumer: {consumer_id}")
                            for resource, amount in resources.items():
                                print(f"       {resource}: {amount}")

                            # Try to get consumer info (VM, etc.)
                            try:
                                # Check if it's a server
                                server = conn.compute.find_server(consumer_id)
                                if server:
                                    print(f"       🖥️  VM: {server.name} (Status: {server.status})")
                                else:
                                    print(f"       🔍 Consumer not found as VM - may be orphaned allocation")
                            except:
                                print(f"       🔍 Could not identify consumer")
                    else:
                        print("   🔗 No allocations found")
                else:
                    print("   🔗 No allocations data")
            except Exception as e:
                print(f"   🔗 Allocations error: {e}")

        # 3. Check compute services and cross-reference with VMs
        print("\n" + "=" * 80)
        print("🖥️ COMPUTE SERVICES & VM CROSS-REFERENCE")
        print("=" * 80)

        services = list(conn.compute.services(binary='nova-compute'))
        services_table = PrettyTable()
        services_table.field_names = ["Host", "Status", "State", "Disabled Reason"]

        # Get all VMs to see where they're running
        print("\n📋 Checking VM distribution across hosts...")
        try:
            servers = list(conn.compute.servers(all_projects=True))
            host_vm_count = {}

            for server in servers:
                host = getattr(server, 'host', 'Unknown')
                host_vm_count[host] = host_vm_count.get(host, 0) + 1

            print("   VM distribution:")
            for host, count in host_vm_count.items():
                print(f"     {host}: {count} VMs")

            if not servers:
                print("   ℹ️  No VMs found in the cluster")

        except Exception as e:
            print(f"   Error getting VMs: {e}")

        for service in services:
            services_table.add_row([
                service.host,
                service.status,
                service.state,
                service.disabled_reason or "N/A"
            ])

        print(services_table)

        # 4. Summary of anomalies
        print("\n" + "=" * 80)
        print("⚠️  ANOMALY SUMMARY")
        print("=" * 80)

        anomalies_found = False
        for provider in rps:
            try:
                inventory = conn.placement.get(f"/resource_providers/{provider.id}/inventories")
                if inventory and 'inventories' in inventory:
                    inv_data = inventory['inventories']
                    for res_class, res_data in inv_data.items():
                        used = res_data.get('allocated', 0)
                        if used > 0:
                            print(f"❌ {provider.name}: {used} {res_class} allocated but need to check VMs")
                            anomalies_found = True
            except:
                pass

        if not anomalies_found:
            print("✅ No resource allocation anomalies detected")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()