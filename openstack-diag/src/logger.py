import logging
import sys
import os
from typing import Optional, Dict, Any
from pathlib import Path

# Import configuration
from config import Config


class ColorFormatter(logging.Formatter):
    """Custom formatter for colored console output."""

    # ANSI color codes
    COLORS = {
        'DEBUG': '\033[36m',  # Cyan
        'INFO': '\033[32m',  # Green
        'WARNING': '\033[33m',  # Yellow
        'ERROR': '\033[31m',  # Red
        'CRITICAL': '\033[41m',  # Red background
        'RESET': '\033[0m'  # Reset
    }

    def format(self, record):
        """Format log record with colors for terminal output."""
        # Add colors only for terminal output
        if sys.stdout.isatty():
            level_name = record.level_name
            if level_name in self.COLORS:
                record.level_name = (f"{self.COLORS[level_name]}{level_name}"
                                     f"{self.COLORS['RESET']}")
                record.msg = (f"{self.COLORS[level_name]}{record.msg}"
                              f"{self.COLORS['RESET']}")

        # Use parent class formatting logic
        return super().format(record)


class DiagnosticsLogger:
    """
    Main logging class for OpenStack Diagnostics.

    Implements Singleton pattern to ensure single logging configuration
    across the entire application.
    """

    # Class variables for Singleton pattern
    _instance = None
    _initialized = False

    def __new__(cls):
        """Singleton pattern implementation - control instance creation."""
        if cls._instance is None:
            cls._instance = super(DiagnosticsLogger, cls).__new__(cls)
        return cls._instance

    def __init__(self):
        """Initialize logger instance only once."""
        if not self._initialized:
            # Initialize configuration and logger
            self.config = Config()
            self.logger = None
            self._setup_logger()
            self._initialized = True

    def _setup_logger(self) -> None:
        """Configure the root logger for the application."""

        # Create root logger with maximum level
        self.logger = logging.getLogger('openstack_diag')
        self.logger.setLevel(logging.DEBUG)

        # Prevent log propagation to avoid duplicate records
        self.logger.propagate = False

        # Clear any existing handlers
        for handler in self.logger.handlers[:]:
            self.logger.removeHandler(handler)

        # Create and add new handlers
        handlers = self._create_handlers()
        for handler in handlers:
            self.logger.addHandler(handler)

    def _create_handlers(self) -> list:
        """Create and configure log handlers based on configuration."""
        handlers = []

        # Define log formats
        detailed_format = (
            '%(asctime)s | %(name)s | %(levelname)-8s | '
            '%(filename)s:%(lineno)d | %(message)s'
        )
        simple_format = '%(asctime)s | %(levelname)-8s | %(message)s'
        date_format = '%Y-%m-%d %H:%M:%S'

        # Create file handler if enabled
        file_enabled = self.config.get('logging.file_output', True)
        if file_enabled:
            file_handler = self._create_file_handler(
                detailed_format, date_format
            )
            handlers.append(file_handler)

        # Create console handler if enabled
        console_enabled = self.config.get('logging.console_output', True)
        if console_enabled:
            console_handler = self._create_console_handler(
                simple_format, date_format
            )
            handlers.append(console_handler)

        return handlers

    def _create_file_handler(self, fmt: str, date_fmt: str) -> logging.Handler:
        """Create and configure file handler for log files."""

        # Get full log file path from config
        log_file = self.config.get_log_path()

        # Create file handler
        handler = logging.FileHandler(
            filename=log_file,
            encoding='utf-8'
        )

        # Set log level from config
        log_level = self.config.get('logging.level', 'INFO')
        handler.setLevel(getattr(logging, log_level))

        # Create and set formatter
        formatter = logging.Formatter(fmt, date_fmt)
        handler.setFormatter(formatter)

        return handler

    def _create_console_handler(self, fmt: str, date_fmt: str) -> logging.Handler:
        """Create and configure console handler for terminal output."""

        # Create console handler (stdout)
        handler = logging.StreamHandler(sys.stdout)

        # Set log level from config
        log_level = self.config.get('logging.level', 'INFO')
        handler.setLevel(getattr(logging, log_level))

        # Use color formatter for terminals if enabled in config
        color_enabled = self.config.get('logging.color_output', True)
        if sys.stdout.isatty() and color_enabled:
            formatter = ColorFormatter(fmt, date_fmt)
        else:
            formatter = logging.Formatter(fmt, date_fmt)

        handler.setFormatter(formatter)
        return handler

    def get_logger(self, name: Optional[str] = None) -> logging.Logger:
        """
        Get logger instance for module.

        Args:
            name: Module name (usually __name__)

        Returns:
            Configured logger instance
        """
        if name:
            return self.logger.getChild(name)
        return self.logger


# Global logger instance for application-wide use
diag_logger = DiagnosticsLogger()


def get_logger(name: Optional[str] = None) -> logging.Logger:
    """
    Factory function to get logger instance.

    Simplified interface for getting configured logger.

    Args:
        name: Module name (usually __name__)

    Returns:
        Configured logger instance
    """
    return diag_logger.get_logger(name)


# Example usage and testing
if __name__ == "__main__":
    logger = get_logger(__name__)

    # Test different log levels
    logger.debug("Debug message - detailed information")
    logger.info("Info message - general information")
    logger.warning("Warning message - something unexpected")
    logger.error("Error message - operation failed")
    logger.critical("Critical message - severe error")

    # Test logging with exception
    try:
        result = 1 / 0
    except Exception as e:
        logger.error("Error during operation: %s", e, exc_info=True)




