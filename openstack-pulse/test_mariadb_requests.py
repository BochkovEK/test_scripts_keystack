#!/usr/bin/env python3
"""
Simple MariaDB connection debug script
"""

import mysql.connector
from mysql.connector import Error
import os


def test_mariadb_connection():
    # Get credentials from environment variables
    host = os.getenv('MARIADB_HOST', 'foo')
    user = os.getenv('MYSQL_USER', 'root')
    password = os.getenv('MYSQL_PASS', '')
    port = int(os.getenv('MARIADB_PORT', '3306'))

    print(f"🔍 Testing connection to: {user}@{host}:{port}")

    try:
        # Test connection
        # connection = pymysql.connect(
        #     host=host,  # IP удаленного сервера
        #     user='username',
        #     password='password',
        #     port=3306,
        #     connect_timeout=10,
        #     autocommit=True,
        #     charset='utf8mb4',
        #     cursorclass=pymysql.cursors.DictCursor
        # )
        connection = mysql.connector.connect(
            host=host,
            user='username',
            password='password',
            port=3306,
            # database='your_database',  # опционально
            connection_timeout=10
        )

        if connection.is_connected():
            print("✅ Успешное подключение через mysql.connector!")

            # Пример запроса
            cursor = connection.cursor()
            cursor.execute("SELECT @@version;")
            result = cursor.fetchone()
            print(f"Версия MySQL: {result[0]}")

    except Error as e:
        print(f"❌ Ошибка: {e}")
    finally:
        if 'connection' in locals() and connection.is_connected():
            connection.close()

        # print("✅ Connection successful!")
        #
        # # Test query
        # with connection.cursor() as cursor:
        #     cursor.execute("SHOW GLOBAL STATUS LIKE 'wsrep%'")
        #     results = cursor.fetchall()
        #
        #     print("✅ Galera status query successful!")
        #     print("📊 Galera metrics found:")
        #     for name, value in results:
        #         print(f"   {name}: {value}")
        #
        # connection.close()

    # except pymysql.Error as e:
    #     print(f"❌ Connection failed: {e}")
    #     sys.exit(1)
    # except Exception as e:
    #     print(f"❌ Unexpected error: {e}")
    #     sys.exit(1)


if __name__ == "__main__":
    test_mariadb_connection()