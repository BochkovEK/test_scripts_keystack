#!/usr/bin/env python3
"""
Integration test for config.py and logger.py
Tests configuration loading and logger functionality together.
"""

import sys
import os
import tempfile
import logging
from pathlib import Path

# Add src directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

from config import Config
from logger import get_diagnostics_logger, get_ansible_logger


def test_config_and_logger_integration():
    """Test integration between config and logger modules."""
    print("🔧 Testing Config + Logger Integration...")
    print("=" * 60)

    test_passed = True
    errors = []

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)

        try:
        # Test 1: Create config with custom temp directory

            print(f"\n1. Creating config with temp directory: {temp_path}")
            config = Config(log_dir=str(temp_path))

            # Test config methods
            print("   Testing config.get_log_path():")
            diag_log_path = config.get_log_path('diagnostics')
            ansible_log_path = config.get_log_path('ansible')
            print(f"   - diagnostics: {diag_log_path}")
            print(f"   - ansible: {ansible_log_path}")

            # Verify files don't exist yet
            if diag_log_path.exists():
                errors.append("Diagnostics log file should not exist yet")
                test_passed = False
            if ansible_log_path.exists():
                errors.append("Ansible log file should not exist yet")
                test_passed = False

            # Test 2: Create loggers and verify they use config paths
            print("\n2. Testing loggers with config paths:")
            diag_logger = get_diagnostics_logger("test.integration.diagnostics")
            ansible_logger = get_ansible_logger("test.integration.ansible")

            # Log some messages
            diag_logger.info("Diagnostics INFO message - should be in console and file")
            diag_logger.debug("Diagnostics DEBUG message - should be only in file")

            ansible_logger.debug("Ansible DEBUG message - should be in console and file")
            ansible_logger.info("Ansible INFO message - should be in console and file")

            # Force flush all log handlers
            print("\n   Flushing log handlers...")
            for handler in diag_logger.handlers:
                handler.flush()
            for handler in ansible_logger.handlers:
                handler.flush()

            # Test 3: Verify log files were created
            print("\n3. Verifying log files creation:")
            diag_exists = diag_log_path.exists()
            ansible_exists = ansible_log_path.exists()

            print(f"   - diagnostics.log exists: {diag_exists}")
            print(f"   - ansible.log exists: {ansible_exists}")

            if not diag_exists:
                errors.append("diagnostics.log was not created")
                test_passed = False
            if not ansible_exists:
                errors.append("ansible.log was not created")
                test_passed = False

            # Test 4: Verify log content
            print("\n4. Verifying log content:")
            if diag_exists:
                with open(diag_log_path, 'r') as f:
                    diag_content = f.read()
                    print(f"   - diagnostics.log has {len(diag_content)} characters")
                    has_debug = 'DEBUG' in diag_content
                    has_info = 'INFO' in diag_content
                    print(f"   - Contains DEBUG: {has_debug}")
                    print(f"   - Contains INFO: {has_info}")

                    if not has_debug:
                        errors.append("diagnostics.log missing DEBUG messages")
                        test_passed = False
                    if not has_info:
                        errors.append("diagnostics.log missing INFO messages")
                        test_passed = False

            if ansible_exists:
                with open(ansible_log_path, 'r') as f:
                    ansible_content = f.read()
                    print(f"   - ansible.log has {len(ansible_content)} characters")
                    has_debug = 'DEBUG' in ansible_content
                    print(f"   - Contains DEBUG: {has_debug}")

                    if not has_debug:
                        errors.append("ansible.log missing DEBUG messages")
                        test_passed = False

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

            # Final flush
            logging.shutdown()

        except Exception as e:
            test_passed = False
            errors.append(f"Test crashed: {e}")

    print("\n" + "=" * 60)

    if test_passed:
        print("✅ Integration test completed successfully!")
        print("📊 Summary:")
        print(f"   - Log directory: {temp_path}")
        print(f"   - diagnostics.log: {diag_exists}")
        print(f"   - ansible.log: {ansible_exists}")
        print("   - Check console output for INFO+ messages")
        print("   - Check log files for all DEBUG+ messages")
    else:
        print("❌ Integration test FAILED!")
        print("Errors:")
        for error in errors:
            print(f"   - {error}")
        sys.exit(1)


if __name__ == "__main__":
    test_config_and_logger_integration()