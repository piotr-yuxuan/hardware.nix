"""Shared pytest fixtures for the test suite.

All test files should import fixtures from here rather than duplicating
setup logic.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Callable

import pytest


@pytest.fixture(scope="session")
def scripts_dir() -> Path:
    """Return the absolute path to the scripts/ directory.

    Computed relative to this conftest file so test files do not need to
    re-derive the path themselves.
    """
    return Path(__file__).resolve().parent.parent / "scripts"


@pytest.fixture()
def fake_sysfs(tmp_path: Path) -> Callable[[dict[str, str]], Path]:
    """Build a temporary /sys/class/input-like directory tree.

    Returns a callable that accepts a dict mapping event-node names to
    device name strings and returns the sysfs root path.

    Example::

        sysfs = fake_sysfs({"event2": "PIXA3854:00 093A:0274 Touchpad"})
    """

    def _build(devices: dict[str, str]) -> Path:
        sysfs = tmp_path / "sys" / "class" / "input"
        for node, name in devices.items():
            d = sysfs / node / "device"
            d.mkdir(parents=True)
            (d / "name").write_text(name + "\n")
        return sysfs

    return _build


@pytest.fixture()
def fifo_factory(tmp_path: Path) -> Callable[[str], Path]:
    """Create named FIFOs inside a tmp_path subdirectory.

    Returns a callable ``make_fifo(name) -> Path`` that creates a FIFO
    at ``tmp_path/fifos/<name>`` and returns its path.
    """
    fifo_dir = tmp_path / "fifos"
    fifo_dir.mkdir()

    def make_fifo(name: str) -> Path:
        """Create a named FIFO and return its Path."""
        path = fifo_dir / name
        os.mkfifo(path)
        return path

    return make_fifo


@pytest.fixture()
def write_to_fifo() -> Callable[[Path, bytes], int]:
    """Return a callable that forks a child to write bytes to a FIFO.

    Usage::

        pid = write_to_fifo(fifo_path, b"raw bytes")
        # ... read from the FIFO ...
        os.waitpid(pid, 0)

    The caller is responsible for calling ``os.waitpid`` on the returned PID.
    """

    def write(path: Path, raw_bytes: bytes) -> int:
        """Fork a child that writes raw_bytes to path, then exits.

        Returns the child PID.
        """
        pid = os.fork()
        if pid == 0:
            fd = os.open(str(path), os.O_WRONLY)
            os.write(fd, raw_bytes)
            os.close(fd)
            os._exit(0)
        return pid

    return write
