# VLC: use the shipped firejail profile with NixOS fixups.
#
# private-bin is incompatible with NixOS (Nix store paths are not in
# the locations firejail searches) so it must be disabled.
ignore private-bin

# Portal access for desktop integration (dark/light theme).
dbus-user.talk org.freedesktop.portal.Desktop

# VLC opens media from any folder.  Whitelisting the home root prevents
# narrower upstream whitelist entries from hiding ordinary home
# subdirectories, and the host /tmp replaces the private one.  Later
# upstream blacklists of sensitive application state still apply, and
# the upstream /run whitelist already includes removable drives.
whitelist ${HOME}
ignore private-tmp

include vlc.profile
