#!/usr/bin/env bats
# Tests for hosts/nixOS/bluetooth-devices-sync.sh
#
# The script manages the BlueZ state directory during NixOS activation:
# creates stub info files for new devices, updates existing paired
# devices, and removes unknown device directories.
#
# The script validates that bt_dir matches /var/lib/bluetooth/XX:XX:…
# which cannot be satisfied in an unprivileged test.  Tests that exercise
# the main logic run a patched copy with the guard removed; the guard
# itself is tested separately against the original script.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/hosts/nixOS/bluetooth-devices-sync.sh"

load '../helpers/isolation'

setup() {
	isolation_setup

	adapter="AA:BB:CC:DD:EE:00"
	export bt_dir="$tmpdir/var/lib/bluetooth/$adapter"
	mkdir -p "$bt_dir"

	entries=(
		"$(printf 'AA:BB:CC:DD:EE:01\tSpeaker\t1\t148\t4')"
		"$(printf 'AA:BB:CC:DD:EE:02\tKeyboard\t1\t76\t615')"
	)

	# Patched script: remove the case guard so we can use a tmpdir path
	patched="$tmpdir/sync-patched.sh"
	sed '/^case "\$bt_dir" in$/,/^esac$/d' "$SCRIPT" >"$patched"
}

teardown() {
	isolation_teardown
}

run_sync() {
	local script="${1:-$patched}"
	run "$BASH" "$script" "$bt_dir" "${entries[@]}"
}

# ---------------------------------------------------------------------------
# Stub creation for new devices
# ---------------------------------------------------------------------------

@test "new device: stub info file is created with General and DeviceID sections" {
	run_sync "$patched"
	[[ $status -eq 0 ]]
	info="$bt_dir/AA:BB:CC:DD:EE:01/info"
	[[ -f $info ]]
	grep -q '^\[General\]' "$info"
	grep -q '^Name=Speaker' "$info"
	grep -q '^Trusted=true' "$info"
	grep -q '^\[DeviceID\]' "$info"
	grep -q '^Source=1' "$info"
	grep -q '^Vendor=148' "$info"
	grep -q '^Product=4' "$info"
}

# ---------------------------------------------------------------------------
# Update existing paired device
# ---------------------------------------------------------------------------

@test "existing device: Trusted, Name, Alias are updated while link keys are preserved" {
	dev_dir="$bt_dir/AA:BB:CC:DD:EE:01"
	mkdir -p "$dev_dir"
	cat >"$dev_dir/info" <<'EOF'
[General]
Name=OldName
Alias=OldAlias
Trusted=false
Blocked=false

[LinkKey]
Key=AABBCCDD
Type=4
PINLength=0
EOF
	chmod 600 "$dev_dir/info"

	run_sync "$patched"
	[[ $status -eq 0 ]]
	info="$dev_dir/info"
	grep -q '^Trusted=true' "$info"
	grep -q '^Name=Speaker' "$info"
	grep -q '^Alias=Speaker' "$info"
	grep -q '^Key=AABBCCDD' "$info"
}

# ---------------------------------------------------------------------------
# Unknown device removal
# ---------------------------------------------------------------------------

@test "unknown device directory is removed" {
	unknown="$bt_dir/FF:FF:FF:FF:FF:FF"
	mkdir -p "$unknown"
	echo "[General]" >"$unknown/info"

	run_sync "$patched"
	[[ $status -eq 0 ]]
	[[ ! -d $unknown ]]
}

@test "a failed removal makes the status non-zero, after the other devices" {
	unknown="$bt_dir/FF:FF:FF:FF:FF:FF"
	mkdir -p "$unknown"
	echo "[General]" >"$unknown/info"
	chmod 500 "$unknown"

	run_sync "$patched"
	chmod 700 "$unknown"
	[[ $status -ne 0 ]]
	[[ -f $bt_dir/AA:BB:CC:DD:EE:01/info ]]
	[[ -f $bt_dir/AA:BB:CC:DD:EE:02/info ]]
}

# ---------------------------------------------------------------------------
# Missing adapter directory
# ---------------------------------------------------------------------------

@test "missing adapter directory: exits cleanly" {
	rm -rf "$bt_dir"
	run_sync "$patched"
	[[ $status -eq 0 ]]
	[[ $output == *"missing, skipping"* ]]
}

# ---------------------------------------------------------------------------
# Invalid bt_dir pattern (tests the original script guard)
# ---------------------------------------------------------------------------

@test "bt_dir with wrong pattern: original script aborts with error" {
	export bt_dir="$tmpdir/wrong/path"
	mkdir -p "$bt_dir"
	run_sync "$SCRIPT"
	[[ $status -ne 0 ]]
	[[ $output == *"looks wrong"* ]]
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "idempotency: running twice produces the same result" {
	run_sync "$patched"
	[[ $status -eq 0 ]]
	info1=$(cat "$bt_dir/AA:BB:CC:DD:EE:01/info")

	run_sync "$patched"
	[[ $status -eq 0 ]]
	info2=$(cat "$bt_dir/AA:BB:CC:DD:EE:01/info")

	[[ $info1 == "$info2" ]]
}
