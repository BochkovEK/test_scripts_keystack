#!/usr/bin/env python3
"""
Check supported arguments for evacuate_server in openstacksdk
"""

import inspect
import openstack
import importlib.metadata


def main():
    print("=== Supported arguments for evacuate_server ===\n")

    try:
        version = importlib.metadata.version('openstacksdk')
        print(f"openstacksdk version: {version}\n")
    except Exception:
        print("openstacksdk version: unknown (use pip show openstacksdk)\n")

    try:
        sig = inspect.signature(openstack.compute.v2._proxy.Proxy.evacuate_server)
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
    except Exception as e:
        print(f"Error inspecting method: {e}")


if __name__ == "__main__":
    main()