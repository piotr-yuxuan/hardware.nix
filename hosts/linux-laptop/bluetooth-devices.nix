# Declarative Bluetooth device whitelist for host linux-laptop.
#
# NixOS does not natively support declarative Bluetooth pairing.
# This module uses a system activation script that manages the BlueZ
# state directory (/var/lib/bluetooth/) directly:
#
#   * Whitelisted devices get a stub info file (trusted, with DeviceID)
#     if they have not been paired yet.
#   * Already paired devices keep their link keys; Trusted, Name, and
#     Alias are updated.
#   * Every device directory not in the whitelist is removed, so
#     unknown peripherals are forgotten on each nixos-rebuild switch.
#
# Trade-off: link keys cannot be generated declaratively.  Each device
# still requires one manual pairing via GNOME Settings or bluetoothctl.
# After that first pairing the keys are preserved across rebuilds as
# long as the device stays in the whitelist below.
{
  pkgs,
  lib,
  ...
}: let
  # Opt in only after setting your adapter address and complete device list.
  # Enabling this registry removes paired devices absent from the whitelist.
  adapterAddress = null;
  btDir = if adapterAddress == null then "" else "/var/lib/bluetooth/${adapterAddress}";
  devices = {};

  # Tab-separated device registry consumed by the shell script.
  # Format: MAC<TAB>NAME<TAB>SOURCE<TAB>VENDOR<TAB>PRODUCT
  deviceEntries = lib.concatStringsSep "\\n" (lib.mapAttrsToList
    (mac: dev: "${mac}\t${dev.name}\t${toString dev.source}\t${toString dev.vendor}\t${toString dev.product}")
    devices);

  # Nix-generated header: injects store paths and device data into
  # shell variables before the script body runs.
  header = ''
    sed=${pkgs.gnused}/bin/sed
    basename_cmd=${pkgs.coreutils}/bin/basename
    bt_dir=${btDir}
    whitelist="${lib.concatStringsSep " " (builtins.attrNames devices)}"
    device_entries="$(printf '%b' '${deviceEntries}')"
  '';
in {
  hardware.bluetooth.enable = true;

  system.activationScripts.bluetoothDeviceWhitelist = lib.mkIf (adapterAddress != null) (lib.stringAfter ["etc"] ''
    ${header}
    ${builtins.readFile ./bluetooth-devices-sync.sh}
  '');
}
