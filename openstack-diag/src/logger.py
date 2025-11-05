"""
Simple logging module for OpenStack Diagnostics
Basic logger without complex dependencies
"""

import logging
import sys
from typing import Optional


def get_logger(name: str, level: Optional[str] = None) -> logging.Logger:
    """
    Get simple logger with console output

    Args:
        name: Logger name (usually __name__)
        level: Log level (DEBUG, INFO, WARNING, ERROR)

    Returns:
        Configured logger instance
    """
    logger = logging.getLogger(name)

    # Avoid adding handlers multiple times
    if logger.handlers:
        return logger

    # Set log level
    log_level = getattr(logging, level) if level else logging.INFO
    logger.setLevel(log_level)

    # Create console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(log_level)

    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s | %(name)s | %(levelname)-8s | %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    console_handler.setFormatter(formatter)

    # Add handler to logger
    logger.addHandler(console_handler)
    logger.propagate = False

    return logger

