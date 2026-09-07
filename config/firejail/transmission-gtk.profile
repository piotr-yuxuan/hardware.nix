# Transmission GTK: sandboxed with downloads restricted to ~/net/transmission.
#
# The upstream profile whitelists ${DOWNLOADS} (~/Downloads); override
# that to the dedicated torrent directory so Transmission cannot write
# anywhere else under ~.
#
# private-bin is incompatible with NixOS (Nix store paths are not in
# the locations firejail searches) so it must be disabled.
ignore private-bin

# private-etc on NixOS causes stale resolv.conf inside the sandbox
# when NetworkManager updates it after a network change.  Disabling
# it lets Transmission see the host /etc directly.
ignore private-etc

# Replace the default ${DOWNLOADS} whitelist with ~/net/transmission.
ignore whitelist ${DOWNLOADS}
whitelist ${HOME}/net/transmission

# Transmission on NixOS uses XDG paths for config and cache.
noblacklist ${HOME}/.config/transmission
noblacklist ${HOME}/.cache/transmission
whitelist ${HOME}/.config/transmission
whitelist ${HOME}/.cache/transmission

# The upstream profile sets dbus-user none; override it so desktop
# notifications and portal integration work.
ignore dbus-user none

# Portal access for desktop integration (dark/light theme).
# Desktop notifications for completed downloads.
dbus-user filter
dbus-user.own com.transmissionbt.Transmission.*
dbus-user.talk org.freedesktop.portal.Desktop
dbus-user.talk org.freedesktop.Notifications

include transmission-gtk.profile
