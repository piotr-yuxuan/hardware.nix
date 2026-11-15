#!/usr/bin/env bash
# Watchdog loop for the PixArt I2C HID touchpad on the Framework 16
# AMD 7040.
#
# Usage: touchpad-watchdog.sh CHECKER, where CHECKER is the path of
# touchpad_watchdog.py. python3, modprobe and sleep come from PATH.
#
# The health check (stuck vs. healthy) is handled entirely by the
# Python script.  This loop is responsible only for:
#   1. Calling the health checker on a regular interval.
#   2. Reloading i2c_hid_acpi when the checker reports a stuck state.
#   3. Logging status transitions.

watchdog_py=$1
POLL=5
SAMPLE_WINDOW=2
COOLDOWN=15

echo "Touchpad watchdog started"

while true; do
    python3 "$watchdog_py" "$SAMPLE_WINDOW"
    rc=$?

    case $rc in
        0)
            # Healthy or idle: nothing to do.
            ;;
        2)
            echo "Touchpad evdev node not found, retrying in ${POLL}s"
            ;;
        1)
            echo "Touchpad stuck, reloading i2c_hid_acpi"
            modprobe -r i2c_hid_acpi 2>/dev/null || true
            sleep 1
            modprobe i2c_hid_acpi 2>/dev/null || true
            echo "Module reloaded, cooling down ${COOLDOWN}s"
            sleep "$COOLDOWN"
            ;;
        *)
            echo "Health check exited with unexpected code $rc"
            ;;
    esac

    sleep "$POLL"
done
