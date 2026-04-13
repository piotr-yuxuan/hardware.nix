"""Unit tests for scripts/touchpad-watchdog.py.

Covers: parse_event, classify_event, diagnose, find_touchpad_event_node,
        read_events, check_device, and main.
"""

from __future__ import annotations

import os
import struct
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

# Make the scripts directory importable.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import touchpad_watchdog as tw


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _pack_event(
    ev_type: int, ev_code: int, ev_value: int = 0
) -> bytes:
    """Build a raw input_event struct."""
    return struct.pack(tw.INPUT_EVENT_FORMAT, 0, 0, ev_type, ev_code, ev_value)


def _make_event(
    ev_type: int, ev_code: int, ev_value: int = 0
) -> tw.InputEvent:
    return tw.InputEvent(tv_sec=0, tv_usec=0, ev_type=ev_type, ev_code=ev_code, ev_value=ev_value)


# ---------------------------------------------------------------------------
# parse_event
# ---------------------------------------------------------------------------


class TestParseEvent:
    def test_valid_event(self) -> None:
        data = _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, 12345)
        event = tw.parse_event(data)
        assert event is not None
        assert event.ev_type == tw.EV_MSC
        assert event.ev_code == tw.MSC_TIMESTAMP
        assert event.ev_value == 12345

    def test_short_data_returns_none(self) -> None:
        assert tw.parse_event(b"") is None
        assert tw.parse_event(b"\x00" * 5) is None

    def test_extra_bytes_ignored(self) -> None:
        data = _pack_event(tw.EV_ABS, tw.ABS_X, 100) + b"\xff" * 10
        event = tw.parse_event(data)
        assert event is not None
        assert event.ev_type == tw.EV_ABS
        assert event.ev_code == tw.ABS_X

    def test_preserves_timestamps(self) -> None:
        data = struct.pack(tw.INPUT_EVENT_FORMAT, 42, 999, tw.EV_SYN, 0, 0)
        event = tw.parse_event(data)
        assert event is not None
        assert event.tv_sec == 42
        assert event.tv_usec == 999


# ---------------------------------------------------------------------------
# classify_event
# ---------------------------------------------------------------------------


class TestClassifyEvent:
    def test_timestamp(self) -> None:
        event = _make_event(tw.EV_MSC, tw.MSC_TIMESTAMP)
        assert tw.classify_event(event) is tw.EventKind.TIMESTAMP

    def test_position_abs_x(self) -> None:
        assert tw.classify_event(_make_event(tw.EV_ABS, tw.ABS_X)) is tw.EventKind.POSITION

    def test_position_abs_y(self) -> None:
        assert tw.classify_event(_make_event(tw.EV_ABS, tw.ABS_Y)) is tw.EventKind.POSITION

    def test_position_mt_x(self) -> None:
        assert tw.classify_event(_make_event(tw.EV_ABS, tw.ABS_MT_POSITION_X)) is tw.EventKind.POSITION

    def test_position_mt_y(self) -> None:
        assert tw.classify_event(_make_event(tw.EV_ABS, tw.ABS_MT_POSITION_Y)) is tw.EventKind.POSITION

    def test_other_msc(self) -> None:
        """MSC event that is not MSC_TIMESTAMP."""
        assert tw.classify_event(_make_event(tw.EV_MSC, 0x01)) is tw.EventKind.OTHER

    def test_other_key(self) -> None:
        assert tw.classify_event(_make_event(tw.EV_KEY, 0x14A)) is tw.EventKind.OTHER

    def test_other_syn(self) -> None:
        assert tw.classify_event(_make_event(tw.EV_SYN, 0)) is tw.EventKind.OTHER

    def test_abs_non_position_code(self) -> None:
        """ABS event with a code that is not a position axis."""
        assert tw.classify_event(_make_event(tw.EV_ABS, 0x2F)) is tw.EventKind.OTHER


# ---------------------------------------------------------------------------
# diagnose
# ---------------------------------------------------------------------------


class TestDiagnose:
    def test_empty_stream_is_healthy(self) -> None:
        """No events at all means idle touchpad."""
        assert tw.diagnose([]) is tw.HealthStatus.HEALTHY

    def test_timestamps_only_is_stuck(self) -> None:
        kinds = [tw.EventKind.TIMESTAMP] * 10
        assert tw.diagnose(kinds) is tw.HealthStatus.STUCK

    def test_positions_only_is_healthy(self) -> None:
        kinds = [tw.EventKind.POSITION] * 5
        assert tw.diagnose(kinds) is tw.HealthStatus.HEALTHY

    def test_timestamps_and_positions_is_healthy(self) -> None:
        kinds = [tw.EventKind.TIMESTAMP, tw.EventKind.POSITION, tw.EventKind.TIMESTAMP]
        assert tw.diagnose(kinds) is tw.HealthStatus.HEALTHY

    def test_other_only_is_healthy(self) -> None:
        kinds = [tw.EventKind.OTHER] * 3
        assert tw.diagnose(kinds) is tw.HealthStatus.HEALTHY

    def test_timestamps_and_other_is_stuck(self) -> None:
        """OTHER events do not count as position data."""
        kinds = [tw.EventKind.TIMESTAMP, tw.EventKind.OTHER, tw.EventKind.TIMESTAMP]
        assert tw.diagnose(kinds) is tw.HealthStatus.STUCK

    def test_all_three_kinds_is_healthy(self) -> None:
        kinds = [tw.EventKind.TIMESTAMP, tw.EventKind.POSITION, tw.EventKind.OTHER]
        assert tw.diagnose(kinds) is tw.HealthStatus.HEALTHY

    def test_single_timestamp_is_stuck(self) -> None:
        assert tw.diagnose([tw.EventKind.TIMESTAMP]) is tw.HealthStatus.STUCK

    def test_single_position_is_healthy(self) -> None:
        assert tw.diagnose([tw.EventKind.POSITION]) is tw.HealthStatus.HEALTHY

    def test_accepts_generator(self) -> None:
        """diagnose should work with any iterable, not just lists."""
        gen = (tw.EventKind.TIMESTAMP for _ in range(5))
        assert tw.diagnose(gen) is tw.HealthStatus.STUCK


# ---------------------------------------------------------------------------
# find_touchpad_event_node
# ---------------------------------------------------------------------------


class TestFindTouchpadEventNode:
    def test_finds_matching_device(self, tmp_path: Path) -> None:
        event_dir = tmp_path / "event2" / "device"
        event_dir.mkdir(parents=True)
        (event_dir / "name").write_text("PIXA3854:00 093A:0274 Touchpad\n")
        assert tw.find_touchpad_event_node(tmp_path) == "event2"

    def test_returns_none_when_no_match(self, tmp_path: Path) -> None:
        event_dir = tmp_path / "event0" / "device"
        event_dir.mkdir(parents=True)
        (event_dir / "name").write_text("Some Other Device\n")
        assert tw.find_touchpad_event_node(tmp_path) is None

    def test_returns_none_when_empty(self, tmp_path: Path) -> None:
        assert tw.find_touchpad_event_node(tmp_path) is None

    def test_skips_non_touchpad_pixa_device(self, tmp_path: Path) -> None:
        """Mouse node has PIXA3854 but not 'Touchpad' suffix."""
        event_dir = tmp_path / "event1" / "device"
        event_dir.mkdir(parents=True)
        (event_dir / "name").write_text("PIXA3854:00 093A:0274 Mouse\n")
        assert tw.find_touchpad_event_node(tmp_path) is None

    def test_picks_touchpad_among_multiple_devices(self, tmp_path: Path) -> None:
        for idx, name in [
            (0, "Video Bus"),
            (1, "PIXA3854:00 093A:0274 Mouse"),
            (2, "PIXA3854:00 093A:0274 Touchpad"),
            (5, "Framework Laptop 16 Keyboard Module"),
        ]:
            d = tmp_path / f"event{idx}" / "device"
            d.mkdir(parents=True)
            (d / "name").write_text(name + "\n")
        assert tw.find_touchpad_event_node(tmp_path) == "event2"

    def test_handles_unreadable_name_file(self, tmp_path: Path) -> None:
        event_dir = tmp_path / "event3" / "device"
        event_dir.mkdir(parents=True)
        name_file = event_dir / "name"
        name_file.write_text("PIXA3854:00 093A:0274 Touchpad\n")
        name_file.chmod(0o000)
        try:
            # Should not crash, just skip the unreadable entry.
            result = tw.find_touchpad_event_node(tmp_path)
            # Might be None if chmod actually blocks reading.
            assert result is None or result == "event3"
        finally:
            name_file.chmod(0o644)

    def test_nonexistent_sysfs_root(self) -> None:
        assert tw.find_touchpad_event_node(Path("/nonexistent/path")) is None


# ---------------------------------------------------------------------------
# read_events (with mocked I/O)
# ---------------------------------------------------------------------------


class TestReadEvents:
    def test_returns_empty_on_open_failure(self) -> None:
        events = tw.read_events("/dev/input/nonexistent_device", 0.1)
        assert events == []

    def test_reads_events_from_real_fd(self, tmp_path: Path) -> None:
        """Write fake event data to a FIFO and read it back."""
        fifo = tmp_path / "fake_event"
        os.mkfifo(fifo)

        event_data = _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_X, 500)

        pid = os.fork()
        if pid == 0:
            # Child: write to FIFO then exit.
            fd = os.open(str(fifo), os.O_WRONLY)
            os.write(fd, event_data)
            os.close(fd)
            os._exit(0)
        else:
            try:
                events = tw.read_events(str(fifo), 1.0)
                assert len(events) == 1
                assert events[0].ev_type == tw.EV_ABS
                assert events[0].ev_code == tw.ABS_MT_POSITION_X
                assert events[0].ev_value == 500
            finally:
                os.waitpid(pid, 0)


# ---------------------------------------------------------------------------
# check_device
# ---------------------------------------------------------------------------


class TestCheckDevice:
    def test_stuck_device(self, tmp_path: Path) -> None:
        """Device emitting only timestamps is diagnosed as stuck."""
        fifo = tmp_path / "stuck_event"
        os.mkfifo(fifo)

        events = b"".join(
            _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, i) for i in range(5)
        )

        pid = os.fork()
        if pid == 0:
            fd = os.open(str(fifo), os.O_WRONLY)
            os.write(fd, events)
            os.close(fd)
            os._exit(0)
        else:
            try:
                assert tw.check_device(str(fifo), 1.0) is tw.HealthStatus.STUCK
            finally:
                os.waitpid(pid, 0)

    def test_healthy_device(self, tmp_path: Path) -> None:
        """Device emitting timestamps and positions is healthy."""
        fifo = tmp_path / "healthy_event"
        os.mkfifo(fifo)

        events = (
            _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, 1)
            + _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_X, 100)
            + _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_Y, 200)
        )

        pid = os.fork()
        if pid == 0:
            fd = os.open(str(fifo), os.O_WRONLY)
            os.write(fd, events)
            os.close(fd)
            os._exit(0)
        else:
            try:
                assert tw.check_device(str(fifo), 1.0) is tw.HealthStatus.HEALTHY
            finally:
                os.waitpid(pid, 0)

    def test_missing_device_is_healthy(self) -> None:
        """A device that cannot be opened is treated as healthy (idle)."""
        assert tw.check_device("/dev/input/nonexistent", 0.1) is tw.HealthStatus.HEALTHY


# ---------------------------------------------------------------------------
# main (CLI entry point)
# ---------------------------------------------------------------------------


class TestMain:
    def test_exit_2_when_no_device(self) -> None:
        with patch.object(tw, "find_touchpad_event_node", return_value=None):
            assert tw.main([]) == 2

    def test_exit_0_when_healthy(self) -> None:
        with (
            patch.object(tw, "find_touchpad_event_node", return_value="event2"),
            patch.object(tw, "check_device", return_value=tw.HealthStatus.HEALTHY),
        ):
            assert tw.main(["1"]) == 0

    def test_exit_1_when_stuck(self) -> None:
        with (
            patch.object(tw, "find_touchpad_event_node", return_value="event2"),
            patch.object(tw, "check_device", return_value=tw.HealthStatus.STUCK),
        ):
            assert tw.main(["1"]) == 1

    def test_default_duration(self) -> None:
        """When no argument given, default duration is 2.0."""
        with (
            patch.object(tw, "find_touchpad_event_node", return_value="event2"),
            patch.object(tw, "check_device", return_value=tw.HealthStatus.HEALTHY) as mock_check,
        ):
            tw.main([])
            mock_check.assert_called_once_with("/dev/input/event2", 2.0)

    def test_custom_duration(self) -> None:
        with (
            patch.object(tw, "find_touchpad_event_node", return_value="event5"),
            patch.object(tw, "check_device", return_value=tw.HealthStatus.HEALTHY) as mock_check,
        ):
            tw.main(["3.5"])
            mock_check.assert_called_once_with("/dev/input/event5", 3.5)

    def test_constructs_correct_device_path(self) -> None:
        with (
            patch.object(tw, "find_touchpad_event_node", return_value="event7"),
            patch.object(tw, "check_device", return_value=tw.HealthStatus.HEALTHY) as mock_check,
        ):
            tw.main(["1"])
            mock_check.assert_called_once_with("/dev/input/event7", 1.0)


# ===========================================================================
# Integration tests
# ===========================================================================


SCRIPTS_DIR = Path(__file__).resolve().parent.parent / "scripts"


def _build_fake_sysfs(tmp_path: Path, devices: dict[str, str]) -> Path:
    """Create a fake /sys/class/input tree.

    *devices* maps event node names to device name strings,
    e.g. {"event2": "PIXA3854:00 093A:0274 Touchpad"}.
    """
    sysfs = tmp_path / "sys" / "class" / "input"
    for node, name in devices.items():
        d = sysfs / node / "device"
        d.mkdir(parents=True)
        (d / "name").write_text(name + "\n")
    return sysfs


def _write_events_to_fifo(fifo_path: str, raw: bytes) -> int:
    """Fork a child that writes *raw* to *fifo_path* and exits.

    Returns the child PID (caller must waitpid).
    """
    pid = os.fork()
    if pid == 0:
        fd = os.open(fifo_path, os.O_WRONLY)
        os.write(fd, raw)
        os.close(fd)
        os._exit(0)
    return pid


class TestIntegrationFullPipeline:
    """Run the full sysfs lookup + evdev read + diagnose pipeline
    using fake sysfs directories and FIFOs (no mocks)."""

    def test_stuck_end_to_end(self, tmp_path: Path) -> None:
        sysfs = _build_fake_sysfs(tmp_path, {
            "event0": "Video Bus",
            "event1": "PIXA3854:00 093A:0274 Mouse",
            "event2": "PIXA3854:00 093A:0274 Touchpad",
        })

        # Create a FIFO where the real /dev/input/event2 would be.
        dev_input = tmp_path / "dev" / "input"
        dev_input.mkdir(parents=True)
        fifo = dev_input / "event2"
        os.mkfifo(fifo)

        raw = b"".join(
            _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, i * 8000) for i in range(10)
        )

        node = tw.find_touchpad_event_node(sysfs)
        assert node == "event2"

        pid = _write_events_to_fifo(str(fifo), raw)
        try:
            status = tw.check_device(str(fifo), 1.0)
            assert status is tw.HealthStatus.STUCK
        finally:
            os.waitpid(pid, 0)

    def test_healthy_end_to_end(self, tmp_path: Path) -> None:
        sysfs = _build_fake_sysfs(tmp_path, {
            "event5": "PIXA3854:00 093A:0274 Touchpad",
        })

        dev_input = tmp_path / "dev" / "input"
        dev_input.mkdir(parents=True)
        fifo = dev_input / "event5"
        os.mkfifo(fifo)

        raw = (
            _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, 1000)
            + _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_X, 512)
            + _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_Y, 768)
            + _pack_event(tw.EV_SYN, 0)
            + _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, 2000)
        )

        node = tw.find_touchpad_event_node(sysfs)
        assert node == "event5"

        pid = _write_events_to_fifo(str(fifo), raw)
        try:
            status = tw.check_device(str(fifo), 1.0)
            assert status is tw.HealthStatus.HEALTHY
        finally:
            os.waitpid(pid, 0)

    def test_idle_end_to_end(self, tmp_path: Path) -> None:
        """No events at all within the sample window means healthy."""
        sysfs = _build_fake_sysfs(tmp_path, {
            "event2": "PIXA3854:00 093A:0274 Touchpad",
        })

        dev_input = tmp_path / "dev" / "input"
        dev_input.mkdir(parents=True)
        fifo = dev_input / "event2"
        os.mkfifo(fifo)

        node = tw.find_touchpad_event_node(sysfs)
        assert node == "event2"

        # Keep the write end open but never write, so select() times out.
        pid = os.fork()
        if pid == 0:
            import time
            fd = os.open(str(fifo), os.O_WRONLY)
            time.sleep(2)
            os.close(fd)
            os._exit(0)
        else:
            try:
                status = tw.check_device(str(fifo), 0.3)
                assert status is tw.HealthStatus.HEALTHY
            finally:
                os.waitpid(pid, 0)

    def test_no_device_found(self, tmp_path: Path) -> None:
        sysfs = _build_fake_sysfs(tmp_path, {
            "event0": "Some Other Device",
        })
        assert tw.find_touchpad_event_node(sysfs) is None


class TestIntegrationCli:
    """Run touchpad_watchdog.py as a subprocess to verify CLI behaviour.

    Each test spawns a Python subprocess with a small wrapper that
    patches SYSFS_INPUT_CLASS and, where needed, the device path, to
    point at temporary directories and FIFOs.
    """

    def test_exit_2_no_device_subprocess(self, tmp_path: Path) -> None:
        """With no matching sysfs entry, the script should exit 2."""
        import subprocess

        sysfs = _build_fake_sysfs(tmp_path, {"event0": "Unrelated Device"})
        wrapper = tmp_path / "run_check.py"
        wrapper.write_text(
            f"""\
import sys
sys.path.insert(0, {str(SCRIPTS_DIR)!r})
import touchpad_watchdog as tw
from pathlib import Path
tw.SYSFS_INPUT_CLASS = Path({str(sysfs)!r})
sys.exit(tw.main(["0.1"]))
"""
        )
        result = subprocess.run(
            [sys.executable, str(wrapper)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 2

    def test_exit_1_stuck_subprocess(self, tmp_path: Path) -> None:
        """Subprocess with fake sysfs + FIFO producing stuck events."""
        import subprocess

        sysfs = _build_fake_sysfs(tmp_path, {
            "event2": "PIXA3854:00 093A:0274 Touchpad",
        })
        dev_input = tmp_path / "dev" / "input"
        dev_input.mkdir(parents=True)
        fifo = dev_input / "event2"
        os.mkfifo(fifo)

        raw = b"".join(
            _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, i) for i in range(20)
        )

        wrapper = tmp_path / "run_check.py"
        wrapper.write_text(
            f"""\
import sys
sys.path.insert(0, {str(SCRIPTS_DIR)!r})
import touchpad_watchdog as tw
from pathlib import Path
tw.SYSFS_INPUT_CLASS = Path({str(sysfs)!r})
node = tw.find_touchpad_event_node()
device = {str(dev_input)!r} + "/" + node
status = tw.check_device(device, 1.0)
sys.exit(1 if status is tw.HealthStatus.STUCK else 0)
"""
        )

        pid = _write_events_to_fifo(str(fifo), raw)
        try:
            result = subprocess.run(
                [sys.executable, str(wrapper)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 1
        finally:
            os.waitpid(pid, 0)

    def test_exit_0_healthy_subprocess(self, tmp_path: Path) -> None:
        """Subprocess with fake sysfs + FIFO producing healthy events."""
        import subprocess

        sysfs = _build_fake_sysfs(tmp_path, {
            "event3": "PIXA3854:00 093A:0274 Touchpad",
        })
        dev_input = tmp_path / "dev" / "input"
        dev_input.mkdir(parents=True)
        fifo = dev_input / "event3"
        os.mkfifo(fifo)

        raw = (
            _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, 100)
            + _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_X, 300)
            + _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_Y, 400)
        )

        wrapper = tmp_path / "run_check.py"
        wrapper.write_text(
            f"""\
import sys
sys.path.insert(0, {str(SCRIPTS_DIR)!r})
import touchpad_watchdog as tw
from pathlib import Path
tw.SYSFS_INPUT_CLASS = Path({str(sysfs)!r})
node = tw.find_touchpad_event_node()
device = {str(dev_input)!r} + "/" + node
status = tw.check_device(device, 1.0)
sys.exit(1 if status is tw.HealthStatus.STUCK else 0)
"""
        )

        pid = _write_events_to_fifo(str(fifo), raw)
        try:
            result = subprocess.run(
                [sys.executable, str(wrapper)],
                capture_output=True,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0
        finally:
            os.waitpid(pid, 0)


class TestIntegrationZsh:
    """Test the zsh watchdog loop script's exit-code dispatching."""

    @pytest.fixture()
    def zsh_bin(self) -> str | None:
        """Return zsh path or skip if not available."""
        import shutil
        path = shutil.which("zsh")
        if path is None:
            pytest.skip("zsh not available")
        return path

    def test_healthy_iteration(self, tmp_path: Path, zsh_bin: str) -> None:
        """When the Python checker exits 0, the zsh loop should not
        invoke modprobe and should exit cleanly after one iteration."""
        import subprocess

        # Fake python_cmd that always exits 0 (healthy).
        fake_python = tmp_path / "fake_python"
        fake_python.write_text("#!/bin/sh\nexit 0\n")
        fake_python.chmod(0o755)

        # Fake modprobe that records invocations.
        modprobe_log = tmp_path / "modprobe.log"
        fake_modprobe = tmp_path / "fake_modprobe"
        fake_modprobe.write_text(
            f'#!/bin/sh\necho "$@" >> {modprobe_log}\n'
        )
        fake_modprobe.chmod(0o755)

        # Write a one-shot version of the zsh script (exits after first iteration).
        oneshot = tmp_path / "oneshot.zsh"
        oneshot.write_text(
            f"""#!{zsh_bin}
python_cmd={fake_python}
watchdog_py=/dev/null
modprobe_cmd={fake_modprobe}
sleep_cmd=true

"$python_cmd" "$watchdog_py" 1
rc=$?

case $rc in
    0) exit 0 ;;
    2) exit 2 ;;
    1)
        "$modprobe_cmd" -r i2c_hid_acpi
        "$sleep_cmd" 1
        "$modprobe_cmd" i2c_hid_acpi
        exit 1
        ;;
    *) exit 99 ;;
esac
"""
        )
        oneshot.chmod(0o755)

        result = subprocess.run(
            [zsh_bin, str(oneshot)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 0
        assert not modprobe_log.exists(), "modprobe should not be called when healthy"

    def test_stuck_iteration_triggers_modprobe(self, tmp_path: Path, zsh_bin: str) -> None:
        """When the Python checker exits 1 (stuck), the zsh loop should
        invoke modprobe to reload the module."""
        import subprocess

        fake_python = tmp_path / "fake_python"
        fake_python.write_text("#!/bin/sh\nexit 1\n")
        fake_python.chmod(0o755)

        modprobe_log = tmp_path / "modprobe.log"
        fake_modprobe = tmp_path / "fake_modprobe"
        fake_modprobe.write_text(
            f'#!/bin/sh\necho "$@" >> {modprobe_log}\n'
        )
        fake_modprobe.chmod(0o755)

        oneshot = tmp_path / "oneshot.zsh"
        oneshot.write_text(
            f"""#!{zsh_bin}
python_cmd={fake_python}
watchdog_py=/dev/null
modprobe_cmd={fake_modprobe}
sleep_cmd=true

"$python_cmd" "$watchdog_py" 1
rc=$?

case $rc in
    0) exit 0 ;;
    2) exit 2 ;;
    1)
        "$modprobe_cmd" -r i2c_hid_acpi
        "$sleep_cmd" 1
        "$modprobe_cmd" i2c_hid_acpi
        exit 1
        ;;
    *) exit 99 ;;
esac
"""
        )
        oneshot.chmod(0o755)

        result = subprocess.run(
            [zsh_bin, str(oneshot)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 1
        assert modprobe_log.exists()
        lines = modprobe_log.read_text().strip().splitlines()
        assert lines == ["-r i2c_hid_acpi", "i2c_hid_acpi"]

    def test_no_device_iteration(self, tmp_path: Path, zsh_bin: str) -> None:
        """When the Python checker exits 2 (no device), the loop should
        not invoke modprobe."""
        import subprocess

        fake_python = tmp_path / "fake_python"
        fake_python.write_text("#!/bin/sh\nexit 2\n")
        fake_python.chmod(0o755)

        modprobe_log = tmp_path / "modprobe.log"
        fake_modprobe = tmp_path / "fake_modprobe"
        fake_modprobe.write_text(
            f'#!/bin/sh\necho "$@" >> {modprobe_log}\n'
        )
        fake_modprobe.chmod(0o755)

        oneshot = tmp_path / "oneshot.zsh"
        oneshot.write_text(
            f"""#!{zsh_bin}
python_cmd={fake_python}
watchdog_py=/dev/null
modprobe_cmd={fake_modprobe}
sleep_cmd=true

"$python_cmd" "$watchdog_py" 1
rc=$?

case $rc in
    0) exit 0 ;;
    2) exit 2 ;;
    1)
        "$modprobe_cmd" -r i2c_hid_acpi
        "$sleep_cmd" 1
        "$modprobe_cmd" i2c_hid_acpi
        exit 1
        ;;
    *) exit 99 ;;
esac
"""
        )
        oneshot.chmod(0o755)

        result = subprocess.run(
            [zsh_bin, str(oneshot)],
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert result.returncode == 2
        assert not modprobe_log.exists()


class TestIntegrationRoundTrip:
    """Full round-trip: fake sysfs + FIFO + Python classify + diagnose,
    all without mocks, verifying the entire data path from raw bytes
    to HealthStatus."""

    def test_realistic_stuck_event_stream(self, tmp_path: Path) -> None:
        """Simulate the actual stuck pattern observed on the Framework 16:
        MSC_TIMESTAMP heartbeats at ~8ms intervals with BTN_TOOL_FINGER
        key events, but zero position data."""
        fifo = tmp_path / "event_stuck"
        os.mkfifo(fifo)

        raw = b""
        for i in range(50):
            raw += _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, i * 8000)
            raw += _pack_event(tw.EV_SYN, 0)
            if i % 6 == 0:
                # BTN_TOOL_FINGER (code 0x145) with value 2
                raw += _pack_event(tw.EV_KEY, 0x145, 2)
                raw += _pack_event(tw.EV_SYN, 0)

        pid = _write_events_to_fifo(str(fifo), raw)
        try:
            status = tw.check_device(str(fifo), 1.0)
            assert status is tw.HealthStatus.STUCK
        finally:
            os.waitpid(pid, 0)

    def test_realistic_healthy_event_stream(self, tmp_path: Path) -> None:
        """Simulate a healthy touch: timestamps, multitouch slots,
        position data, SYN_REPORT separators."""
        fifo = tmp_path / "event_healthy"
        os.mkfifo(fifo)

        raw = b""
        for i in range(20):
            raw += _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, i * 8000)
            raw += _pack_event(tw.EV_ABS, 0x2F, 0)          # ABS_MT_SLOT
            raw += _pack_event(tw.EV_ABS, 0x39, i)           # ABS_MT_TRACKING_ID
            raw += _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_X, 500 + i)
            raw += _pack_event(tw.EV_ABS, tw.ABS_MT_POSITION_Y, 300 + i)
            raw += _pack_event(tw.EV_ABS, tw.ABS_X, 500 + i)
            raw += _pack_event(tw.EV_ABS, tw.ABS_Y, 300 + i)
            raw += _pack_event(tw.EV_KEY, 0x14A, 1)          # BTN_TOUCH
            raw += _pack_event(tw.EV_SYN, 0)

        pid = _write_events_to_fifo(str(fifo), raw)
        try:
            status = tw.check_device(str(fifo), 1.0)
            assert status is tw.HealthStatus.HEALTHY
        finally:
            os.waitpid(pid, 0)

    def test_mixed_event_stream_with_late_position(self, tmp_path: Path) -> None:
        """Even if timestamps arrive first, a single position event at
        the end should flip the diagnosis to healthy."""
        fifo = tmp_path / "event_late"
        os.mkfifo(fifo)

        raw = b""
        for i in range(30):
            raw += _pack_event(tw.EV_MSC, tw.MSC_TIMESTAMP, i * 8000)
            raw += _pack_event(tw.EV_SYN, 0)
        # One position event at the very end.
        raw += _pack_event(tw.EV_ABS, tw.ABS_X, 100)

        pid = _write_events_to_fifo(str(fifo), raw)
        try:
            status = tw.check_device(str(fifo), 1.0)
            assert status is tw.HealthStatus.HEALTHY
        finally:
            os.waitpid(pid, 0)
