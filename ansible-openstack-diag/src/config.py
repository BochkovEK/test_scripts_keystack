"""
Configuration management for OpenStack Diagnostics
Centralized configuration loader and path manager
"""

import logging
from pathlib import Path
from typing import Dict, Any, Optional
import yaml


class Config:
    """
    Main configuration class for OpenStack diagnostics
    Handles configuration loading and path resolution
    """

    def __init__(self,
                 config_path: Optional[str] = None,
                 inventory_path: Optional[str] = None,
                 log_dir: Optional[str] = None,
                 reports_dir: Optional[str] = None):
        """
        Initialize configuration with optional path overrides

        Args:
            config_path: Optional path to main configuration file
            inventory_path: Optional path to inventory file
            log_dir: Optional path to log directory
            reports_dir: Optional path to reports directory
        """
        self.base_dir = Path(__file__).parent.parent

        # Store path overrides
        self._config_path = config_path
        self._inventory_path = inventory_path
        self._log_dir = log_dir
        self._reports_dir = reports_dir

        # Load configuration
        self._config = self._load_single_config()
        self._setup_paths()

    def _load_single_config(self) -> Dict[str, Any]:
        """
        Load user configuration - no defaults, only user provided config

        Returns:
            Configuration dictionary
        """
        # Start with empty config
        config = {}

        # Determine which user config file to use
        if self._config_path:
            user_config_file = Path(self._config_path)
        else:
            user_config_file = self.base_dir / "config.yaml"

        # If user config exists - load it
        if user_config_file.exists():
            with open(user_config_file, 'r') as f:
                user_config = yaml.safe_load(f)
                config.update(user_config or {})

        return config

    def _setup_paths(self) -> None:
        """
        Setup all path configurations as instance attributes
        Resolves path priorities: direct arguments -> config file -> defaults
        """
        # Get paths from configuration
        config_paths = self._config.get('paths', {})

        if self._inventory_path:
            self.inventory_path = Path(self._inventory_path)
        else:
            inventory_path = config_paths.get('inventory', 'inventory.ini')
            self.inventory_path = self.base_dir / inventory_path

        if self._log_dir:
            self.log_dir = Path(self._log_dir)
        else:
            log_dir = config_paths.get('log_dir', '/tmp')
            self.log_dir = Path(log_dir)

        if self._reports_dir:
            self.reports_dir = Path(self._reports_dir)
        else:
            reports_dir = config_paths.get('reports_dir', 'reports')
            self.reports_dir = self.base_dir / reports_dir

        # Project structure paths
        self.ansible_dir = config_paths.get('ansible_dir', self.base_dir / 'ansible')
        self.playbooks_dir = config_paths.get('playbooks_dir', self.ansible_dir / 'playbooks')
        self.ansible_cfg_path = config_paths.get('ansible_cfg_path', self.ansible_dir / 'ansible.cfg')

    def get(self, key: str, default: Any = None) -> Any:
        """
        Get configuration value using dot notation

        Args:
            key: Configuration key in dot notation (e.g., 'services.keystone.timeout')
            default: Default value if key is not found

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

    def get_log_path(self, component: str) -> Path:
        """
        Generate log file path for a component

        Args:
            component: Component name (e.g., 'diagnostics', 'ansible')

        Returns:
            Path to log file with fixed name
        """
        filename = f"{component}.log"
        return self.log_dir / filename

    @property
    def log_level(self) -> int:
        """Get log level as logging constant"""
        level_map = {
            'DEBUG': logging.DEBUG,
            'INFO': logging.INFO,
            'WARNING': logging.WARNING,
            'ERROR': logging.ERROR
        }
        level_str = self.get('logging.level', 'INFO')
        return level_map.get(level_str, logging.INFO)

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


# Global configuration instance
_config_instance: Optional[Config] = None


def get_config(config_path: Optional[str] = None,
               inventory_path: Optional[str] = None,
               log_dir: Optional[str] = None,
               reports_dir: Optional[str] = None) -> Config:
    """
    Get or create global configuration instance

    Args:
        config_path: Optional path to configuration file
        inventory_path: Optional path to inventory file
        log_dir: Optional path to log directory
        reports_dir: Optional path to reports directory

    Returns:
        Config instance
    """
    global _config_instance
    if _config_instance is None:
        _config_instance = Config(config_path, inventory_path, log_dir, reports_dir)
    return _config_instance

