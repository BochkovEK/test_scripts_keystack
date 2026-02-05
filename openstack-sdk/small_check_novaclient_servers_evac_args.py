#!/usr/bin/env python3
"""
Minimal check for nova.servers.evacuate parameters (no inspect, no extra packages)
"""

from novaclient import client as nova_client


def main():
    print("=== Checking nova.servers.evacuate parameters ===\n")

    print("Trying to get parameter info from TypeError and docstring...\n")

    try:
        # Create dummy client (no real auth needed for inspection)
        nova = nova_client.Client(version='2.1')

        # Try to call evacuate without arguments → get TypeError hint
        try:
            nova.servers.evacuate()
        except TypeError as e:
            print("From TypeError (required arguments):")
            print(f"  {e}\n")

        # Show docstring if available
        print("Method docstring (if available):")
        doc = nova.servers.evacuate.__doc__
        print(doc if doc else "No docstring available in this version\n")

        print("\nNote:")
        print(" - Without inspect module, full parameter list is not available.")
        print(" - TypeError shows only required positional arguments.")
        print(" - Docstring may be incomplete or missing in older versions.")

    except ImportError:
        print("Error: python-novaclient is not installed.")
        print("Install it: pip install python-novaclient")
    except Exception as e:
        print(f"Unexpected error: {e}")


if __name__ == "__main__":
    main()