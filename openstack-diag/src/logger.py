"""
Logging module for OpenStack Diagnostics.
Provides simple logging interface for different components.
"""

import logging
import sys
from typing import Optional

from config import Config


class ColorFormatter(logging.Formatter):
    """Custom formatter for colored console output."""

    COLORS = {
        'DEBUG': '\033[36m',      # Cyan
        'INFO': '\033[32m',       # Green
        'WARNING': '\033[33m',    # Yellow
        'ERROR': '\033[31m',      # Red
        'CRITICAL': '\033[41m',   # Red background
        'RESET': '\033[0m'        # Reset
    }

    def format(self, record):
        """Format log record with colors for terminal output."""
        if sys.stdout.isatty():
            levelname = record.levelname
            if levelname in self.COLORS:
                record.levelname = f"{self.COLORS[levelname]}{levelname}{self.COLORS['RESET']}"
                record.msg = f"{self.COLORS[levelname]}{record.msg}{self.COLORS['RESET']}"
        return super().format(record)


# Global caches
_file_handlers = {}
_console_handler = None
_config = None


def _get_file_handler(component: str, level: str, config: Optional[Config] = None) -> logging.Handler:
    """Get or create file handler for component."""
    if config is None:
        config = Config()

    if component not in _file_handlers:
        log_file = config.get_log_path(component)
        handler = logging.FileHandler(filename=log_file, encoding='utf-8')
        handler.setLevel(getattr(logging, level))

        formatter = logging.Formatter(
            '%(asctime)s | %(name)s | %(levelname)-8s | %(filename)s:%(lineno)d | %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )
        handler.setFormatter(formatter)
        _file_handlers[component] = handler

    return _file_handlers[component]


def _get_console_handler(level: str, config: Optional[Config] = None) -> Optional[logging.Handler]:
    """Get or create console handler."""
    if config is None:
        config = Config()

    console_enabled = config.get('logging.console_output', True)
    if not console_enabled:
        return None

    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(getattr(logging, level))

    color_enabled = config.get('logging.color_output', True)
    if sys.stdout.isatty() and color_enabled:
        formatter = ColorFormatter(
            '%(asctime)s | %(levelname)-8s | %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )
    else:
        formatter = logging.Formatter(
            '%(asctime)s | %(levelname)-8s | %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )

    handler.setFormatter(formatter)
    return handler


def get_diagnostics_logger(name: str, config: Optional[Config] = None) -> logging.Logger:
    """Get logger for diagnostics (console=INFO, file=DEBUG)."""
    if config is None:
        config = Config()

    logger = logging.getLogger(f"openstack_diag.diagnostics.{name}")

    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    logger.addHandler(_get_file_handler('diagnostics', 'DEBUG', config))

    console_handler = _get_console_handler('INFO', config)
    if console_handler:
        logger.addHandler(console_handler)

    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    return logger


def get_ansible_logger(name: str, config: Optional[Config] = None) -> logging.Logger:
    """Get logger for ansible (console=DEBUG, file=DEBUG)."""
    if config is None:
        config = Config()

    logger = logging.getLogger(f"openstack_diag.ansible.{name}")

    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    logger.addHandler(_get_file_handler('ansible', 'DEBUG', config))

    console_handler = _get_console_handler('DEBUG', config)
    if console_handler:
        logger.addHandler(console_handler)

    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    return logger

