#!/usr/bin/env python3
"""
Test script for config.py
Tests configuration loading, path resolution, and settings access
"""

import sys
import tempfile
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent / 'src'))

from config import get_config, Config
import yaml


def test_basic_config():
    """Test basic configuration loading"""
    print("=== Testing Basic Config ===")

    # Test with default config (should use config.yaml if exists)
    config = get_config()

    print(f"✓ Base dir: {config.base_dir}")
    print(f"✓ Inventory path: {config.inventory_path}")
    print(f"✓ Log dir: {config.log_dir}")
    print(f"✓ Reports dir: {config.reports_dir}")
    print(f"✓ Ansible dir: {config.ansible_dir}")
    print(f"✓ Playbooks dir: {config.playbooks_dir}")


def test_path_overrides():
    """Test path override functionality"""
    print("\n=== Testing Path Overrides ===")

    with tempfile.TemporaryDirectory() as temp_dir:
        # Create test inventory file
        test_inventory = Path(temp_dir) / "test_inventory.ini"
        test_inventory.write_text("[controllers]\ncontroller1\n")

        # Create test config file
        test_config = Path(temp_dir) / "test_config.yaml"
        test_config.write_text("""
paths:
  inventory: "custom_inventory.ini"
  reports_dir: "custom_reports"
  log_dir: "/custom/tmp"

nodes:
  controllers: ["test-controller"]
  computes: ["test-compute1", "test-compute2"]
""")

        # Test with overridden paths
        config = Config(
            config_path=str(test_config),
            inventory_path=str(test_inventory),
            log_dir="/override/tmp",
            reports_dir="/override/reports"
        )

        print(f"✓ Overridden inventory: {config.inventory_path}")
        print(f"✓ Overridden log_dir: {config.log_dir}")
        print(f"✓ Overridden reports_dir: {config.reports_dir}")
        print(f"✓ Nodes from test config: {config.nodes}")


def test_config_access():
    """Test configuration access methods"""
    print("\n=== Testing Config Access ===")

    config = get_config()

    # Test get method with dot notation
    log_level = config.get('logging.level', 'INFO')
    timeout = config.get('ansible.timeout', 300)
    missing_key = config.get('nonexistent.key', 'default_value')

    print(f"✓ logging.level: {log_level}")
    print(f"✓ ansible.timeout: {timeout}")
    print(f"✓ nonexistent.key (with default): {missing_key}")

    # Test properties
    print(f"✓ nodes: {config.nodes}")
    print(f"✓ services: {list(config.services.keys())}")
    print(f"✓ thresholds: {config.thresholds}")
    print(f"✓ log_level constant: {config.log_level}")


def test_log_path_generation():
    """Test log path generation"""
    print("\n=== Testing Log Path Generation ===")

    config = get_config()

    log_path_ansible = config.get_log_path('ansible')
    log_path_keystone = config.get_log_path('keystone')

    print(f"✓ Ansible log path: {log_path_ansible}")
    print(f"✓ Keystone log path: {log_path_keystone}")
    print(f"✓ Log dir in path: {log_path_ansible.parent == config.log_dir}")


def test_singleton_pattern():
    """Test that get_config returns the same instance"""
    print("\n=== Testing Singleton Pattern ===")

    config1 = get_config()
    config2 = get_config()

    print(f"✓ Same instance: {config1 is config2}")
    print(f"✓ Same inventory path: {config1.inventory_path == config2.inventory_path}")


def main():
    """Run all tests"""
    print("Testing OpenStack Diagnostics Config script\n")

    try:
        test_basic_config()
        test_path_overrides()
        test_config_access()
        test_log_path_generation()
        test_singleton_pattern()

        print("\n🎉 All tests completed successfully!")

    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

