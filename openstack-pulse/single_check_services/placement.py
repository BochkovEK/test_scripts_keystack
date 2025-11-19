"""
Placement Service monitoring
Checks resource providers, inventory and allocation consistency
"""

import openstack
import time
from config.config import ServiceType


class PlacementCheck:
    def __init__(self, config, debug=False):
        """
        Initialize Placement health check

        Args:
            config: Config object providing service authentication
            debug: Enable debug output
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.OPENSTACK)
        self.conn = openstack.connection.Connection(**auth_params)

        if self.debug:
            print(f"🔧 [PLACEMENT_DEBUG] Initialized")

    def run_single_check(self):
        """Execute single Placement resources health check (one-time)"""
        start_time = time.time()

        try:
            # Get resource providers
            resource_providers = list(self.conn.placement.resource_providers())

            # Get all VMs for cross-reference
            servers = list(self.conn.compute.servers(all_projects=True))

            # Analyze placement state
            placement_stats = self._analyze_placement(resource_providers, servers)

            result = {
                'status': 'OK',
                'response_time': round(time.time() - start_time, 2),
                'placement': placement_stats
            }

            if self.debug:
                print(f"🔧 [PLACEMENT_DEBUG] Single check completed: {len(resource_providers)} resource providers")

            return result

        except Exception as e:
            error_result = {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

            if self.debug:
                print(f"🔧 [PLACEMENT_DEBUG] Single check failed: {error_result}")

            return error_result

    def display_placement_report(self, data):
        """Display Placement allocation consistency report"""
        placement = data['placement']

        print(f"🔍 Placement Allocation Report:")
        print(f"  Resource Providers: {placement['active_providers']}/{placement['total_providers']} with allocations")
        print(
            f"  Total allocations: {placement['total_allocations']} ({placement['valid_allocations']} valid, {placement['orphaned_allocations']} orphaned)")

        # Show providers with orphaned allocations
        providers_with_issues = [p for p in placement['providers'] if p['orphaned_count'] > 0]
        if providers_with_issues:
            print(f"  ⚠️  Allocation inconsistencies detected:")
            for provider in providers_with_issues:
                print(f"    🔴 {provider['name']}: {provider['orphaned_count']} orphaned allocation(s)")

                for allocation in provider['allocations']:
                    if allocation['status'] == 'orphaned':
                        resources_str = ", ".join([f"{k}={v}" for k, v in allocation['resources'].items()])
                        print(f"      Consumer: {allocation['consumer_id']}; Resources: {resources_str}")
                        print(f"      ❓ STATUS: ORPHANED - No VM found in Nova")

        # Show providers with only valid allocations
        clean_providers = [p for p in placement['providers'] if p['orphaned_count'] == 0 and p['allocation_count'] > 0]
        if clean_providers:
            for provider in clean_providers:
                print(f"    🟢 {provider['name']}: {provider['allocation_count']} valid allocation(s)")

        # Show providers without allocations
        inactive_providers = [p for p in placement['providers'] if p['allocation_count'] == 0]
        if inactive_providers:
            for provider in inactive_providers:
                print(f"    🔵 {provider['name']}: no allocations")

    def _analyze_placement(self, resource_providers, servers):
        """
        Analyze Placement resource providers and allocations

        Args:
            resource_providers: List of placement resource providers
            servers: List of Nova servers for cross-reference

        Returns:
            Dictionary with placement statistics
        """
        stats = {
            'total_providers': len(resource_providers),
            'active_providers': 0,
            'total_allocations': 0,
            'valid_allocations': 0,
            'orphaned_allocations': 0,
            'providers': []
        }

        for provider in resource_providers:
            provider_stats = self._analyze_resource_provider(provider, servers)
            stats['providers'].append(provider_stats)

            if provider_stats['allocation_count'] > 0:
                stats['active_providers'] += 1

            stats['total_allocations'] += provider_stats['allocation_count']
            stats['valid_allocations'] += provider_stats['valid_count']
            stats['orphaned_allocations'] += provider_stats['orphaned_count']

        return stats

    def _analyze_resource_provider(self, provider, servers):
        """Analyze individual resource provider and its allocations"""
        provider_info = {
            'name': provider.name,
            'uuid': provider.id,
            'allocation_count': 0,
            'valid_count': 0,
            'orphaned_count': 0,
            'allocations': []
        }

        try:
            # Get allocations for this provider
            allocations_resp = self.conn.placement.get(f'/resource_providers/{provider.id}/allocations')
            allocations_data = allocations_resp.json()
            allocations = allocations_data.get('allocations', {})

            provider_info['allocation_count'] = len(allocations)

            for consumer_id, alloc_data in allocations.items():
                resources = alloc_data.get('resources', {})

                # Check if consumer exists in Nova
                consumer_exists = any(server.id == consumer_id for server in servers)

                allocation_info = {
                    'consumer_id': consumer_id,
                    'resources': resources,
                    'status': 'valid' if consumer_exists else 'orphaned'
                }
                provider_info['allocations'].append(allocation_info)

                if consumer_exists:
                    provider_info['valid_count'] += 1
                else:
                    provider_info['orphaned_count'] += 1

        except Exception as e:
            if self.debug:
                print(f"🔧 [PLACEMENT_DEBUG] Failed to analyze {provider.name}: {e}")

        return provider_info

    def close(self):
        """Close OpenStack connection"""
        if hasattr(self, 'conn'):
            self.conn.close()
            if self.debug:
                print(f"🔧 [PLACEMENT_DEBUG] Connection closed")

