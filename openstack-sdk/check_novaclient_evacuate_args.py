#!/usr/bin/env python3
"""
Check supported arguments for nova.servers.evacuate in python-novaclient
"""

import inspect
import pkg_resources


def main():
    print("=== Supported arguments for nova.servers.evacuate ===\n")

    try:
        version = pkg_resources.get_distribution("python-novaclient").version
        print(f"python-novaclient version: {version}\n")
    except Exception:
        print("python-novaclient version: unknown (use pip show python-novaclient)\n")

    try:
        from novaclient.v2 import servers
        sig = inspect.signature(servers.ServerManager.evacuate)

        print("Method signature:")
        print(f"  {sig}\n")

        print("Detailed parameters:")
        for param_name, param in sig.parameters.items():
            kind_str = str(param.kind).split('.')[-1]
            default = "no default" if param.default is inspect.Parameter.empty else repr(param.default)
            annotation = "no annotation" if param.annotation is inspect.Parameter.empty else repr(param.annotation)

            print(f"  {param_name}:")
            print(f"    kind:        {kind_str}")
            print(f"    default:     {default}")
            print(f"    annotation:  {annotation}")
            print()

    except ImportError:
        print("Error: python-novaclient is not installed. Install it with: pip install python-novaclient")
    except Exception as e:
        print(f"Error inspecting method: {e}")


if __name__ == "__main__":
    main()
