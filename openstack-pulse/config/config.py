import os
import yaml
import sys
from dotenv import load_dotenv
from typing import Dict, Any, Tuple, List
from enum import Enum


class ServiceType(Enum):
    """Enumeration of supported service types for authentication"""
    OPENSTACK = "openstack"
    RABBITMQ = "rabbitmq"
    MARIADB = "galera"
    ADMINUI = 'adminui'


class DotDict:
    """
    Wrapper class providing dot-notation access to dictionary attributes.

    Recursively converts nested dictionaries into DotDict instances for
    convenient attribute-style access.
    """

    def __init__(self, data: Dict):
        for key, value in data.items():
            if isinstance(value, dict):
                setattr(self, key, DotDict(value))
            else:
                setattr(self, key, value)


class Config:
    """
    Central configuration provider for all services.

    Handles loading and validation of configuration files, environment variables,
    and service-specific authentication parameters.
    """

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
        """Determine the project root directory path"""
        return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    def _load_auth_credentials(self) -> Dict[str, str]:
        """Load authentication credentials from environment variables."""
        return {
            'username': os.getenv('OS_USERNAME'),
            'password': os.getenv('OS_PASSWORD'),
            'project_name': os.getenv('OS_PROJECT_NAME'),
            'user_domain_name': os.getenv('OS_USER_DOMAIN_NAME', 'Default'),
            'project_domain_name': os.getenv('OS_PROJECT_DOMAIN_NAME', 'Default'),
            'auth_url': os.getenv('OS_AUTH_URL'),
            'rabbit_user': os.getenv('RABBIT_USER', 'guest'),
            'rabbit_pass': os.getenv('RABBIT_PASS', 'guest'),
            'rabbit_cacert': os.getenv('RABBIT_CACERT'),
            'mysql_user': os.getenv('MYSQL_USER', 'user'),
            'mysql_pass': os.getenv('MYSQL_PASS', 'pass')
        }

    def get_service_auth(self, service_type: ServiceType) -> Dict[str, Any]:
        """
        Get authentication parameters for specific service type.

        Args:
            service_type: Type of service to get authentication for

        Returns:
            Dictionary with authentication parameters specific to the service

        Raises:
            ValueError: If unknown service type is provided
        """
        auth_handlers = {
            ServiceType.OPENSTACK: self._get_openstack_auth,
            ServiceType.RABBITMQ: self._get_rabbitmq_auth,
            ServiceType.MARIADB: self._get_mariadb_auth,
            ServiceType.ADMINUI: self._get_adminui_auth
        }

        handler = auth_handlers.get(service_type)
        if handler:
            return handler()

        raise ValueError(f"Unknown service type: {service_type}")

    def _get_adminui_auth(self) -> Dict[str, Any]:
        """Get AdminUI specific authentication parameters"""

        # Get adminui section from config.yml
        adminui = getattr(self.settings, 'adminui', {})

        # Get nodes from inventory (control section) or use single host from OS_AUTH_URL
        nodes = self.nodes.get('control', [])

        # If no nodes in inventory, use FQDN from OS_AUTH_URL as single node
        if not nodes and self.auth.get('auth_url'):
            from urllib.parse import urlparse
            parsed = urlparse(self.auth['auth_url'])
            fqdn = parsed.hostname
            nodes = [('adminui', fqdn)]

        return {
            'port': getattr(adminui, 'port', None),
            'scheme': getattr(adminui, 'protocol', getattr(adminui, 'scheme', 'https')),
            'nodes': nodes,
            'cacert_path': getattr(adminui, 'cacert_path', getattr(adminui, 'path_to_cacert', None)),
            'timeout': getattr(adminui, 'timeout', None),
        }

    def _get_openstack_auth(self) -> Dict[str, Any]:
        """Get OpenStack specific authentication parameters"""
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
        """Get RabbitMQ specific authentication parameters"""

        rabbit = getattr(self.settings, 'rabbitmq', {})

        yaml_cacert = getattr(rabbit, 'cacert_path', None) or getattr(rabbit, 'path_to_cacert', None)

        return {
            'username': self.auth['rabbit_user'],
            'password': self.auth['rabbit_pass'],
            'port': int(rabbit.port or getattr(self.settings.endpoints, 'rabbitmq_port', 15672)),
            'scheme': rabbit.protocol or getattr(rabbit, 'scheme', None) or 'https',
            'nodes': self.nodes.get('control', []),
            'cacert_path': self.auth['rabbit_cacert'] or yaml_cacert,
        }

    def _get_mariadb_auth(self) -> Dict[str, Any]:
        """Get MariaDB specific authentication parameters"""
        return {
            'username': self.auth['mysql_user'],
            'password': self.auth['mysql_pass'],
            'port': self.settings.mariadb.port,
            'nodes': self.nodes['control']
        }

    def _validate_config_files(self):
        """
        Validate existence of required configuration files.

        Checks for config.yml and inventory files, exiting with error
        if required files are not found.
        """
        config_path = self.config_path or os.path.join(self.project_root, 'config', 'config.yml')

        # Always validate config.yml existence
        if not os.path.exists(config_path):
            self._exit_with_file_error('config.yml', config_path)

        # Validate inventory file existence
        inventory_found = False

        if self.inventory_path:
            # Check only the provided inventory path
            if os.path.exists(self.inventory_path):
                inventory_found = True
            else:
                self._exit_with_file_error('inventory', self.inventory_path)
        else:
            # Check both default inventory files
            for filename in ['inventory.ini', 'inventory']:
                default_path = os.path.join(self.project_root, filename)
                if os.path.exists(default_path):
                    inventory_found = True
                    break

        if not inventory_found:
            self._exit_with_file_error('inventory', 'inventory or inventory.ini in project root')

    def _load_yaml_config(self) -> DotDict:
        """
        Load and parse YAML configuration file.

        Returns:
            DotDict instance providing dot-notation access to configuration
        """
        config_path = self.config_path or os.path.join(self.project_root, 'config', 'config.yml')
        with open(config_path) as f:
            return DotDict(yaml.safe_load(f))

    def _load_inventory(self) -> Dict[str, List[Tuple[str, str]]]:
        """
        Load node inventory from Ansible inventory file.

        Returns:
            Dictionary mapping section names to lists of (display_name, connect_host) tuples
        """
        if self.inventory_path:
            if os.path.exists(self.inventory_path):
                return self._parse_inventory(self.inventory_path)
            else:
                self._exit_with_file_error('inventory', self.inventory_path)

        # Try default inventory files
        inventory_files = ['inventory.ini', 'inventory']

        for filename in inventory_files:
            inventory_path = os.path.join(self.project_root, filename)
            if os.path.exists(inventory_path):
                print(f"📁 Using inventory: {filename} from project root")
                return self._parse_inventory(inventory_path)

        self._exit_with_file_error('inventory', inventory_files[0])

    def _parse_inventory(self, inventory_path: str) -> Dict[str, List[Tuple[str, str]]]:
        """
        Parse Ansible inventory file extracting host information.

        Args:
            inventory_path: Path to the inventory file

        Returns:
            Dictionary with node information organized by section
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
        Parse a single line from inventory file and update nodes dictionary.

        Args:
            line: Inventory file line to parse
            nodes: Nodes dictionary to update with parsed information
        """
        parts = line.split()
        if not parts:
            return

        display_name = parts[0]
        connect_host = self._extract_connect_host(parts)
        nodes['control'].append((display_name, connect_host))

    def _extract_connect_host(self, parts: List[str]) -> str:
        """
        Extract connection host from inventory line parts.

        Args:
            parts: Split inventory line parts

        Returns:
            Connection host (IP address or hostname)
        """
        for part in parts[1:]:
            if part.startswith('ansible_host='):
                return part.split('=')[1]
        return parts[0]  # Fall back to display name

    def _exit_with_file_error(self, file_type: str, expected_path: str):
        """
        Exit application with descriptive error message for missing files.

        Args:
            file_type: Type of file that was not found
            expected_path: Expected path where file should be located
        """
        print(f"❌ CRITICAL: {file_type} not found!")
        print(f"📂 Expected: {expected_path}")
        print("")

        if file_type == 'config.yml':
            print("💡 Config file must be named exactly 'config.yml'")
        elif file_type == 'inventory':
            print("💡 Inventory file must be 'inventory' or 'inventory.ini'")

        sys.exit(1)

