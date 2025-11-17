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
        connection = mysql.connector.connect(
            host=host,
            user=user,
            password=password,
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

if __name__ == "__main__":
    test_mariadb_connection()