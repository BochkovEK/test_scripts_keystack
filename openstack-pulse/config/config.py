import os
import yaml
from dotenv import load_dotenv
import sys
from typing import Dict, Any
from enum import Enum
# import openstack


class ServiceType(Enum):
    """Service types for authentication"""
    OPENSTACK = "openstack"
    RABBITMQ = "rabbitmq"
    MARIADB = "mariadb"


class DotDict:
    """Simple dot-notation access to dictionary attributes"""

    def __init__(self, data):
        for key, value in data.items():
            if isinstance(value, dict):
                setattr(self, key, DotDict(value))
            else:
                setattr(self, key, value)


class Config:
    """Central configuration provider for all services"""

    def __init__(self):
        # Load environment variables from .env
        load_dotenv()

        # Get project root directory
        self.project_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

        # Load authentication credentials
        self.auth = self._load_auth_credentials()

        # Validate required configuration files
        self._check_required_files()

        # Load YAML configuration
        self.settings = self._load_yaml_config()

        # Load inventory nodes
        self.nodes = self._load_inventory()

    def _load_auth_credentials(self) -> Dict[str, str]:
        """Load authentication credentials from environment variables"""
        return {
            'username': os.getenv('OS_USERNAME'),
            'password': os.getenv('OS_PASSWORD'),
            'project_name': os.getenv('OS_PROJECT_NAME'),
            'user_domain_name': os.getenv('OS_USER_DOMAIN_NAME', 'Default'),
            'project_domain_name': os.getenv('OS_PROJECT_DOMAIN_NAME', 'Default'),
            'auth_url': os.getenv('OS_AUTH_URL'),
            'rabbit_user': os.getenv('RABBIT_USER', 'guest'),
            'rabbit_pass': os.getenv('RABBIT_PASS', 'guest'),
            'mysql_user': os.getenv('MYSQL_USER', 'user'),
            'mysql_pass': os.getenv('MYSQL_PASS', 'pass')
        }

    def get_service_auth(self, service_type: ServiceType) -> Dict[str, Any]:
        """
        Get authentication parameters for specific service type

        Args:
            service_type: Type of service (OPENSTACK, RABBITMQ, MARIADB)

        Returns:
            Dictionary with authentication parameters
        """
        if service_type == ServiceType.OPENSTACK:
            return {
                'auth_url': self.auth['auth_url'],
                'username': self.auth['username'],
                'password': self.auth['password'],
                'project_name': self.auth['project_name'],
                'user_domain_name': self.auth['user_domain_name'],
                'project_domain_name': self.auth['project_domain_name'],
                'verify': False  # Disable SSL verification
            }

        elif service_type == ServiceType.RABBITMQ:
            return {
                'username': self.auth['rabbit_user'],
                'password': self.auth['rabbit_pass'],
                'port': self.settings.endpoints.rabbitmq_port,
                'nodes': self.nodes['control']  # List of RabbitMQ nodes
            }

        elif service_type == ServiceType.MARIADB:
            return {
                'username': self.auth['mysql_user'],
                'password': self.auth['mysql_pass'],
                'nodes': self.nodes['control']  # List of database nodes
            }

        else:
            raise ValueError(f"Unknown service type: {service_type}")

    def _check_required_files(self):
        """Validate that all required configuration files exist"""
        required_files = {
            'config.yml': os.path.join(self.project_root, 'config', 'config.yml'),
            'inventory': [
                os.path.join(self.project_root, 'inventory.ini'),
                os.path.join(self.project_root, 'inventory')
            ]
        }

        # Check config.yml
        if not os.path.exists(required_files['config.yml']):
            self._exit_with_file_error('config.yml', required_files['config.yml'])

        # Check inventory file
        inventory_found = any(os.path.exists(path) for path in required_files['inventory'])
        if not inventory_found:
            self._exit_with_file_error('inventory', required_files['inventory'][0])

    def _load_yaml_config(self) -> DotDict:
        """Load and parse YAML configuration file"""
        config_path = os.path.join(self.project_root, 'config', 'config.yml')
        with open(config_path) as f:
            config_data = yaml.safe_load(f)
        return DotDict(config_data)

    def _load_inventory(self) -> Dict[str, list]:
        """Load node inventory from Ansible inventory file"""
        inventory_files = ['inventory.ini', 'inventory']

        for filename in inventory_files:
            inventory_path = os.path.join(self.project_root, filename)
            if os.path.exists(inventory_path):
                print(f"📁 Using inventory: {filename} from project root")
                return self._parse_inventory(inventory_path)

        # Critical error - inventory is required
        print("❌ CRITICAL: Inventory file not found!")
        print(f"   Expected in project root: {', '.join(inventory_files)}")
        print(f"   Project root: {self.project_root}")
        sys.exit(1)

    def _parse_inventory(self, inventory_path: str) -> Dict[str, list]:
        """
        Parse simple Ansible inventory file

        Expected format:
        [control]
        controller1
        controller2
        controller3
        """

        nodes = {'control': []}

        try:
            with open(inventory_path, 'r') as f:
                in_control_section = False

                for line in f:
                    line = line.strip()

                    if line == '[control]':
                        in_control_section = True
                        continue
                    elif line.startswith('['):
                        in_control_section = False
                        continue

                    if in_control_section and line and not line.startswith('#'):
                        parts = line.split()
                        display_name = parts[0]

                        # Ищем ansible_host=IP
                        connect_host = display_name  # по умолчанию используем само имя
                        for part in parts[1:]:
                            if part.startswith('ansible_host='):
                                connect_host = part.split('=')[1]
                                break

                        nodes['control'].append((display_name, connect_host))
            return nodes

        #     with open(inventory_path, 'r') as f:
        #         in_control_section = False
        #
        #         for line in f:
        #             line = line.strip()
        #
        #             if line == '[control]':
        #                 in_control_section = True
        #                 continue
        #             elif line.startswith('['):
        #                 in_control_section = False
        #                 continue
        #
        #             if in_control_section and line and not line.startswith('#'):
        #                 host = line.split()[0]  # Take first word as hostname
        #                 if host and not host.startswith('ansible_'):
        #                     nodes['control'].append(host)
        #
        #     return nodes
        #
        except Exception as e:
            print(f"❌ Error reading inventory: {e}")
            sys.exit(1)

    def _exit_with_file_error(self, file_type: str, expected_path: str):
        """Exit with descriptive error message for missing files"""
        print(f"❌ CRITICAL: {file_type} not found!")
        print(f"📂 Expected: {expected_path}")
        print("")

        if file_type == 'config.yml':
            print("💡 Config file must be named exactly 'config.yml'")
        elif file_type == 'inventory':
            print("💡 Inventory file must be 'inventory' or 'inventory.ini'")

        sys.exit(1)