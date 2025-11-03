#!/usr/bin/env python3
"""
Test script for logger.py
Located in project root: openstack-diag/test_logger.py
"""

import sys
import os

# Add src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from logger import get_logger


def test_logger():
    """Test all logger functionality."""
    print("Testing OpenStack Diagnostics Logger...")

    # Get logger for this test
    logger = get_logger("test_logger")

    print("\n1. Testing log levels:")
    logger.debug("This is a DEBUG message")
    logger.info("This is an INFO message")
    logger.warning("This is a WARNING message")
    logger.error("This is an ERROR message")
    logger.critical("This is a CRITICAL message")

    print("\n2. Testing exception logging:")
    try:
        # Intentionally cause an error
        result = 10 / 0
    except Exception as e:
        logger.error("Division error occurred: %s", e, exc_info=True)

    print("\n3. Testing different module loggers:")
    service_logger = get_logger("test.services.nova")
    service_logger.info("Testing Nova service logger")

    network_logger = get_logger("test.services.neutron")
    network_logger.info("Testing Neutron service logger")

    print("\n4. Testing log formatting:")
    logger.info("Message with %s formatting", "parameterized")
    logger.info("User: %s, Action: %s, Status: %s", "admin", "diagnostics", "started")

    print("\n✅ Logger test completed successfully!")
    print("📝 Check console output and log files for results")


if __name__ == "__main__":
    test_logger()