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

        # 2. Direct API calls to check the problematic resource provider
        print("\n" + "=" * 80)
        print("🔍 DETAILED ANALYSIS OF CDM-BL-PCA11")
        print("=" * 80)

        problematic_rp = None
        for rp in rps:
            if rp.get('name') == 'cdm-bl-pca11':
                problematic_rp = rp
                break

        if problematic_rp:
            rp_uuid = problematic_rp.get('uuid')
            print(f"📋 Resource Provider Details:")
            print(f"   Name: {problematic_rp.get('name')}")
            print(f"   UUID: {rp_uuid}")
            print(f"   Generation: {problematic_rp.get('generation')}")

            # Check if this UUID matches what nova-compute expects
            print(f"\n🔍 UUID Comparison:")
            expected_uuid = "2a61c6dd-d045-408a-b4e6-9b0358f0a13a"
            print(f"   Current UUID in Placement: {rp_uuid}")
            print(f"   Expected UUID from error:  {expected_uuid}")

            if rp_uuid != expected_uuid:
                print(f"   ❌ UUID MISMATCH DETECTED!")
                print(f"   💡 This is the root cause of the conflict")
            else:
                print(f"   ✅ UUID matches")

            # Try to get allocations using direct HTTP request
            print(f"\n📦 Checking allocations...")
            try:
                # Use the placement client directly
                allocations = conn.placement.get_resource_provider_allocations(rp_uuid)
                if allocations:
                    print(f"   ⚠️  Found {len(allocations)} allocation(s):")
                    for consumer_id, alloc in allocations.items():
                        print(f"      Consumer: {consumer_id}")
                        for resource, amount in alloc.get('resources', {}).items():
                            print(f"        {resource}: {amount}")
                else:
                    print(f"   ✅ No allocations found")
            except Exception as e:
                print(f"   ❌ Error checking allocations: {e}")

        else:
            print("❌ Resource provider 'cdm-bl-pca11' not found in placement")

        # 3. Check compute services status
        print("\n" + "=" * 80)
        print("🖥️ COMPUTE SERVICES STATUS")
        print("=" * 80)

        services = list(conn.compute.services(binary='nova-compute'))
        services_table = PrettyTable()
        services_table.field_names = ["Host", "Status", "State", "Disabled Reason"]

        cdm_bl_pca11_service = None
        for service in services:
            services_table.add_row([
                service.host,
                service.status,
                service.state,
                service.disabled_reason or "N/A"
            ])
            if service.host == 'cdm-bl-pca11':
                cdm_bl_pca11_service = service

        print(services_table)

        # 4. Recommended actions
        print("\n" + "=" * 80)
        print("🎯 RECOMMENDED ACTIONS")
        print("=" * 80)

        if problematic_rp and problematic_rp.get('uuid') != expected_uuid:
            current_uuid = problematic_rp.get('uuid')
            print(f"1. DELETE the current resource provider:")
            print(f"   openstack resource provider delete {current_uuid}")
            print(f"")
            print(f"2. RESTART nova-compute on cdm-bl-pca11:")
            print(f"   ssh cdm-bl-pca11 sudo systemctl restart nova-compute")
            print(f"")
            print(f"3. VERIFY new resource provider creation:")
            print(f"   openstack resource provider list --name cdm-bl-pca11")
        else:
            print("No specific actions recommended based on current data")

    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()