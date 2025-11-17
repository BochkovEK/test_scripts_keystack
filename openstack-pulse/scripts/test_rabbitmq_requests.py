import requests
import time
import os
from concurrent.futures import ThreadPoolExecutor, as_completed

# Configuration from environment variables
RABBIT_URLS = [
    os.getenv('RABBIT_URL1', 'http://foo.com:15672'),
    os.getenv('RABBIT_URL2', 'http://bar.com:15672'),
    os.getenv('RABBIT_URL3', 'http://baz.com:15672')
]
RABBIT_USER = os.getenv('RABBIT_USER', 'guest')
RABBIT_PASS = os.getenv('RABBIT_PASS', 'guest')


def test_multiple_sessions():
    """Test RabbitMQ with separate sessions for each node"""

    # Create separate sessions for each node
    sessions = {}
    for url in RABBIT_URLS:
        host = url.replace('http://', '').replace('https://', '').split(':')[0]
        session = requests.Session()
        session.auth = (RABBIT_USER, RABBIT_PASS)
        sessions[host] = session
        print(f"Created session for: {host}")

    print(f"Testing {len(RABBIT_URLS)} RabbitMQ nodes with separate sessions...")
    print(f"URLs: {RABBIT_URLS}")
    print(f"User: {RABBIT_USER}")
    print("-" * 50)

    def check_single_node(url, session):
        """Check single node with dedicated session"""
        start_time = time.time()
        try:
            response = session.get(f"{url}/api/overview", timeout=10)
            end_time = time.time()

            if response.status_code == 200:
                data = response.json()
                queues = data.get('object_totals', {}).get('queues', 0)
                messages = data.get('queue_totals', {}).get('messages', 0)
                return f"{url}: {end_time - start_time:.2f}s - SUCCESS (queues: {queues}, messages: {messages})"
            else:
                return f"{url}: {end_time - start_time:.2f}s - FAILED (status: {response.status_code})"
        except Exception as e:
            return f"{url}: {time.time() - start_time:.2f}s - ERROR: {e}"

    # Test multiple cycles to see connection reuse
    for cycle in range(3):
        print(f"\n--- Cycle {cycle + 1} ---")

        with ThreadPoolExecutor(max_workers=len(RABBIT_URLS)) as executor:
            future_to_url = {}
            for url in RABBIT_URLS:
                host = url.replace('http://', '').replace('https://', '').split(':')[0]
                session = sessions[host]
                future = executor.submit(check_single_node, url, session)
                future_to_url[future] = url

            for future in as_completed(future_to_url):
                result = future.result()
                print(result)

        # Small delay between cycles
        if cycle < 2:
            time.sleep(1)

    print("-" * 50)
    print("Test completed")


if __name__ == "__main__":
    test_multiple_sessions()