"""
Consistent logging utilities for opencode skills.
"""

import sys
from datetime import datetime
from typing import Optional
from enum import Enum


class LogLevel(Enum):
    """Log levels."""
    DEBUG = 0
    INFO = 1
    SUCCESS = 2
    WARNING = 3
    ERROR = 4


class SkillLogger:
    """Logger for opencode skills with consistent formatting."""
    
    # Emoji icons for different log levels
    ICONS = {
        LogLevel.DEBUG: '🔍',
        LogLevel.INFO: 'ℹ️ ',
        LogLevel.SUCCESS: '✅',
        LogLevel.WARNING: '⚠️ ',
        LogLevel.ERROR: '❌'
    }
    
    def __init__(self, skill_name: str, verbose: bool = True, use_colors: bool = True):
        self.skill_name = skill_name
        self.verbose = verbose
        self.use_colors = use_colors
        self.log_history = []
    
    def _format_message(self, level: LogLevel, message: str) -> str:
        """Format log message with timestamp and skill name."""
        timestamp = datetime.now().strftime('%H:%M:%S')
        icon = self.ICONS.get(level, '•')
        
        if self.use_colors and sys.stdout.isatty():
            # ANSI color codes
            colors = {
                LogLevel.DEBUG: '\033[36m',    # Cyan
                LogLevel.INFO: '\033[34m',     # Blue
                LogLevel.SUCCESS: '\033[32m',  # Green
                LogLevel.WARNING: '\033[33m',  # Yellow
                LogLevel.ERROR: '\033[31m'     # Red
            }
            reset = '\033[0m'
            color = colors.get(level, '')
            return f"{icon} [{timestamp}] [{self.skill_name}] {color}{message}{reset}"
        else:
            return f"{icon} [{timestamp}] [{self.skill_name}] {message}"
    
    def _log(self, level: LogLevel, message: str, **kwargs):
        """Internal log method."""
        formatted = self._format_message(level, message)
        
        # Store in history
        self.log_history.append({
            'timestamp': datetime.now().isoformat(),
            'level': level.name,
            'message': message,
            'skill': self.skill_name
        })
        
        # Print if verbose or error
        if self.verbose or level in [LogLevel.ERROR, LogLevel.WARNING]:
            print(formatted, **kwargs)
    
    def debug(self, message: str):
        """Log debug message."""
        self._log(LogLevel.DEBUG, message)
    
    def info(self, message: str):
        """Log info message."""
        self._log(LogLevel.INFO, message)
    
    def success(self, message: str):
        """Log success message."""
        self._log(LogLevel.SUCCESS, message)
    
    def warning(self, message: str):
        """Log warning message."""
        self._log(LogLevel.WARNING, message)
    
    def error(self, message: str):
        """Log error message."""
        self._log(LogLevel.ERROR, message)
    
    def section(self, title: str):
        """Print section header."""
        separator = '=' * 60
        self.info(separator)
        self.info(title)
        self.info(separator)
    
    def progress(self, current: int, total: int, message: str = ""):
        """Show progress bar."""
        if not self.verbose:
            return
        
        percentage = (current / total) * 100
        bar_length = 30
        filled = int(bar_length * current / total)
        bar = '█' * filled + '░' * (bar_length - filled)
        
        status = f"\r{self.ICONS[LogLevel.INFO]} [{self.skill_name}] [{bar}] {percentage:.1f}% {message}"
        
        if current >= total:
            status += '\n'
        
        print(status, end='', flush=True)
    
    def get_history(self) -> list:
        """Get log history."""
        return self.log_history.copy()
    
    def save_history(self, filepath: str):
        """Save log history to file."""
        import json
        with open(filepath, 'w') as f:
            json.dump(self.log_history, f, indent=2)


class StatusReporter:
    """High-level status reporter for multi-step operations."""
    
    def __init__(self, logger: SkillLogger):
        self.logger = logger
        self.steps = []
        self.current_step = 0
    
    def add_step(self, name: str, description: str = ""):
        """Add a step to the workflow."""
        self.steps.append({
            'name': name,
            'description': description,
            'status': 'pending',
            'start_time': None,
            'end_time': None,
            'error': None
        })
    
    def start_step(self, step_name: str):
        """Start a step."""
        for i, step in enumerate(self.steps):
            if step['name'] == step_name:
                self.current_step = i
                step['status'] = 'in_progress'
                step['start_time'] = datetime.now()
                self.logger.info(f"Starting: {step_name}")
                if step['description']:
                    self.logger.info(f"  {step['description']}")
                break
    
    def complete_step(self, step_name: str, success: bool = True, message: str = ""):
        """Complete a step."""
        for step in self.steps:
            if step['name'] == step_name:
                step['status'] = 'completed' if success else 'failed'
                step['end_time'] = datetime.now()
                
                if success:
                    self.logger.success(f"Completed: {step_name}")
                    if message:
                        self.logger.info(f"  {message}")
                else:
                    self.logger.error(f"Failed: {step_name}")
                    if message:
                        self.logger.error(f"  {message}")
                        step['error'] = message
                break
    
    def get_summary(self) -> str:
        """Get workflow summary."""
        total = len(self.steps)
        completed = sum(1 for s in self.steps if s['status'] == 'completed')
        failed = sum(1 for s in self.steps if s['status'] == 'failed')
        
        lines = [
            "",
            "=" * 60,
            "WORKFLOW SUMMARY",
            "=" * 60,
            f"Total steps: {total}",
            f"Completed: {completed} ✅",
            f"Failed: {failed} ❌",
            f"Success rate: {(completed/total)*100:.1f}%" if total > 0 else "N/A",
            "=" * 60
        ]
        
        return '\n'.join(lines)
    
    def print_summary(self):
        """Print workflow summary."""
        print(self.get_summary())


def create_logger(skill_name: str, verbose: bool = True) -> SkillLogger:
    """Factory function to create a logger."""
    return SkillLogger(skill_name, verbose=verbose)
