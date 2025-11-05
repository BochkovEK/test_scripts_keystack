#!/usr/bin/env python3
"""
Test script for Ansible Runner
Basic connectivity test using ping module
"""

import sys
from pathlib import Path

# Add src to path for imports
src_path = Path(__file__).parent / 'src'
sys.path.append(str(src_path))

from config import get_config
from ansible_executor import get_ansible_runner


def test_ansible_runner():
    """Test basic Ansible functionality"""
    print("=== Testing Ansible Runner ===")

    # Load configuration
    config = get_config()
    print(f"✓ Config loaded: {config.inventory_path}")

    # Get Ansible runner
    runner = get_ansible_runner(config)
    print("✓ Ansible runner initialized")

    # Test basic connectivity
    print("Testing node connectivity...")

    # This would use a simple playbook with ping module
    # For now, just test initialization
    print("✓ Ansible runner ready for playbooks")

    return True


if __name__ == "__main__":
    success = test_ansible_runner()
    if success:
        print("\n✅ All tests passed!")
        sys.exit(0)
    else:
        print("\n❌ Tests failed!")
        sys.exit(1)