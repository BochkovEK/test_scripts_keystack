import os
import yaml
import sys
# import argparse
from dotenv import load_dotenv
from typing import Dict, Any, Tuple, List
from enum import Enum

class ServiceType(Enum):
    """Service types for authentication"""
    OPENSTACK = "openstack"
    RABBITMQ = "rabbitmq"
    MARIADB = "galera"


class DotDict:
    """Simple dot-notation access to dictionary attributes"""

    def __init__(self, data: Dict):
        for key, value in data.items():
            if isinstance(value, dict):
                setattr(self, key, DotDict(value))
            else:
                setattr(self, key, value)


class Config:
    """Central configuration provider for all services"""

    def __init__(self, inventory_path=None, config_path=None):
        load_dotenv()
        self.inventory_path = inventory_path
        self.config_path = config_path
        self.project_root = self._get_project_root()
        self.auth = self._load_auth_credentials()
        self._validate_config_files()
        self.settings = self._load_yaml_config()
        self.nodes = self._load_inventory()

    def _get_project_root(self) -> str:
        """Get project root directory"""
        return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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
            service_type: Type of service

        Returns:
            Dictionary with authentication parameters
        """
        auth_handlers = {
            ServiceType.OPENSTACK: self._get_openstack_auth,
            ServiceType.RABBITMQ: self._get_rabbitmq_auth,
            ServiceType.MARIADB: self._get_mariadb_auth
        }

        handler = auth_handlers.get(service_type)
        if handler:
            return handler()

        raise ValueError(f"Unknown service type: {service_type}")

    def _get_openstack_auth(self) -> Dict[str, Any]:
        """Get OpenStack authentication parameters"""
        return {
            'auth_url': self.auth['auth_url'],
            'username': self.auth['username'],
            'password': self.auth['password'],
            'project_name': self.auth['project_name'],
            'user_domain_name': self.auth['user_domain_name'],
            'project_domain_name': self.auth['project_domain_name'],
            'verify': False
        }

    def _get_rabbitmq_auth(self) -> Dict[str, Any]:
        """Get RabbitMQ authentication parameters"""
        return {
            'username': self.auth['rabbit_user'],
            'password': self.auth['rabbit_pass'],
            'port': self.settings.endpoints.rabbitmq_port,
            'nodes': self.nodes['control']
        }

    def _get_mariadb_auth(self) -> Dict[str, Any]:
        """Get MariaDB authentication parameters"""
        return {
            'username': self.auth['mysql_user'],
            'password': self.auth['mysql_pass'],
            'port': self.settings.endpoints.mariadb_port,
            'nodes': self.nodes['control']
        }

    def _validate_config_files(self):
        """Validate that all required configuration files exist"""
        config_path = os.path.join(self.project_root, 'config', 'config.yml')
        if not self.inventory_path:
            inventory_paths = [
                os.path.join(self.project_root, 'inventory.ini'),
                os.path.join(self.project_root, 'inventory')
            ]
        else:
            inventory_paths = self.inventory_path

        if not os.path.exists(config_path):
            self._exit_with_file_error('config.yml', config_path)

        if not any(os.path.exists(path) for path in inventory_paths):
            self._exit_with_file_error('inventory', inventory_paths[0])

    def _load_yaml_config(self) -> DotDict:
        """Load and parse YAML configuration file"""
        config_path = self.config_path or os.path.join(self.project_root, 'config', 'config.yml')
        with open(config_path) as f:
            return DotDict(yaml.safe_load(f))

    def _load_inventory(self) -> Dict[str, List[Tuple[str, str]]]:
        """Load node inventory from Ansible inventory file"""
        print(f"[DEBUG]: self.inventory_pat: {self.inventory_path}")
        if self.inventory_path:
            if os.path.exists(self.inventory_path):
                return self._parse_inventory(self.inventory_path)
            else:
                self._exit_with_file_error('inventory', self.inventory_path)

        inventory_files = ['inventory.ini', 'inventory']

        for filename in inventory_files:
            inventory_path = os.path.join(self.project_root, filename)
            if os.path.exists(inventory_path):
                print(f"📁 Using inventory: {filename} from project root")
                return self._parse_inventory(inventory_path)

        self._exit_with_file_error('inventory', inventory_files[0])

    def _parse_inventory(self, inventory_path: str) -> Dict[str, List[Tuple[str, str]]]:
        """
        Parse Ansible inventory file with host information

        Args:
            inventory_path: Path to inventory file

        Returns:
            Dictionary with node information by section
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
                        self._parse_inventory_line(line, nodes)

            return nodes

        except Exception as e:
            print(f"❌ Error reading inventory: {e}")
            sys.exit(1)

    def _parse_inventory_line(self, line: str, nodes: Dict[str, List[Tuple[str, str]]]):
        """
        Parse a single line from inventory file

        Args:
            line: Inventory file line
            nodes: Nodes dictionary to update
        """
        parts = line.split()
        if not parts:
            return

        display_name = parts[0]
        connect_host = self._extract_connect_host(parts)
        nodes['control'].append((display_name, connect_host))

    def _extract_connect_host(self, parts: List[str]) -> str:
        """
        Extract connection host from inventory parts

        Args:
            parts: Split inventory line parts

        Returns:
            Connection host (IP or hostname)
        """
        for part in parts[1:]:
            if part.startswith('ansible_host='):
                return part.split('=')[1]
        return parts[0]  # Default to display name

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

