"""Simple logging utility for PyTorchJob Manager."""

import logging
import sys


def get_logger(name: str = "pytorchjob_manager") -> logging.Logger:
    """Get a configured logger instance."""
    logger = logging.getLogger(name)
    
    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter(
            "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S"
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
    
    return logger
