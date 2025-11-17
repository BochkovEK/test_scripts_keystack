import os
import time
import requests


def test_connection_timeout():
    """Test when RabbitMQ closes idle connections"""
    # Получаем переменные окружения
    username = os.getenv('RABBIT_USER', 'guest')
    password = os.getenv('RABBIT_PASS', 'guest')

    # Собираем URLs из переменных окружения RABBIT_URL1, RABBIT_URL2, etc.
    urls = []
    i = 1
    while True:
        url_var = f'RABBIT_URL{i}'
        url = os.getenv(url_var)
        if url:
            urls.append(url)
            i += 1
        else:
            break

    if not urls:
        print("❌ No RABBIT_URL* environment variables found")
        return

    print(f"Testing {len(urls)} nodes: {urls}")
    print(f"User: {username}")

    # Тестируем разные интервалы
    sleep_times = [3, 4, 5, 6, 7, 10, 15, 30]

    for sleep_time in sleep_times:
        print(f"\n🔍 Testing with {sleep_time} second sleep:")
        print("=" * 40)

        # Создаем сессию
        session = requests.Session()
        session.auth = (username, password)

        for i, url in enumerate(urls):
            print(f"Node {i + 1}: {url}")

            # Первый запрос
            start_time = time.time()
            try:
                response1 = session.get(f"{url}/api/overview", timeout=10)
                time1 = time.time() - start_time
                print(f"  First request: {time1:.3f}s - Status: {response1.status_code}")
            except Exception as e:
                print(f"  First request: ERROR - {e}")
                continue

            # Спим указанное время
            time.sleep(sleep_time)

            # Второй запрос
            start_time = time.time()
            try:
                response2 = session.get(f"{url}/api/overview", timeout=10)
                time2 = time.time() - start_time
                print(f"  Second request: {time2:.3f}s - Status: {response2.status_code}")

                # Анализируем разницу
                if time2 > 1.0:  # Если больше 1 сек - вероятно новое соединение
                    print(f"  ⚠️  Connection was likely closed (took {time2:.3f}s)")
                else:
                    print(f"  ✅ Connection reused (took {time2:.3f}s)")

            except Exception as e:
                print(f"  Second request: ERROR - {e}")

        session.close()


if __name__ == "__main__":
    test_connection_timeout()