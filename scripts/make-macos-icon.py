"""Compatibility entry point for the macos icon generator."""
import runpy
from pathlib import Path

runpy.run_path(str(Path(__file__).with_name('make-app-icons.py')))['generate']('macos')
