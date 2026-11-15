#!/usr/bin/env bash
# stat, id, notify-send and emacsclient come from PATH.

msg="SNAPSHOT FAILURE: btrbk-home.service failed. Run: journalctl -u btrbk-home.service"

# Write to all PTYs owned by example.
# wall(1) uses utmp to find targets, but GUI terminal emulators
# (GNOME Console, Emacs eat, VS Code) do not register utmp entries,
# so wall never reaches them.  Writing directly to each user-owned
# PTY bypasses that limitation.
# Note: mistty redraws its buffer and swallows injected PTY output,
# so it is covered by the emacsclient warning below instead.
for pts in /dev/pts/[0-9]*; do
	[ -c "$pts" ] || continue
	owner=$(stat -c %U "$pts" 2>/dev/null) || continue
	[ "$owner" = "example" ] || continue
	printf '\n\033[1;31m*** %s ***\033[0m\n' "$msg" >"$pts" 2>/dev/null || true
done

uid=$(id -u example)

# Emacs warning buffer (covers mistty and any Emacs frame).
/run/wrappers/bin/sudo -u example emacsclient -e \
	"(display-warning 'btrbk \"$msg\" :error)" \
	2>/dev/null || true

# Desktop notification via D-Bus.
if [ -d "/run/user/$uid" ]; then
	/run/wrappers/bin/sudo -u example \
		DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
		notify-send -u critical \
		"Snapshot FAILED" \
		"btrbk-home.service failed. Run: journalctl -u btrbk-home.service"
fi
