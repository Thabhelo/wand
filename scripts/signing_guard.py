"""Refuse routine updates that would change macOS's trusted app identity."""
from pathlib import Path
import subprocess


def requirement(app: Path) -> str:
    subprocess.run(['codesign', '--verify', '--strict', str(app)], check=True, capture_output=True)
    result = subprocess.run(['codesign', '-d', '-r-', str(app)], check=True, capture_output=True, text=True)
    for line in (result.stdout + result.stderr).splitlines():
        if line.startswith('designated => '):
            return line.removeprefix('designated => ')
    raise ValueError('No designated signing requirement found')


def verify_update(previous: Path, candidate: Path) -> None:
    if requirement(previous) != requirement(candidate):
        raise ValueError('Update changes the trusted signing identity. Existing permissions may not carry over; stop and plan an explicit identity migration.')
