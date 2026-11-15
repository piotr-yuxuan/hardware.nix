#!/usr/bin/env bash
# Bluetooth device whitelist synchronisation.
#
# Usage: bluetooth-devices-sync.sh BT_DIR ENTRY...
#
#   BT_DIR  BlueZ adapter directory (/var/lib/bluetooth/<adapter>)
#   ENTRY   one device to keep: MAC<TAB>NAME<TAB>SOURCE<TAB>VENDOR<TAB>PRODUCT
#
# GNU sed comes from PATH. The NixOS activation runs this script as its
# own process, so an exit here ends this script only.

bt_dir=$1
shift

# Defensive guard: abort if bt_dir does not look like a BlueZ adapter path.
case "$bt_dir" in
  /var/lib/bluetooth/??:??:??:??:??:??) ;;
  *) echo "bluetooth-whitelist: bt_dir looks wrong ($bt_dir), aborting" >&2
     exit 1 ;;
esac

# Write a stub info file for a device that has never been paired.
write_stub_info() {
  local info="$1" name="$2" source="$3" vendor="$4" product="$5"
  cat > "$info" <<EOF
[General]
Name=$name
Alias=$name
Trusted=true
Blocked=false

[DeviceID]
Source=$source
Vendor=$vendor
Product=$product
EOF
  chmod 600 "$info"
}

ensure_device() {
  local mac="$1" name="$2" source="$3" vendor="$4" product="$5"
  local dev_dir="$bt_dir/$mac"
  local info="$dev_dir/info"
  mkdir -p "$dev_dir"

  if [ -f "$info" ]; then
    # Already paired: preserve link keys, update Trusted, Alias, and Name.
    if grep -q '^Trusted=' "$info"; then
      sed -i 's/^Trusted=.*/Trusted=true/' "$info"
    else
      sed -i '/^\[General\]/a Trusted=true' "$info"
    fi
    if grep -q '^Alias=' "$info"; then
      sed -i "s|^Alias=.*|Alias=$name|" "$info"
    else
      sed -i "/^\[General\]/a Alias=$name" "$info"
    fi
    if grep -q '^Name=' "$info"; then
      sed -i "s|^Name=.*|Name=$name|" "$info"
    else
      sed -i "/^\[General\]/a Name=$name" "$info"
    fi
  else
    # Not yet paired: write a stub so the device shows as known.
    write_stub_info "$info" "$name" "$source" "$vendor" "$product"
  fi

  chmod 600 "$info"
  chmod 700 "$dev_dir"
}

if [ ! -d "$bt_dir" ]; then
  echo "bluetooth-whitelist: adapter directory $bt_dir missing, skipping"
  exit 0
fi

# Any command that fails from here on makes the exit status non-zero,
# after the remaining devices are handled.
rc=0
set -o errtrace
trap 'rc=1' ERR

echo "bluetooth-whitelist: managing paired devices"

# Remove devices not in the whitelist.
for dir in "$bt_dir"/??:??:??:??:??:??; do
  [ -d "$dir" ] || continue
  mac="$(basename "$dir")"
  keep=false
  for entry in "$@"; do
    if [ "$mac" = "${entry%%$'\t'*}" ]; then
      keep=true
      break
    fi
  done
  if ! $keep; then
    echo "bluetooth-whitelist: forgetting unknown device $mac"
    rm -rf "$dir"
  fi
done

# Ensure each whitelisted device entry exists.
for entry in "$@"; do
  IFS=$'\t' read -r mac name source vendor product <<<"$entry"
  echo -e "bluetooth-whitelist: ensuring $name\t($mac)"
  ensure_device "$mac" "$name" "$source" "$vendor" "$product"
done

echo "bluetooth-whitelist: done"
exit "$rc"
