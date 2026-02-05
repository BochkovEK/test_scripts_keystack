#!/usr/bin/env python3
"""
Minimal check for openstack.compute.evacuate_server parameters
"""

import openstack


def main():
    print("=== Checking openstack.compute.evacuate_server parameters ===\n")

    print("Trying to get parameter info from TypeError and docstring...\n")

    try:
        # Create dummy connection (no real auth needed for inspection)
        conn = openstack.connect()

        # Try to call evacuate_server without arguments → get TypeError hint
        try:
            conn.compute.evacuate_server()
        except TypeError as e:
            print("From TypeError (required arguments):")
            print(f"  {e}\n")

        # Show docstring if available
        print("Method docstring (if available):")
        doc = conn.compute.evacuate_server.__doc__
        print(doc if doc else "No docstring available in this version\n")

    except ImportError:
        print("Error: openstacksdk is not installed.")
        print("Install it: pip install openstacksdk")
    except Exception as e:
        print(f"Unexpected error: {e}")


if __name__ == "__main__":
    main()