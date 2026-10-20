# mpv: use the shipped firejail profile with NixOS fixups.
#
# private-bin is incompatible with NixOS (Nix store paths are not in
# the locations firejail searches) so it must be disabled.
ignore private-bin

# The MPRIS script publishes media controls, so WirePlumber can pause
# mpv when its output goes away. The shipped profile turns the session
# bus off, which cannot be relaxed to a filter once read, so it is
# ignored before the include. The script owns its name with an
# instance suffix, and the filter allows no other name.
ignore dbus-user none
dbus-user filter
dbus-user.own org.mpris.MediaPlayer2.mpv
dbus-user.own org.mpris.MediaPlayer2.mpv.*

include mpv.profile
