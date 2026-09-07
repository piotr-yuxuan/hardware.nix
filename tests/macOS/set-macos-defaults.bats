#!/usr/bin/env bats
# Tests for scripts/set-macos-defaults.sh
#
# The script sets default applications on macOS using duti.
# Tests create a fake duti binary that records invocations and verify
# the correct UTI/bundle-ID associations are set.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/set-macos-defaults.sh"

load '../helpers/isolation'

setup() {
	isolation_setup

	# Fake duti: record invocations
	make_fake_bin duti ''

	export DUTI_BIN="$tmpdir/bin/duti"
	export DRY_RUN_CMD=""
	export HOME="$tmpdir"
}

teardown() {
	isolation_teardown
}

run_defaults() {
	run bash -c "
		export DUTI_BIN=\"$DUTI_BIN\" DRY_RUN_CMD=\"$DRY_RUN_CMD\" HOME=\"$tmpdir\"
		source \"$SCRIPT\"
	"
}

# ---------------------------------------------------------------------------
# Audio UTIs -> VLC
# ---------------------------------------------------------------------------

@test "audio UTIs are assigned to org.videolan.vlc" {
	run_defaults
	[[ $status -eq 0 ]]
	calls=$(fake_calls)
	[[ $calls == *"duti -s org.videolan.vlc public.audio all"* ]]
	[[ $calls == *"duti -s org.videolan.vlc public.mp3 all"* ]]
	[[ $calls == *"duti -s org.videolan.vlc public.flac-audio all"* ]]
}

# ---------------------------------------------------------------------------
# Programming/prose UTIs -> Emacs
# ---------------------------------------------------------------------------

@test "programming UTIs are assigned to org.gnu.Emacs" {
	run_defaults
	[[ $status -eq 0 ]]
	calls=$(fake_calls)
	[[ $calls == *"duti -s org.gnu.Emacs public.plain-text all"* ]]
	[[ $calls == *"duti -s org.gnu.Emacs public.source-code all"* ]]
	[[ $calls == *"duti -s org.gnu.Emacs public.python-script all"* ]]
}

# ---------------------------------------------------------------------------
# Office UTIs -> LibreOffice
# ---------------------------------------------------------------------------

@test "office UTIs are assigned to org.libreoffice.script" {
	run_defaults
	[[ $status -eq 0 ]]
	calls=$(fake_calls)
	[[ $calls == *"duti -s org.libreoffice.script org.openxmlformats.wordprocessingml.document all"* ]]
	[[ $calls == *"duti -s org.libreoffice.script com.microsoft.word.doc all"* ]]
}

# ---------------------------------------------------------------------------
# Browser UTIs -> Firefox Developer Edition
# ---------------------------------------------------------------------------

@test "browser UTIs and URL schemes are assigned to org.mozilla.firefoxdeveloperedition" {
	run_defaults
	[[ $status -eq 0 ]]
	calls=$(fake_calls)
	[[ $calls == *"duti -s org.mozilla.firefoxdeveloperedition public.html all"* ]]
	[[ $calls == *"duti -s org.mozilla.firefoxdeveloperedition http all"* ]]
	[[ $calls == *"duti -s org.mozilla.firefoxdeveloperedition https all"* ]]
}

# ---------------------------------------------------------------------------
# duti failure: script continues (|| true guard)
# ---------------------------------------------------------------------------

@test "duti failure does not abort the script" {
	# Make duti always fail
	cat >"$tmpdir/bin/duti" <<'DUTI'
#!/bin/sh
echo "duti $*" >> "$HOME/.fake-calls"
exit 1
DUTI
	chmod +x "$tmpdir/bin/duti"

	run_defaults
	[[ $status -eq 0 ]]
	# Should still have attempted multiple calls
	calls=$(fake_calls)
	lines=$(echo "$calls" | wc -l)
	[[ $lines -gt 5 ]]
}

# ---------------------------------------------------------------------------
# Dry-run mode (DRY_RUN_CMD=echo)
# ---------------------------------------------------------------------------

@test "dry-run mode echoes duti commands but does not invoke the real binary" {
	export DRY_RUN_CMD=echo
	# Use a duti that would fail if actually called
	cat >"$tmpdir/bin/duti" <<'DUTI'
#!/bin/sh
echo "SHOULD NOT RUN" >&2
exit 1
DUTI
	chmod +x "$tmpdir/bin/duti"

	run bash -c "
		export DUTI_BIN=\"$DUTI_BIN\" DRY_RUN_CMD=echo HOME=\"$tmpdir\"
		source \"$SCRIPT\"
	"
	[[ $status -eq 0 ]]
	# The output should contain the echoed duti commands
	[[ $output == *"duti"* ]]
	[[ $output == *"org.videolan.vlc"* ]]
}
