"""Touchpad health checker for the PixArt PIXA3854 I2C HID touchpad.

The PIXA3854 touchpad on the Framework 16 AMD 7040 sometimes enters a
stuck state where the firmware sends only MSC_TIMESTAMP heartbeat
events (type=4, code=5) with no ABS_MT_POSITION_X/Y data.

This module provides pure functions to:
  1. Find the touchpad evdev node via sysfs.
  2. Classify raw evdev events as timestamps or positions.
  3. Diagnose touchpad health from a stream of classified events.
  4. Read raw events from a device node within a time budget.

Exit codes (when run as __main__):
  0  healthy (idle or producing position data)
  1  stuck (timestamps flowing, no position data)
  2  device not found
"""

from __future__ import annotations

import os
import select
import struct
import sys
import time
from enum import Enum, auto
from pathlib import Path
from typing import BinaryIO, Iterable, NamedTuple


# -- evdev constants ----------------------------------------------------------

EV_SYN = 0x00
EV_KEY = 0x01
EV_ABS = 0x03
EV_MSC = 0x04

MSC_TIMESTAMP = 0x05

ABS_X = 0x00
ABS_Y = 0x01
ABS_MT_POSITION_X = 0x35
ABS_MT_POSITION_Y = 0x36

POSITION_CODES = frozenset({ABS_X, ABS_Y, ABS_MT_POSITION_X, ABS_MT_POSITION_Y})

INPUT_EVENT_SIZE = struct.calcsize("llHHi")
INPUT_EVENT_FORMAT = "llHHi"

SYSFS_INPUT_CLASS = Path("/sys/class/input")
TOUCHPAD_NAME_PATTERN = "PIXA3854"
TOUCHPAD_SUFFIX = "Touchpad"


# -- data types ---------------------------------------------------------------


class EventKind(Enum):
    """Classification of a raw evdev event."""

    TIMESTAMP = auto()
    POSITION = auto()
    OTHER = auto()


class HealthStatus(Enum):
    """Result of a touchpad health check."""

    HEALTHY = auto()
    STUCK = auto()


class InputEvent(NamedTuple):
    """A parsed Linux input_event."""

    tv_sec: int
    tv_usec: int
    ev_type: int
    ev_code: int
    ev_value: int


# -- pure functions -----------------------------------------------------------


def parse_event(data: bytes) -> InputEvent | None:
    """Parse raw bytes into an InputEvent, or None if data is too short."""
    if len(data) < INPUT_EVENT_SIZE:
        return None
    fields = struct.unpack(INPUT_EVENT_FORMAT, data[:INPUT_EVENT_SIZE])
    return InputEvent(*fields)


def classify_event(event: InputEvent) -> EventKind:
    """Classify a parsed evdev event."""
    if event.ev_type == EV_MSC and event.ev_code == MSC_TIMESTAMP:
        return EventKind.TIMESTAMP
    if event.ev_type == EV_ABS and event.ev_code in POSITION_CODES:
        return EventKind.POSITION
    return EventKind.OTHER


def diagnose(kinds: Iterable[EventKind]) -> HealthStatus:
    """Determine touchpad health from a sequence of classified events.

    Stuck: at least one TIMESTAMP seen, zero POSITION seen.
    Healthy: either no events at all (idle) or at least one POSITION.
    """
    has_timestamp = False
    has_position = False
    for kind in kinds:
        if kind is EventKind.TIMESTAMP:
            has_timestamp = True
        elif kind is EventKind.POSITION:
            has_position = True
    if has_timestamp and not has_position:
        return HealthStatus.STUCK
    return HealthStatus.HEALTHY


def find_touchpad_event_node(
    sysfs_root: Path | None = None,
) -> str | None:
    """Return the evdev node name (e.g. 'event2') for the PixArt touchpad.

    Scans sysfs for an input device whose name contains both
    TOUCHPAD_NAME_PATTERN and TOUCHPAD_SUFFIX.  Returns None when no
    matching device exists.
    """
    root = sysfs_root if sysfs_root is not None else SYSFS_INPUT_CLASS
    try:
        candidates = sorted(root.glob("event*/device/name"))
    except OSError:
        return None
    for name_path in candidates:
        try:
            name = name_path.read_text().strip()
        except OSError:
            continue
        if TOUCHPAD_NAME_PATTERN in name and TOUCHPAD_SUFFIX in name:
            # name_path is e.g. /sys/class/input/event2/device/name
            return name_path.parent.parent.name
    return None


# -- I/O layer (side-effectful, kept thin for testability) --------------------


def read_events(
    device_path: str,
    duration: float,
    clock: type = time,
) -> list[InputEvent]:
    """Read raw evdev events from a device node for up to *duration* seconds.

    Returns the list of parsed events.  An empty list means the device
    was idle (no finger on the touchpad).
    """
    events: list[InputEvent] = []
    try:
        fd = os.open(device_path, os.O_RDONLY | os.O_NONBLOCK)
    except OSError:
        return events
    try:
        deadline = clock.monotonic() + duration
        while True:
            remaining = deadline - clock.monotonic()
            if remaining <= 0:
                break
            ready, _, _ = select.select([fd], [], [], min(remaining, 0.1))
            if ready:
                try:
                    data = os.read(fd, INPUT_EVENT_SIZE)
                except OSError:
                    break
                event = parse_event(data)
                if event is not None:
                    events.append(event)
    finally:
        os.close(fd)
    return events


def check_device(device_path: str, duration: float) -> HealthStatus:
    """End-to-end health check: read events, classify, diagnose."""
    events = read_events(device_path, duration)
    kinds = (classify_event(e) for e in events)
    return diagnose(kinds)


# -- CLI entry point ----------------------------------------------------------


def main(args: list[str] | None = None) -> int:
    """Run a single health check and exit.

    Usage: touchpad-watchdog.py [SAMPLE_SECONDS]

    Exit codes: 0 = healthy, 1 = stuck, 2 = device not found.
    """
    argv = args if args is not None else sys.argv[1:]
    duration = float(argv[0]) if argv else 2.0

    node = find_touchpad_event_node()
    if node is None:
        print("touchpad evdev node not found", file=sys.stderr)
        return 2

    device_path = f"/dev/input/{node}"
    status = check_device(device_path, duration)

    if status is HealthStatus.STUCK:
        print(f"stuck on {node}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
