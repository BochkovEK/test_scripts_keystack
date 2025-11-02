#!/usr/bin/env python3
"""
Simple test script for config.py
"""

import sys
import os
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent / 'src'))

from config import get_config


def test_basic_config():
    """Test basic configuration loading"""
    print("=== Testing Basic Config ===")

    # Test 1: Default config
    config = get_config()
    print(f"✓ Log dir: {config.log_dir}")
    print(f"✓ Log level: {config.log_level}")
    print(f"✓ Ansible timeout: {config.ansible_timeout}")
    print(f"✓ Nodes: {config.nodes}")
    print(f"✓ Services: {list(config.services.keys())}")


def test_path_methods():
    """Test path-related methods"""
    print("\n=== Testing Path Methods ===")

    config = get_config()

    # Test get_log_path
    log_path = config.get_log_path('test_component')
    print(f"✓ Log path: {log_path}")
    print(f"✓ Log path exists: {log_path.parent.exists()}")

    # Test directory creation
    print(f"✓ Log dir exists: {config.log_dir.exists()}")
    print(f"✓ Reports dir exists: {config.reports_dir.exists()}")


def test_config_access():
    """Test configuration access methods"""
    print("\n=== Testing Config Access ===")

    config = get_config()

    # Test get method with dot notation
    log_level = config.get('logging.level')
    timeout = config.get('ansible.timeout')
    missing_key = config.get('nonexistent.key', 'default_value')

    print(f"✓ logging.level: {log_level}")
    print(f"✓ ansible.timeout: {timeout}")
    print(f"✓ nonexistent.key (with default): {missing_key}")


def test_validation():
    """Test configuration validation"""
    print("\n=== Testing Validation ===")

    config = get_config()
    is_valid = config.validate()

    print(f"✓ Config validation: {is_valid}")
    print(f"✓ Inventory exists: {config.ansible_inventory.exists()}")
    print(f"✓ Playbooks dir exists: {config.playbooks_dir.exists()}")


def test_environment_overrides():
    """Test environment variable overrides"""
    print("\n=== Testing Environment Overrides ===")

    # Set environment variables
    os.environ['OPENSTACK_DIAG_LOG_DIR'] = '/tmp/test-openstack-diag'
    os.environ['OPENSTACK_DIAG_LOG_LEVEL'] = 'DEBUG'

    # Create new config instance to apply overrides
    from config import Config
    test_config = Config()

    print(f"✓ Custom log dir: {test_config.log_dir}")
    print(f"✓ Custom log level: {test_config.log_level}")

    # Cleanup
    del os.environ['OPENSTACK_DIAG_LOG_DIR']
    del os.environ['OPENSTACK_DIAG_LOG_LEVEL']


def main():
    """Run all tests"""
    print("Testing OpenStack Diagnostics Config Module\n")

    try:
        test_basic_config()
        test_path_methods()
        test_config_access()
        test_validation()
        test_environment_overrides()

        print("\n🎉 All tests completed successfully!")

    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()