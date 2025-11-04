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
_config = Config()


def _get_file_handler(component: str, level: str) -> logging.Handler:
    """Get or create file handler for component."""
    print(f"DEBUG: Creating file handler for {component} at level {level}")
    if component not in _file_handlers:
        log_file = _config.get_log_path(component)
        print(f"DEBUG: Log file path: {log_file}")
        handler = logging.FileHandler(filename=log_file, encoding='utf-8')
        print(f"DEBUG: FileHandler created: {handler}")
        handler.setLevel(getattr(logging, level))

        formatter = logging.Formatter(
            '%(asctime)s | %(name)s | %(levelname)-8s | %(filename)s:%(lineno)d | %(message)s',
            '%Y-%m-%d %H:%M:%S'
        )
        handler.setFormatter(formatter)
        _file_handlers[component] = handler

    return _file_handlers[component]


def _get_console_handler(level: str) -> Optional[logging.Handler]:
    """Get or create console handler."""
    global _console_handler

    console_enabled = _config.get('logging.console_output', True)
    if not console_enabled:
        return None

    if _console_handler is None or _console_handler.level != getattr(logging, level):
        handler = logging.StreamHandler(sys.stdout)
        handler.setLevel(getattr(logging, level))

        color_enabled = _config.get('logging.color_output', True)
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
        _console_handler = handler

    return _console_handler


def get_diagnostics_logger(name: str) -> logging.Logger:
    """Get logger for diagnostics (console=INFO, file=DEBUG)."""
    print(f"DEBUG: Creating diagnostics logger: {name}")
    logger = logging.getLogger(f"openstack_diag.diagnostics.{name}")

    # Clear existing handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    # Add handlers
    logger.addHandler(_get_file_handler('diagnostics', 'DEBUG'))
    print(f"DEBUG: Logger handlers: {logger.handlers}")

    console_handler = _get_console_handler('INFO')
    if console_handler:
        logger.addHandler(console_handler)

    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    return logger


def get_ansible_logger(name: str) -> logging.Logger:
    """Get logger for ansible (console=DEBUG, file=DEBUG)."""
    logger = logging.getLogger(f"openstack_diag.ansible.{name}")

    # Clear existing handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)

    # Add handlers
    logger.addHandler(_get_file_handler('ansible', 'DEBUG'))

    console_handler = _get_console_handler('DEBUG')
    if console_handler:
        logger.addHandler(console_handler)

    logger.setLevel(logging.DEBUG)
    logger.propagate = False
    return logger


