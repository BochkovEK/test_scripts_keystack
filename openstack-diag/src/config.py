"""
Configuration management for OpenStack Diagnostics
Handles paths, settings, and environment variables
"""

import os
import logging
from pathlib import Path
from typing import Dict, Any, Optional
import yaml


class Config:
    """
    Central configuration management for OpenStack diagnostics
    Loads settings from default config, user config, environment variables
    """

    def __init__(self, config_path: Optional[str] = None):
        """
        Initialize configuration

        Args:
            config_path: Optional path to user configuration file
        """
        self.base_dir = Path(__file__).parent.parent
        self._config = self._load_configuration(config_path)
        self._setup_paths()
        self._ensure_directories()

    def _load_configuration(self, config_path: Optional[str]) -> Dict[str, Any]:
        """
        Load configuration with environment overrides
        """
        # Load default configuration
        default_config_path = self.base_dir / "config" / "default_config.yaml"
        with open(default_config_path, 'r') as f:
            config = yaml.safe_load(f)

        # COMPLETELY REPLACE with user config if provided
        if config_path and Path(config_path).exists():
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)  # Полная замена

        # Apply environment overrides to the final config
        self._apply_environment_overrides(config)

        return config

    @staticmethod
    def _apply_environment_overrides(config: Dict[str, Any]) -> None:
        """
        Apply environment variable overrides to configuration

        Args:
            config: Configuration dictionary to update
        """
        # Log directory from environment
        if os.getenv('OPENSTACK_DIAG_LOG_DIR'):
            config['paths']['log_dir'] = os.getenv('OPENSTACK_DIAG_LOG_DIR')

        # Log level from environment
        if os.getenv('OPENSTACK_DIAG_LOG_LEVEL'):
            config['logging']['level'] = os.getenv('OPENSTACK_DIAG_LOG_LEVEL')

    def _setup_paths(self) -> None:
        """
        Setup and validate all path configurations
        """
        paths = self._config['paths']

        # Absolute paths (can be outside project)
        self.log_dir = Path(paths['log_dir'])

        # Relative to project base directory
        self.reports_dir = self.base_dir / paths['reports_dir']
        self.config_dir = self.base_dir / "config"

        # Ansible paths
        self.ansible_dir = self.base_dir / "ansible"
        self.ansible_inventory = self.config_dir / "inventory.yml"
        self.playbooks_dir = self.ansible_dir / "playbooks"

    def get_log_path(self, component: str) -> Path:
        """
        Generate log file path for a component

        Args:
            component: Component name (e.g., 'ansible', 'keystone')

        Returns:
            Path to log file with timestamp
        """
        from datetime import datetime
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{component}_{timestamp}.log"
        return self.log_dir / filename

    def get(self, key: str, default: Any = None) -> Any:
        """
        Get configuration value using dot notation

        Args:
            key: Configuration key (e.g., 'logging.level')
            default: Default value if key not found

        Returns:
            Configuration value or default
        """
        keys = key.split('.')
        value = self._config

        try:
            for k in keys:
                value = value[k]
            return value
        except (KeyError, TypeError):
            return default

    @property
    def log_level(self) -> int:
        """
        Get log level as logging constant

        Returns:
            logging constant (DEBUG, INFO, etc.)
        """
        level_map = {
            'DEBUG': logging.DEBUG,
            'INFO': logging.INFO,
            'WARNING': logging.WARNING,
            'ERROR': logging.ERROR
        }
        return level_map.get(self.get('logging.level'), logging.INFO)

    @property
    def nodes(self) -> Dict[str, list]:
        """Get nodes configuration"""
        return self.get('nodes', {})

    @property
    def services(self) -> Dict[str, Any]:
        """Get services configuration"""
        return self.get('services', {})

    @property
    def thresholds(self) -> Dict[str, Any]:
        """Get thresholds configuration"""
        return self.get('thresholds', {})

    @property
    def ansible_timeout(self) -> int:
        """Get Ansible execution timeout"""
        return self.get('ansible.timeout', 300)

    def validate(self) -> bool:
        """
        Validate configuration

        Returns:
            True if configuration is valid
        """
        # Check if inventory file exists
        if not self.ansible_inventory.exists():
            logging.warning(f"Inventory file not found: {self.ansible_inventory}")
            return False

        # Check if playbooks directory exists
        if not self.playbooks_dir.exists():
            logging.warning(f"Playbooks directory not found: {self.playbooks_dir}")
            return False

        return True


# Global configuration instance
_config_instance: Optional[Config] = None


def get_config(config_path: Optional[str] = None) -> Config:
    """
    Get or create global configuration instance

    Args:
        config_path: Optional path to configuration file

    Returns:
        Config instance
    """
    global _config_instance
    if _config_instance is None:
        _config_instance = Config(config_path)
    return _config_instance