#!/usr/bin/env python3
"""
Test script for Ansible Executor
Test connectivity using ping module
"""

import sys
from pathlib import Path

# Add src to path for imports
src_path = Path(__file__).parent / 'src'
sys.path.append(str(src_path))

from config import get_config
from ansible_executor import get_ansible_runner


def test_ansible_ping():
    """Test Ansible connectivity using ping module"""
    print("=== Testing Ansible Executor with Ping ===")

    # Load configuration
    config = get_config()
    print(f"✓ Config loaded")
    print(f"  Inventory: {config.inventory_path}")
    print(f"  Ansible dir: {config.ansible_dir}")

    # Get Ansible executor
    runner = get_ansible_runner(config)
    print("✓ Ansible executor initialized")

    # Test available playbooks
    playbooks = runner.get_available_playbooks()
    print(f"✓ Available playbooks: {playbooks}")

    # Run ping test
    print("\n🔍 Running ping test...")
    result = runner.run_playbook("test_ping.yml")

    print(f"✓ Playbook execution completed")
    print(f"  Success: {result['success']}")
    print(f"  Return code: {result['return_code']}")
    print(f"  Status: {result.get('status', 'N/A')}")

    if result['success']:
        print("✅ Ping test PASSED - all nodes are reachable")
    else:
        print("❌ Ping test FAILED")
        print(f"   Error: {result.get('error', 'Unknown error')}")
        if result['stdout']:
            print(f"   Output: {result['stdout'][:200]}...")

    return result['success']


if __name__ == "__main__":
    success = test_ansible_ping()
    if success:
        print("\n🎉 All tests passed! Ansible executor is working.")
        sys.exit(0)
    else:
        print("\n💥 Tests failed!")
        sys.exit(1)