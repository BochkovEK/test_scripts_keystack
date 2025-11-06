#!/usr/bin/env python3
"""
Simple Ansible container list script
"""

import sys
from pathlib import Path
import ansible_runner


def main():
    if len(sys.argv) != 3:
        print("Usage: python list_containers.py <inventory> <playbook>")
        sys.exit(1)

    inventory_path = Path(sys.argv[1])
    playbook_path = Path(sys.argv[2])

    if not inventory_path.exists():
        print(f"Error: Inventory not found: {inventory_path}")
        sys.exit(1)

    if not playbook_path.exists():
        print(f"Error: Playbook not found: {playbook_path}")
        sys.exit(1)

    # Run playbook directly with ansible-runner
    result = ansible_runner.run(
        playbook=str(playbook_path),
        inventory=str(inventory_path),
        private_data_dir='.',  # Current directory
        quiet=False  # Show Ansible output
    )

    print(f"\nReturn code: {result.rc}")
    print(f"Status: {result.status}")


if __name__ == "__main__":
    main()