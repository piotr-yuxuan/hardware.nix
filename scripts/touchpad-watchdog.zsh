# Variables python_cmd, modprobe_cmd, and sleep_cmd are set by the
# Nix wrapper.  watchdog_py holds the store path to
# touchpad-watchdog.py.

# Watchdog loop for the PixArt I2C HID touchpad on the Framework 16
# AMD 7040.
#
# The health check (stuck vs. healthy) is handled entirely by the
# Python script.  This loop is responsible only for:
#   1. Calling the health checker on a regular interval.
#   2. Reloading i2c_hid_acpi when the checker reports a stuck state.
#   3. Logging status transitions.

POLL=5
SAMPLE_WINDOW=2
COOLDOWN=15

echo "Touchpad watchdog started"

while true; do
    "$python_cmd" "$watchdog_py" "$SAMPLE_WINDOW"
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
            "$modprobe_cmd" -r i2c_hid_acpi 2>/dev/null || true
            "$sleep_cmd" 1
            "$modprobe_cmd" i2c_hid_acpi 2>/dev/null || true
            echo "Module reloaded, cooling down ${COOLDOWN}s"
            "$sleep_cmd" "$COOLDOWN"
            ;;
        *)
            echo "Health check exited with unexpected code $rc"
            ;;
    esac

    "$sleep_cmd" "$POLL"
done
