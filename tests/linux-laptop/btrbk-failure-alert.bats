#!/usr/bin/env bats
# Tests for scripts/btrbk-failure-alert.sh
#
# The script broadcasts a failure message to PTYs owned by example,
# sends a desktop notification via notify-send, and displays an Emacs
# warning buffer via emacsclient.  Tests use fake binaries for all
# external commands and verify the invocations.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/btrbk-failure-alert.sh"

load '../helpers/isolation'

setup() {
	isolation_setup

	# Fake stat: print "example" for any PTY file
	make_fake_bin stat 'echo example'

	# Fake id: print UID 1000 for example
	make_fake_bin id 'echo 1000'

	# Fake notify-send: just record the call
	make_fake_bin notify-send ''

	# Fake emacsclient: just record the call
	make_fake_bin emacsclient ''

	# Fake sudo: invoke the command directly (skip privilege escalation).
	# The script calls sudo -u example [ENV=val ...] <command> <args>
	# We need to handle env vars passed as positional args before the command.
	make_fake_bin sudo '
		shift; shift  # skip -u example
		# Process any VAR=val arguments as environment exports
		while [ $# -gt 0 ]; do
			case "$1" in
				*=*) export "$1"; shift ;;
				*) break ;;
			esac
		done
		"$@"
	'

	export stat_cmd="$tmpdir/bin/stat"
	export id_cmd="$tmpdir/bin/id"
	export notify_send="$tmpdir/bin/notify-send"
	export emacsclient="$tmpdir/bin/emacsclient"
	export HOME="$tmpdir"

	# Create a fake /dev/pts directory with a pseudo PTY.
	# The script iterates /dev/pts/[0-9]* which we cannot fake without
	# root.  Instead we create a wrapper script that patches the loop
	# to use our test directory.
	export fake_pts_dir="$tmpdir/dev/pts"
	mkdir -p "$fake_pts_dir"
	touch "$fake_pts_dir/0"

	# Create a fake /run/user/1000 so the notify-send block fires
	mkdir -p "$tmpdir/run/user/1000"

	# Patched script: replace /dev/pts with our fake directory and
	# /run/wrappers/bin/sudo with our fake sudo, and /run/user with
	# our tmpdir/run/user
	export patched="$tmpdir/btrbk-alert-patched.sh"
	sed -e "s|/dev/pts|$fake_pts_dir|g" \
	    -e "s|/run/wrappers/bin/sudo|$tmpdir/bin/sudo|g" \
	    -e "s|/run/user/|$tmpdir/run/user/|g" \
	    "$SCRIPT" >"$patched"
}

teardown() {
	isolation_teardown
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@test "script exits 0 (alert service should not fail)" {
	run bash -c "
		export stat_cmd=\"$stat_cmd\" id_cmd=\"$id_cmd\" \
			notify_send=\"$notify_send\" emacsclient=\"$emacsclient\" \
			HOME=\"$tmpdir\"
		source \"$patched\"
	"
	[[ $status -eq 0 ]]
}

@test "emacsclient is called with -e flag and display-warning sexp" {
	bash -c "
		export stat_cmd=\"$stat_cmd\" id_cmd=\"$id_cmd\" \
			notify_send=\"$notify_send\" emacsclient=\"$emacsclient\" \
			HOME=\"$tmpdir\"
		source \"$patched\"
	"
	calls=$(fake_calls)
	[[ $calls == *"emacsclient -e"* ]]
	[[ $calls == *"display-warning"* ]]
}

@test "notify-send is called with -u critical and a message containing btrbk" {
	bash -c "
		export stat_cmd=\"$stat_cmd\" id_cmd=\"$id_cmd\" \
			notify_send=\"$notify_send\" emacsclient=\"$emacsclient\" \
			HOME=\"$tmpdir\"
		source \"$patched\"
	"
	calls=$(fake_calls)
	[[ $calls == *"notify-send -u critical"* ]]
	[[ $calls == *"btrbk"* ]]
}
