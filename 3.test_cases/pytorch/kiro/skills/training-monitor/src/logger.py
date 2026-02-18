"""
Simple logging utility for training monitor
"""

import sys
from datetime import datetime
from typing import Optional


class Logger:
    """Simple colored logger for training monitor"""
    
    COLORS = {
        "DEBUG": "\033[36m",    # Cyan
        "INFO": "\033[92m",     # Green
        "WARN": "\033[93m",     # Yellow
        "ERROR": "\033[91m",    # Red
        "RESET": "\033[0m",
    }
    
    def __init__(self, name: str = "training-monitor", level: str = "INFO"):
        self.name = name
        self.level = level
        self.levels = {"DEBUG": 0, "INFO": 1, "WARN": 2, "ERROR": 3}
        
    def _should_log(self, level: str) -> bool:
        return self.levels.get(level, 1) >= self.levels.get(self.level, 1)
        
    def log(self, message: str, level: str = "INFO"):
        """Log a message with timestamp and color"""
        if not self._should_log(level):
            return
            
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        color = self.COLORS.get(level, self.COLORS["INFO"])
        reset = self.COLORS["RESET"]
        
        output = f"{color}[{level}]{reset} {timestamp} - {message}"
        
        if level == "ERROR":
            sys.stderr.write(output + "\n")
        else:
            sys.stdout.write(output + "\n")
            
    def debug(self, message: str):
        self.log(message, "DEBUG")
        
    def info(self, message: str):
        self.log(message, "INFO")
        
    def warn(self, message: str):
        self.log(message, "WARN")
        
    def error(self, message: str):
        self.log(message, "ERROR")


# Global logger instance
_default_logger: Optional[Logger] = None


def get_logger(name: str = "training-monitor", level: str = "INFO") -> Logger:
    """Get or create a logger instance"""
    global _default_logger
    if _default_logger is None:
        _default_logger = Logger(name, level)
    return _default_logger
