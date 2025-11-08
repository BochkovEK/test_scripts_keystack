#!/usr/bin/env python3
import requests
import sys
import os


def check_rabbit_node(display_name, connect_host, port=15672, username='guest', password='guest'):
    """Simple script to check RabbitMQ node and parse response"""

    username = os.getenv('RABBIT_USER', 'guest')
    password = os.getenv('RABBIT_PASS', 'guest')

    url = f"http://{connect_host}:{port}"
    auth = (username, password)

    print(f"🔍 Checking: {display_name} -> {url}")
    print(f"🔐 Auth: {username}:***")

    try:
        session = requests.Session()
        session.auth = auth

        # Get nodes data
        response = session.get(f"{url}/api/nodes", timeout=5)
        print(f"📡 Response status: {response.status_code}")

        if response.status_code == 200:
            nodes_data = response.json()
            print(f"📊 Found {len(nodes_data)} nodes in response")

            # Print all node names for debugging
            print("📋 Node names in response:")
            for i, node in enumerate(nodes_data):
                node_name = node.get('name', 'unknown')
                running = node.get('running', False)
                print(f"  {i + 1}. {node_name} (running: {running})")

            # Try to find our node
            short_name = display_name.split('.')[0]  # ctrl3.foo.bar.com -> ctrl3
            rabbit_node_name = f"rabbit@{short_name}"

            print(f"🔎 Looking for: '{rabbit_node_name}' or '{display_name}'")

            found = False
            for node in nodes_data:
                node_name = node.get('name', '')
                if node_name == rabbit_node_name:
                    print(f"✅ Found exact match: {node_name}")
                    print(f"   Status: {'running' if node.get('running') else 'not_running'}")
                    found = True
                    break
                elif display_name in node_name:
                    print(f"🟡 Found partial match: {node_name}")
                    print(f"   Status: {'running' if node.get('running') else 'not_running'}")
                    found = True
                    break

            if not found:
                print("❌ Node not found in response")

        else:
            print(f"❌ HTTP Error: {response.status_code}")

    except Exception as e:
        print(f"💥 Exception: {e}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python debug_rabbit.py <display_name> <connect_host>")
        print("Example: python debug_rabbit.py ctrl1 192.168.1.10")
        print("Example: python debug_rabbit.py ctrl3.foo.bar.com ctrl3.foo.bar.com")
        sys.exit(1)

    display_name = sys.argv[1]
    connect_host = sys.argv[2]

    check_rabbit_node(display_name, connect_host)