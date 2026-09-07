#!/usr/bin/env bats
# Tests for scripts/darwin-post-activation.sh
#
# The script runs as root during darwin-rebuild switch and writes one
# login window preference.  Tests use a fake defaults binary.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/darwin-post-activation.sh"

load '../helpers/isolation'

setup() {
	isolation_setup

	# Fake defaults: record invocations
	make_fake_bin defaults ''

	# Patched script: replace /usr/bin/defaults with our fake
	export patched="$tmpdir/darwin-post-activation-patched.sh"
	sed "s|/usr/bin/defaults|$tmpdir/bin/defaults|g" "$SCRIPT" >"$patched"

	export HOME="$tmpdir"
}

teardown() {
	isolation_teardown
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "script exits 0" {
	run bash -c "
		export HOME=\"$tmpdir\"
		source \"$patched\"
	"
	[[ $status -eq 0 ]]
}

@test "defaults write is called with com.apple.loginwindow ShowInputMenu -bool true" {
	bash -c "
		export HOME=\"$tmpdir\"
		source \"$patched\"
	"
	calls=$(fake_calls)
	[[ $calls == *"defaults write /Library/Preferences/com.apple.loginwindow ShowInputMenu -bool true"* ]]
}
