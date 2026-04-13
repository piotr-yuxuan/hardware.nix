#!/usr/bin/env bats
# Tests for scripts/finder-favorites-macOS.sh
# shellcheck disable=SC2154  # tmpdir is set by isolation_setup before any test body runs
# shellcheck disable=SC2120  # live() and dry() accept optional extra env vars; not all callers use them
#
# The script manages Finder sidebar entries via the mysides binary.
# MYSIDES_BIN must be set by the caller; DRY_RUN_CMD is provided by
# Home Manager (empty string for live mode, "echo" for dry-run).
#
# Isolation strategy:
# - MYSIDES_BIN is pointed at a fake binary in $tmpdir/bin/mysides that
#   records every invocation in $HOME/.fake-calls.
# - The fake mysides prints a configurable list of entries for the "list"
#   subcommand so that remove/add ordering can be verified.
# - DRY_RUN_CMD=echo is set for dry-run tests; remove and add invocations
#   are then only echoed to stdout, not executed.
#
# All tests run on Linux and macOS alike; no real mysides is needed.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/finder-favorites-macOS.sh"

load '../helpers/isolation'

setup()    { isolation_setup; }
teardown() { isolation_teardown; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# make_fake_mysides [list_output]
# Creates $tmpdir/bin/mysides that records calls and emits list_output for
# the "list" subcommand.  Pass an empty string for an empty sidebar.
make_fake_mysides() {
    local list_output="${1:-}"
    mkdir -p "$tmpdir/bin"
    {
        printf '#!/bin/sh\n'
        printf 'echo "mysides $*" >> "$HOME/.fake-calls"\n'
        printf 'if [ "$1" = "list" ]; then\n'
        printf '    printf "%%s\n" '"'"'%s'"'"'\n' "$list_output"
        printf 'fi\n'
    } > "$tmpdir/bin/mysides"
    chmod +x "$tmpdir/bin/mysides"
}

# live [extra env vars as KEY=VALUE ...]
# Sources the script in live mode (no DRY_RUN_CMD).
live() {
    env HOME="$tmpdir" MYSIDES_BIN="$tmpdir/bin/mysides" "$@" bash -c '
        export HOME MYSIDES_BIN
        DRY_RUN_CMD=
        source "$1"
    ' _ "$SCRIPT"
}

# dry [extra env vars as KEY=VALUE ...]
# Sources the script in dry-run mode and captures output+status via bats run.
dry() {
    run env HOME="$tmpdir" MYSIDES_BIN="$tmpdir/bin/mysides" "$@" bash -c '
        export HOME MYSIDES_BIN DRY_RUN_CMD
        DRY_RUN_CMD=echo
        source "$1"
    ' _ "$SCRIPT"
}

# ---------------------------------------------------------------------------
# a. MYSIDES_BIN absent
# ---------------------------------------------------------------------------

@test "exits 0 when MYSIDES_BIN does not exist" {
    run env HOME="$tmpdir" MYSIDES_BIN="/nonexistent/mysides" bash -c '
        export HOME MYSIDES_BIN
        source "$1"
    ' _ "$SCRIPT"
    [[ $status -eq 0 ]]
}

@test "prints 'skipping' to stderr when MYSIDES_BIN does not exist" {
    run env HOME="$tmpdir" MYSIDES_BIN="/nonexistent/mysides" bash -c '
        export HOME MYSIDES_BIN
        source "$1" 2>&1
    ' _ "$SCRIPT"
    [[ $output == *"skipping"* ]]
}

# ---------------------------------------------------------------------------
# b. MYSIDES_BIN present but not executable
# ---------------------------------------------------------------------------

@test "exits 0 when MYSIDES_BIN is present but not executable" {
    local not_x="$tmpdir/bin/mysides-not-exec"
    mkdir -p "$tmpdir/bin"
    touch "$not_x"
    run env HOME="$tmpdir" MYSIDES_BIN="$not_x" bash -c '
        export HOME MYSIDES_BIN
        source "$1"
    ' _ "$SCRIPT"
    [[ $status -eq 0 ]]
}

@test "prints 'skipping' to stderr when MYSIDES_BIN is not executable" {
    local not_x="$tmpdir/bin/mysides-not-exec"
    mkdir -p "$tmpdir/bin"
    touch "$not_x"
    run env HOME="$tmpdir" MYSIDES_BIN="$not_x" bash -c '
        export HOME MYSIDES_BIN
        source "$1" 2>&1
    ' _ "$SCRIPT"
    [[ $output == *"skipping"* ]]
}

# ---------------------------------------------------------------------------
# c. Live mode: all wanted entries are added
# ---------------------------------------------------------------------------

@test "live mode: all wanted entries are added to the sidebar" {
    make_fake_mysides ""
    live
    local wanted=(Applications Home img mov net pvt snd src)
    for name in "${wanted[@]}"; do
        [[ $(fake_calls) == *"mysides add $name"* ]]
    done
}

# ---------------------------------------------------------------------------
# d. Live mode: existing entries are removed before adding
# ---------------------------------------------------------------------------

@test "live mode: existing sidebar entry is removed before adding" {
    make_fake_mysides "OldEntry -> file:///path/to/OldEntry"
    live
    [[ $(fake_calls) == *"mysides remove OldEntry"* ]]
}

@test "live mode: remove appears before add in the call log" {
    make_fake_mysides "OldEntry -> file:///path/to/OldEntry"
    live
    local calls; calls=$(fake_calls)
    local remove_line add_line
    remove_line=$(echo "$calls" | grep -n "remove OldEntry" | head -1 | cut -d: -f1)
    add_line=$(echo "$calls"    | grep -n "add Applications"  | head -1 | cut -d: -f1)
    [[ -n $remove_line && -n $add_line ]]
    [[ $remove_line -lt $add_line ]]
}

# ---------------------------------------------------------------------------
# e. Live mode: add uses correct file:// URL scheme
# ---------------------------------------------------------------------------

@test "live mode: add calls include file:// URL with correct HOME path" {
    make_fake_mysides ""
    live
    local wanted=(Applications Home img mov net pvt snd src)
    for name in "${wanted[@]}"; do
        [[ $(fake_calls) == *"mysides add $name file://$tmpdir/$name/"* ]]
    done
}

# ---------------------------------------------------------------------------
# f. Dry-run mode: mysides remove and add are not invoked
# ---------------------------------------------------------------------------

@test "dry-run mode: exits 0" {
    make_fake_mysides ""
    dry
    [[ $status -eq 0 ]]
}

@test "dry-run mode: mysides remove and add are not recorded in fake_calls" {
    make_fake_mysides "OldEntry -> file:///path/to/OldEntry"
    dry
    # mysides list IS called (not guarded by DRY_RUN_CMD), but remove and add
    # are only echoed to stdout, never executed.
    [[ $(fake_calls) != *"mysides remove"* ]]
    [[ $(fake_calls) != *"mysides add"* ]]
}

# ---------------------------------------------------------------------------
# g. Dry-run mode: commands are printed to stdout
# ---------------------------------------------------------------------------

@test "dry-run mode: add commands are printed to stdout" {
    make_fake_mysides ""
    dry
    [[ $output == *"mysides add"* ]]
}

@test "dry-run mode: all wanted names appear in stdout" {
    make_fake_mysides ""
    dry
    local wanted=(Applications Home img mov net pvt snd src)
    for name in "${wanted[@]}"; do
        [[ $output == *"mysides add $name"* ]]
    done
}

# ---------------------------------------------------------------------------
# h. Idempotency: second run produces the same call pattern
# ---------------------------------------------------------------------------

@test "idempotency: second run exits 0" {
    make_fake_mysides ""
    live
    live
    [[ $? -eq 0 ]]
}

@test "idempotency: second run adds the same set of wanted entries" {
    make_fake_mysides ""
    live
    # Clear the call log before the second run
    rm -f "$tmpdir/.fake-calls"
    live
    local wanted=(Applications Home img mov net pvt snd src)
    for name in "${wanted[@]}"; do
        [[ $(fake_calls) == *"mysides add $name"* ]]
    done
}
