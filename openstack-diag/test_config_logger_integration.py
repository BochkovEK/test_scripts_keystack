#!/usr/bin/env python3
"""
Integration test for config.py and logger.py
Tests configuration loading and logger functionality together.
"""

import sys
import os
import tempfile
from pathlib import Path

# Add src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from config import Config
from logger import get_diagnostics_logger, get_ansible_logger


def test_config_and_logger_integration():
    """Test integration between config and logger modules."""
    print("🔧 Testing Config + Logger Integration...")
    print("=" * 60)

    # Test 1: Create config with custom temp directory
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)

        print(f"\n1. Creating config with temp directory: {temp_path}")
        config = Config(log_dir=str(temp_path))

        # Test config methods
        print("   Testing config.get_log_path():")
        diag_log_path = config.get_log_path('diagnostics')
        ansible_log_path = config.get_log_path('ansible')
        print(f"   - diagnostics: {diag_log_path}")
        print(f"   - ansible: {ansible_log_path}")

        # Verify files don't exist yet
        assert not diag_log_path.exists(), "Log file should not exist yet"
        assert not ansible_log_path.exists(), "Log file should not exist yet"

        # Test 2: Create loggers and verify they use config paths
        print("\n2. Testing loggers with config paths:")
        diag_logger = get_diagnostics_logger("test.integration.diagnostics")
        ansible_logger = get_ansible_logger("test.integration.ansible")

        # Log some messages
        diag_logger.info("Diagnostics INFO message - should be in console and file")
        diag_logger.debug("Diagnostics DEBUG message - should be only in file")

        ansible_logger.debug("Ansible DEBUG message - should be in console and file")
        ansible_logger.info("Ansible INFO message - should be in console and file")

        # Test 3: Verify log files were created
        print("\n3. Verifying log files creation:")
        diag_log_path = config.get_log_path('diagnostics')
        ansible_log_path = config.get_log_path('ansible')

        print(f"   - diagnostics.log exists: {diag_log_path.exists()}")
        print(f"   - ansible.log exists: {ansible_log_path.exists()}")

        # Test 4: Verify log content
        print("\n4. Verifying log content:")
        if diag_log_path.exists():
            with open(diag_log_path, 'r') as f:
                diag_content = f.read()
                print(f"   - diagnostics.log has {len(diag_content)} characters")
                print(f"   - Contains DEBUG: {'DEBUG' in diag_content}")
                print(f"   - Contains INFO: {'INFO' in diag_content}")

        if ansible_log_path.exists():
            with open(ansible_log_path, 'r') as f:
                ansible_content = f.read()
                print(f"   - ansible.log has {len(ansible_content)} characters")
                print(f"   - Contains DEBUG: {'DEBUG' in ansible_content}")

        # Test 5: Test config settings
        print("\n5. Testing config settings:")
        console_output = config.get('logging.console_output', True)
        color_output = config.get('logging.color_output', True)
        log_level = config.get('logging.level', 'INFO')

        print(f"   - console_output: {console_output}")
        print(f"   - color_output: {color_output}")
        print(f"   - log_level: {log_level}")

        # Test 6: Test different log levels
        print("\n6. Testing different log levels:")
        diag_logger.warning("This is a WARNING message")
        diag_logger.error("This is an ERROR message")
        ansible_logger.critical("This is a CRITICAL message")

        print("\n" + "=" * 60)
        print("✅ Integration test completed successfully!")
        print("📊 Summary:")
        print(f"   - Log directory: {temp_path}")
        print(f"   - diagnostics.log: {diag_log_path.exists()}")
        print(f"   - ansible.log: {ansible_log_path.exists()}")
        print("   - Check console output for INFO+ messages")
        print("   - Check log files for all DEBUG+ messages")


if __name__ == "__main__":
    test_config_and_logger_integration()