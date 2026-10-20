# WirePlumber's own linking/mpris-pause.lua, taken from the installed
# WirePlumber and patched to pause sandboxed players too.  Placed in
# services.pipewire.wireplumber.configPackages, it comes before the
# WirePlumber package on XDG_DATA_DIRS and so replaces the original.
#
# The patch applies without fuzz: when upstream changes the lines it
# touches, the build fails instead of shipping a stale copy.
{
  runCommand,
  wireplumber,
}:
runCommand "wireplumber-mpris-pause" {} "install -Dm644 ${wireplumber}/share/wireplumber/scripts/linking/mpris-pause.lua $out/share/wireplumber/scripts/linking/mpris-pause.lua && patch --forward --fuzz=0 --no-backup-if-mismatch $out/share/wireplumber/scripts/linking/mpris-pause.lua ${./wireplumber-mpris-pause.patch}"
