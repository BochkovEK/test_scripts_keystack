import os
import yaml
from dotenv import load_dotenv
import openstack
import sys
# import configparser
# from keystoneauth1 import session
# from keystoneauth1.identity import v3
# from typing import Dict, Any


class DotDict:
    """Simple dot-notation access to dictionary attributes"""

    def __init__(self, data):
        for key, value in data.items():
            if isinstance(value, dict):
                setattr(self, key, DotDict(value))
            else:
                setattr(self, key, value)


class Config:
    def __init__(self):
        # Load environment variables from .env
        load_dotenv()

        # Get project root directory
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

        # Load auth credentials first
        self.auth = {
            'username': os.getenv('OS_USERNAME'),
            'password': os.getenv('OS_PASSWORD'),
            'project_name': os.getenv('OS_PROJECT_NAME'),
            'user_domain_name': os.getenv('OS_USER_DOMAIN_NAME', 'Default'),
            'project_domain_name': os.getenv('OS_PROJECT_DOMAIN_NAME', 'Default'),
            'auth_url': os.getenv('OS_AUTH_URL'),
            'rabbit_user': os.getenv('RABBIT_USER', 'guest'),
            'rabbit_pass': os.getenv('RABBIT_PASS', 'guest'),
            'mysql_user': os.getenv('MYSQL_USER', 'monitor'),
            'mysql_pass': os.getenv('MYSQL_PASS', '')
        }

        # Load base config with absolute path
        config_path = os.path.join(self.project_root, 'config', 'config.yml')
        with open(config_path) as f:
            config_data = yaml.safe_load(f)

        # Convert to dot notation for easy access
        self.settings = DotDict(config_data)

        # Create OpenStack connection using auth dict
        self.conn = self._create_connection()
        self.session = self.conn.session

        try:
            self.nodes = self._load_inventory()
        except FileNotFoundError as e:
            print(f"⚠️  {e}")
            print("   Continuing without inventory data...")
            self.nodes = {'controllers': []}  # Пустой inventory

            # Create OpenStack connection
        self.conn = self._create_connection()
        self.session = self.conn.session

    def _load_inventory(self):
        """Load nodes from Ansible inventory file in project root"""
        inventory_files = [
            'inventory.ini',
            'inventory'
        ]

        for filename in inventory_files:
            inventory_path = os.path.join(self.project_root, filename)
            if os.path.exists(inventory_path):
                print(f"📁 Using inventory: {filename} from project root")
                return self._parse_inventory(inventory_path)

        # FATAL ERROR - stop script
        print("❌ CRITICAL: Inventory file not found!")
        print(f"   Expected in project root: {', '.join(inventory_files)}")
        print(f"   Project root: {self.project_root}")
        print("   Please create inventory file with [controllers] section")
        sys.exit(1)

    # def _load_inventory(self):
    #     """Load nodes from Ansible inventory file in project root"""
    #     inventory_files = [
    #         'inventory.ini',
    #         'inventory'
    #     ]
    #
    #     for filename in inventory_files:
    #         inventory_path = os.path.join(self.project_root, filename)
    #         if os.path.exists(inventory_path):
    #             return self._parse_inventory(inventory_path)
    #
    #     raise FileNotFoundError(
    #         f"Inventory file not found in project root. "
    #         f"Expected: {', '.join(inventory_files)}"
    #     )

    def _create_connection(self):
        """Create OpenStack connection using credentials from self.auth"""
        return openstack.connect(
            auth_url=self.auth['auth_url'],
            username=self.auth['username'],
            password=self.auth['password'],
            project_name=self.auth['project_name'],
            user_domain_name=self.auth['user_domain_name'],
            project_domain_name=self.auth['project_domain_name']
        )

    # def _parse_inventory(self, inventory_path):
    #     config = configparser.ConfigParser()
    #     files_read = config.read(inventory_path)
    #     if not files_read:
    #         raise ValueError(f"Failed to read inventory file: {inventory_path}")
    #
    #     nodes = {'controllers': []}
    #
    #     if 'controllers' in config:
    #         for host in config['controllers']:
    #             if host.startswith('ansible_'):
    #                 continue
    #
    #             # Получаем всю строку параметров для хоста
    #             params_string = config['controllers'][host]
    #
    #             # Ищем в строке 'ansible_host=IP'
    #             if 'ansible_host=' in params_string:
    #                 # Извлекаем IP после 'ansible_host='
    #                 ansible_host = params_string.split('ansible_host=')[1].split()[0]
    #                 nodes['controllers'].append(ansible_host)
    #             else:
    #                 # Если нет ansible_host, используем имя хоста как есть
    #                 nodes['controllers'].append(host)
    #
    #     return nodes

    # def _parse_inventory(self, inventory_path):
    #     """Parse Ansible inventory file with error handling"""
    #     config = configparser.ConfigParser()
    #
    #     try:
    #         # ✅ ОБРАБОТКА ОШИБОК ЧТЕНИЯ - ловим проблемы с файлом
    #         files_read = config.read(inventory_path)
    #         if not files_read:
    #             raise ValueError(f"Failed to read inventory file: {inventory_path}")
    #     except configparser.ParsingError as e:
    #         # ✅ ЧЕТКОЕ СООБЩЕНИЕ ОБ ОШИБКЕ - вместо непонятного traceback
    #         print(f"❌ CRITICAL: Invalid inventory file format!")
    #         print(f"   File: {inventory_path}")
    #         print(f"   Error: {e}")
    #         print("💡 Check for syntax errors in inventory file")
    #         sys.exit(1)
    #
    #     nodes = {'controllers': []}
    #
    #     if 'controllers' in config:
    #         for host in config['controllers']:
    #             if host.startswith('ansible_'):
    #                 continue  # ✅ ПРОПУСК СЛУЖЕБНЫХ ПЕРЕМЕННЫХ
    #
    #             # ✅ БЕЗОПАСНЫЙ ПАРСИНГ ПАРАМЕТРОВ - вместо доступа к несуществующим ключам
    #             params_string = config['controllers'][host]
    #             if 'ansible_host=' in params_string:
    #                 # ✅ РУЧНОЙ ПАРСИНГ СТРОКИ - не зависящий от структуры ConfigParser
    #                 # Извлекаем IP после 'ansible_host='
    #                 start = params_string.find('ansible_host=') + len('ansible_host=')
    #                 end = params_string.find(' ', start)
    #                 if end == -1:
    #                     end = len(params_string)  # ✅ ОБРАБОТКА КОНЦА СТРОКИ
    #                 ansible_host = params_string[start:end]
    #                 nodes['controllers'].append(ansible_host)
    #             else:
    #                 # ✅ FALLBACK - если нет ansible_host, используем имя хоста
    #                 nodes['controllers'].append(host)
    #
    #     return nodes

    def _parse_inventory(self, inventory_path):
        """Simple inventory parser"""
        nodes = {'controllers': []}

        try:
            with open(inventory_path, 'r') as f:
                in_controllers_section = False

                for line in f:
                    line = line.strip()

                    if line == '[controllers]':
                        in_controllers_section = True
                        continue
                    elif line.startswith('['):
                        in_controllers_section = False
                        continue

                    if in_controllers_section and line and not line.startswith('#'):
                        # Берем первое слово как hostname
                        host = line.split()[0]
                        if host and not host.startswith('ansible_'):
                            nodes['controllers'].append(host)

        except Exception as e:
            print(f"❌ Error reading inventory: {e}")
            sys.exit(1)

        return nodes

