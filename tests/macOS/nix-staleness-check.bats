#!/usr/bin/env bats
# Tests for scripts/nix-staleness-check.sh
# shellcheck disable=SC2154  # tmpdir is set by isolation_setup before any test body runs
#
# The script checks a Nix flake directory for stale inputs (older than 14 days)
# and emits a macOS notification via osascript when any are found.
#
# Isolation strategy:
# - NIX_BIN and JQ_BIN env vars override the tools the script calls, bypassing
#   the /run/current-system/sw/bin prepend the script performs on PATH.
# - OSASCRIPT_BIN overrides the hardcoded /usr/bin/osascript so notification
#   calls can be intercepted without root access or a macOS environment.
# - STALENESS_CUTOFF_SECONDS fixes the 14-day cutoff to a known epoch value,
#   bypassing the platform-specific date invocation.
# - TS_FROM_ISO_DATE points to a script that converts ISO 8601 strings to epoch
#   seconds, bypassing the BSD-only "date -j -f" invocation.
#
# All tests run on Linux and macOS alike.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/nix-staleness-check.sh"

load '../helpers/isolation'
load '../helpers/nix_mocks'

setup()    { isolation_setup; }
teardown() { isolation_teardown; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# make_fake_ts_parser <mode>
# mode=stale  → always returns 0 (older than any realistic cutoff)
# mode=fresh  → always returns current epoch (newer than any realistic cutoff)
# mode=fixed:<n> → always returns n
make_fake_ts_parser() {
    local mode="${1:-fresh}"
    mkdir -p "$tmpdir/bin"
    case "$mode" in
        stale) printf '#!/bin/sh\necho "0"\n' > "$tmpdir/bin/ts_parser" ;;
        fresh) printf '#!/bin/sh\ndate +%%s\n'  > "$tmpdir/bin/ts_parser" ;;
        fixed:*) printf '#!/bin/sh\necho "%s"\n' "${mode#fixed:}" > "$tmpdir/bin/ts_parser" ;;
    esac
    chmod +x "$tmpdir/bin/ts_parser"
}

# run_staleness [extra KEY=VALUE pairs]
# Runs the script with essential test overrides pre-applied.
# Extra KEY=VALUE pairs (e.g. NH_FLAKE=... STALENESS_CUTOFF_SECONDS=...) are
# passed as env assignments before the bash invocation via "$@".
run_staleness() {
    env HOME="$tmpdir" \
        NIX_BIN="$tmpdir/bin/nix" \
        JQ_BIN="$tmpdir/bin/jq" \
        OSASCRIPT_BIN="$tmpdir/bin/osascript" \
        TS_FROM_ISO_DATE="$tmpdir/bin/ts_parser" \
        "$@" \
        bash -c 'export HOME NIX_BIN JQ_BIN OSASCRIPT_BIN TS_FROM_ISO_DATE NH_FLAKE \
                        STALENESS_CUTOFF_SECONDS; source "$1"' \
        _ "$SCRIPT"
}

# ---------------------------------------------------------------------------
# a. Early exit when NH_FLAKE is unset
# ---------------------------------------------------------------------------

@test "exits 0 when NH_FLAKE is unset" {
    make_fake_osascript
    run env -u NH_FLAKE HOME="$tmpdir" \
        OSASCRIPT_BIN="$tmpdir/bin/osascript" \
        bash -c 'export HOME OSASCRIPT_BIN; unset NH_FLAKE; source "$1"' _ "$SCRIPT"
    [[ $status -eq 0 ]]
}

@test "no osascript call when NH_FLAKE is unset" {
    make_fake_osascript
    env -u NH_FLAKE HOME="$tmpdir" \
        OSASCRIPT_BIN="$tmpdir/bin/osascript" \
        bash -c 'export HOME OSASCRIPT_BIN; unset NH_FLAKE; source "$1"' _ "$SCRIPT"
    [[ -z $(fake_calls) ]]
}

# ---------------------------------------------------------------------------
# b. Early exit when NH_FLAKE points at a nonexistent directory
# ---------------------------------------------------------------------------

@test "exits 0 when NH_FLAKE points at a nonexistent directory" {
    make_fake_osascript
    run env -u NH_FLAKE HOME="$tmpdir" \
        NH_FLAKE="/nonexistent/path/to/flake" \
        OSASCRIPT_BIN="$tmpdir/bin/osascript" \
        bash -c 'export HOME NH_FLAKE OSASCRIPT_BIN; source "$1"' _ "$SCRIPT"
    [[ $status -eq 0 ]]
}

@test "no osascript call when NH_FLAKE points at a nonexistent directory" {
    make_fake_osascript
    env -u NH_FLAKE HOME="$tmpdir" \
        NH_FLAKE="/nonexistent/path/to/flake" \
        OSASCRIPT_BIN="$tmpdir/bin/osascript" \
        bash -c 'export HOME NH_FLAKE OSASCRIPT_BIN; source "$1"' _ "$SCRIPT"
    [[ -z $(fake_calls) ]]
}

# ---------------------------------------------------------------------------
# c. Fresh inputs: no notification
# ---------------------------------------------------------------------------

@test "exits 0 with fresh inputs" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    make_fake_jq fresh
    make_fake_osascript
    make_fake_ts_parser fresh
    local cutoff; cutoff=$(date -d '14 days ago' +%s 2>/dev/null || date -v-14d +%s)
    run run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="$cutoff"
    [[ $status -eq 0 ]]
}

@test "no osascript call with fresh inputs" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    make_fake_jq fresh
    make_fake_osascript
    make_fake_ts_parser fresh
    local cutoff; cutoff=$(date -d '14 days ago' +%s 2>/dev/null || date -v-14d +%s)
    run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="$cutoff"
    [[ -z $(fake_calls) ]]
}

# ---------------------------------------------------------------------------
# d. Single stale input: notification sent
# ---------------------------------------------------------------------------

@test "exits 0 with a single stale input" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    make_fake_jq stale
    make_fake_osascript
    make_fake_ts_parser stale
    local cutoff; cutoff=$(date -d '14 days ago' +%s 2>/dev/null || date -v-14d +%s)
    run run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="$cutoff"
    [[ $status -eq 0 ]]
}

@test "osascript called with 'Stale inputs' for a single stale input" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    make_fake_jq stale
    make_fake_osascript
    make_fake_ts_parser stale
    local cutoff; cutoff=$(date -d '14 days ago' +%s 2>/dev/null || date -v-14d +%s)
    run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="$cutoff"
    [[ $(fake_calls) == *"osascript"* ]]
    [[ $(fake_calls) == *"Stale inputs"* ]]
}

# ---------------------------------------------------------------------------
# e. nix metadata failure: script exits cleanly
# ---------------------------------------------------------------------------

@test "exits 0 when nix metadata fails" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix fail
    make_fake_osascript
    run run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="9999999999"
    [[ $status -eq 0 ]]
}

@test "no osascript call when nix metadata fails" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix fail
    make_fake_osascript
    run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="9999999999"
    [[ -z $(fake_calls) ]]
}

# ---------------------------------------------------------------------------
# f. jq parse error: script exits cleanly
# ---------------------------------------------------------------------------

@test "exits 0 when jq exits non-zero" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    printf '#!/bin/sh\nexit 1\n' > "$tmpdir/bin/jq"; chmod +x "$tmpdir/bin/jq"
    make_fake_osascript
    run run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="9999999999"
    [[ $status -eq 0 ]]
}

@test "no osascript call when jq exits non-zero" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    printf '#!/bin/sh\nexit 1\n' > "$tmpdir/bin/jq"; chmod +x "$tmpdir/bin/jq"
    make_fake_osascript
    run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="9999999999"
    [[ -z $(fake_calls) ]]
}

# ---------------------------------------------------------------------------
# g. Boundary: input with ts exactly equal to cutoff is NOT stale
#
# The script uses a strict less-than comparison: [ "$ts" -lt "$cutoff" ]
# An input whose timestamp equals the cutoff is therefore NOT considered stale.
# An input one second before the cutoff IS stale.
# ---------------------------------------------------------------------------

@test "boundary: input with ts equal to cutoff is NOT stale (strict less-than)" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    # jq returns an arbitrary ISO date; ts_parser will override the parsed value
    printf '#!/bin/sh\necho "nixpkgs=1970-01-01T00:16:40"\n' > "$tmpdir/bin/jq"; chmod +x "$tmpdir/bin/jq"
    make_fake_osascript
    # ts_parser returns 1000; cutoff is also 1000 → 1000 < 1000 is false → not stale
    make_fake_ts_parser "fixed:1000"
    run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="1000"
    [[ -z $(fake_calls) ]]
}

@test "boundary: input with ts one second before cutoff IS stale" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    printf '#!/bin/sh\necho "nixpkgs=1970-01-01T00:16:39"\n' > "$tmpdir/bin/jq"; chmod +x "$tmpdir/bin/jq"
    make_fake_osascript
    # ts_parser returns 999; cutoff is 1000 → 999 < 1000 is true → stale
    make_fake_ts_parser "fixed:999"
    run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="1000"
    [[ $(fake_calls) == *"Stale inputs"* ]]
}

# ---------------------------------------------------------------------------
# h. Multiple stale inputs: notification lists all names
# ---------------------------------------------------------------------------

@test "notification message lists all stale input names" {
    local flake_dir="$tmpdir/flake"
    mkdir -p "$flake_dir"
    make_fake_nix ok
    # jq returns two stale entries
    printf '#!/bin/sh\necho "nixpkgs=1970-01-01T00:00:01"\necho "home-manager=1970-01-01T00:00:02"\n' \
        > "$tmpdir/bin/jq"; chmod +x "$tmpdir/bin/jq"
    make_fake_osascript
    make_fake_ts_parser stale
    local cutoff; cutoff=$(date -d '14 days ago' +%s 2>/dev/null || date -v-14d +%s)
    run_staleness NH_FLAKE="$flake_dir" STALENESS_CUTOFF_SECONDS="$cutoff"
    [[ $(fake_calls) == *"nixpkgs"* ]]
    [[ $(fake_calls) == *"home-manager"* ]]
}
