#!/usr/bin/env python3
"""
Check supported arguments for evacuate_server in openstacksdk
"""

import inspect
import openstack


def main():
    print("=== Supported arguments for evacuate_server ===")
    print(f"openstacksdk version: {openstack.__version__}\n")

    # Получаем сигнатуру метода
    sig = inspect.signature(openstack.compute.v2._proxy.Proxy.evacuate_server)

    print("Method signature:")
    print(f"  {sig}\n")

    print("Detailed parameters:")
    for param_name, param in sig.parameters.items():
        kind = {
            inspect.Parameter.POSITIONAL_ONLY: "positional-only",
            inspect.Parameter.POSITIONAL_OR_KEYWORD: "positional or keyword",
            inspect.Parameter.VAR_POSITIONAL: "var-positional (*args)",
            inspect.Parameter.KEYWORD_ONLY: "keyword-only",
            inspect.Parameter.VAR_KEYWORD: "var-keyword (**kwargs)",
        }.get(param.kind, "unknown")

        default = "no default" if param.default is inspect.Parameter.empty else repr(param.default)
        annotation = "no annotation" if param.annotation is inspect.Parameter.empty else repr(param.annotation)

        print(f"  {param_name}:")
        print(f"    kind:        {kind}")
        print(f"    default:     {default}")
        print(f"    annotation:  {annotation}")
        print()


if __name__ == "__main__":
    main()
