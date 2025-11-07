import requests
import time
import os

# Configuration from environment variables
RABBIT_URLs = ["http://cdm-bl-pca07.lab.itkey.com:15672", "http://cdm-bl-pca06.lab.itkey.com:15672", "http://cdm-bl-pca08.lab.itkey.com:15672"]
# RABBIT_URL = os.getenv('RABBIT_URL', 'http://localhost:15672')
RABBIT_USER = os.getenv('RABBIT_USER', 'guest')
RABBIT_PASS = os.getenv('RABBIT_PASS', 'guest')

def test_rabbitmq_session():
    """Test RabbitMQ API with session for connection reuse"""

    # Create session with authentication
    session = requests.Session()
    session.auth = (RABBIT_USER, RABBIT_PASS)

    print("Testing RabbitMQ API with session...")
    print(f"URLs: {RABBIT_URLs}")
    print(f"User: {RABBIT_USER}")
    print("-" * 50)

    # Make multiple requests and measure time
    for i in range(5):
        start_time = time.time()

        try:
            for url in RABBIT_URLs:
                response = session.get(f"{url}/api/overview", timeout=10)
                end_time = time.time()
                response_time = end_time - start_time

                if response.status_code == 200:
                    data = response.json()
                    queues = data.get('object_totals', {}).get('queues', 0)
                    messages = data.get('queue_totals', {}).get('messages', 0)

                    print(f"Request {i + 1}: {response_time:.2f}s - SUCCESS (queues: {queues}, messages: {messages})")
                else:
                    print(f"Request {i + 1}: {response_time:.2f}s - FAILED (status: {response.status_code})")

        except requests.exceptions.Timeout:
            end_time = time.time()
            print(f"Request {i + 1}: {end_time - start_time:.2f}s - TIMEOUT")
        except Exception as e:
            end_time = time.time()
            print(f"Request {i + 1}: {end_time - start_time:.2f}s - ERROR: {e}")

        # Small delay between requests
        if i < 4:
            time.sleep(1)

    print("-" * 50)
    print("Test completed")


if __name__ == "__main__":
    test_rabbitmq_session()