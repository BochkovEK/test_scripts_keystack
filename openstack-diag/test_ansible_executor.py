#!/usr/bin/env python3
"""
Test script for Ansible Executor
Test connectivity using predefined playbooks
"""

import sys
from pathlib import Path

# Add src to path for imports
src_path = Path(__file__).parent / 'src'
sys.path.append(str(src_path))

from config import get_config
from ansible_executor import get_ansible_runner

# Playbooks to test
TEST_PLAYBOOKS = [
    "ping.yml",  # Basic connectivity test
    "check_containers.yml",  # Container status check
    # "check_services.yml",    # Service status check
]


def test_playbook(playbook_name: str, runner) -> bool:
    """Test single playbook execution"""
    print(f"\n🔍 Testing playbook: {playbook_name}")

    result = runner.run_playbook(playbook_name)

    print(f"   Success: {result['success']}")
    print(f"   Return code: {result['return_code']}")
    print(f"   Status: {result.get('status', 'N/A')}")

    if result['success']:
        print(f"✅ {playbook_name} - PASSED")
        if result['stdout']:
            print(f"   Output preview: {result['stdout'][:100]}...")
        return True
    else:
        print(f"❌ {playbook_name} - FAILED")
        print(f"   Error: {result.get('error', 'Unknown error')}")

        # Full error output
        if result['stdout']:
            print(f"\n   STDOUT:")
            print("   " + "=" * 50)
            print(result['stdout'])
            print("   " + "=" * 50)

        if result['stderr']:
            print(f"\n   STDERR:")
            print("   " + "=" * 50)
            print(result['stderr'])
            print("   " + "=" * 50)

        return False


def test_ansible_executor():
    """Test Ansible executor with multiple playbooks"""
    print("=== Testing Ansible Executor ===")

    # Load configuration
    config = get_config()
    print(f"✓ Config loaded")
    print(f"  Inventory: {config.inventory_path}")
    print(f"  Ansible dir: {config.ansible_dir}")

    # Get Ansible executor
    runner = get_ansible_runner(config)
    print("✓ Ansible executor initialized")

    # Test available playbooks
    available_playbooks = runner.get_available_playbooks()
    print(f"✓ Available playbooks: {available_playbooks}")

    # Run tests for each playbook
    results = []
    for playbook in TEST_PLAYBOOKS:
        if playbook in available_playbooks:
            success = test_playbook(playbook, runner)
            results.append((playbook, success))
        else:
            print(f"⚠️  Playbook not found: {playbook}")
            results.append((playbook, False))

    # Summary
    print(f"\n📊 Test Summary:")
    passed = sum(1 for _, success in results if success)
    total = len(results)

    for playbook, success in results:
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"   {status} - {playbook}")

    return passed == total


if __name__ == "__main__":
    success = test_ansible_executor()
    if success:
        print("\n🎉 All tests passed! Ansible executor is working.")
        sys.exit(0)
    else:
        print("\n💥 Some tests failed!")
        sys.exit(1)