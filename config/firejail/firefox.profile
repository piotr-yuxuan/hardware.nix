# Firefox Developer Edition: sandboxed with ~/Downloads access.
#
# private-bin is incompatible with NixOS (Nix store paths are not in
# the locations firejail searches) so it must be disabled.
ignore private-bin

# private-etc mounts a tmpfs over /etc that is populated with copies of
# the host files at sandbox startup.  When NetworkManager updates
# /etc/resolv.conf on a WiFi network change, the copy inside the sandbox
# becomes stale and Firefox loses DNS resolution while all other
# applications (which read the live file) continue to work.  Disabling
# private-etc lets Firefox see the host /etc directly so resolv.conf
# updates are always visible.
ignore private-etc

ignore whitelist ${DOWNLOADS}
whitelist ${HOME}/Downloads

# NixOS Firefox uses XDG paths (~/.config/mozilla, ~/.cache/mozilla)
# rather than ~/.mozilla.  Whitelist them so profiles, logins, and
# cache persist across sessions.
noblacklist ${HOME}/.config/mozilla
noblacklist ${HOME}/.cache/mozilla
whitelist ${HOME}/.config/mozilla
whitelist ${HOME}/.cache/mozilla

# Portal access for desktop integration under Wayland.  The upstream
# profile only allows org.freedesktop.portal.Documents.  Without this
# Firefox cannot read the system color-scheme (dark/light) from
# org.freedesktop.portal.Settings and screen sharing is broken.
dbus-user.talk org.freedesktop.portal.Desktop

include firefox-developer-edition.profile
