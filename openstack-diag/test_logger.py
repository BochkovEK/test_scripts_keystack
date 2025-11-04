#!/usr/bin/env python3
"""
Test script for logger.py
Tests both diagnostics and ansible loggers with different log levels.
"""

import sys
import os

# Add src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from logger import get_diagnostics_logger, get_ansible_logger


def test_loggers():
    """Test all logger functionality."""
    print("🧪 Testing OpenStack Diagnostics Logger...")
    print("=" * 50)
    
    # Test 1: Diagnostics logger (console=INFO, file=DEBUG)
    print("\n1. Testing DIAGNOSTICS logger (console: INFO+, file: DEBUG+):")
    diag_logger = get_diagnostics_logger("test_diagnostics")
    
    diag_logger.debug("This DEBUG message should appear only in file")
    diag_logger.info("This INFO message should appear in console and file")
    diag_logger.warning("This WARNING message should appear in console and file")
    diag_logger.error("This ERROR message should appear in console and file")
    
    # Test 2: Ansible logger (console=DEBUG, file=DEBUG)  
    print("\n2. Testing ANSIBLE logger (console: DEBUG+, file: DEBUG+):")
    ansible_logger = get_ansible_logger("test_ansible")
    
    ansible_logger.debug("This ANSIBLE DEBUG should appear in console and file")
    ansible_logger.info("This ANSIBLE INFO should appear in console and file")
    ansible_logger.warning("This ANSIBLE WARNING should appear in console and file")
    
    # Test 3: Exception logging
    print("\n3. Testing exception logging:")
    try:
        # Intentionally cause an error
        result = 10 / 0
    except Exception as e:
        diag_logger.error("Division error occurred: %s", e, exc_info=True)
    
    # Test 4: Different module names
    print("\n4. Testing different module loggers:")
    service_logger = get_diagnostics_logger("test.services.nova")
    service_logger.info("Nova service test message")
    
    network_logger = get_diagnostics_logger("test.services.neutron")
    network_logger.info("Neutron service test message")
    
    print("\n" + "=" * 50)
    print("✅ Logger test completed successfully!")
    print("📝 Check:")
    print("   - Console output above for INFO+ messages")
    print("   - Log files in configured directory for all messages")
    print("   - diagnostics.log should have DEBUG+ messages")
    print("   - ansible.log should have DEBUG+ messages")


if __name__ == "__main__":
    test_loggers()