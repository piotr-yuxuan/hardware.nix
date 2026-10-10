#!/usr/bin/env bats
# Tests for scripts/brew-bundle-activation.sh
# shellcheck disable=SC2154  # tmpdir is set by isolation_setup before any test body runs
#
# The script runs `brew bundle` during Home Manager activation on macOS.
# It discovers Homebrew at /opt/homebrew.
#
# Isolation strategy:
# - HOMEBREW_PREFIX env var overrides the hardcoded discovery path,
#   pointing it into $tmpdir so a fake brew binary is found without root
#   access and without macOS being required.
# - The fake brew records every invocation in $HOME/.fake-calls and emits
#   valid shellenv output so the PATH setup inside the script succeeds.
# - BREWFILE is set to a known path inside $tmpdir.
# - The script is zsh-based and is sourced in a zsh subshell; zsh must be
#   available (it is on all supported platforms for this project).
#
# All tests run on Linux and macOS alike.

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/brew-bundle-activation.sh"

load '../helpers/isolation'

setup() {
    isolation_setup
    # Default Brewfile used by all tests.
    touch "$tmpdir/Brewfile"
}
teardown() { isolation_teardown; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# make_fake_brew <prefix_dir> [brew_update_exit_code] [brew_bundle_install_exit_code] [brew_bundle_cleanup_exit_code]
# Creates a fake brew binary at <prefix_dir>/bin/brew.
# Its shellenv subcommand adds <prefix_dir>/bin to PATH so the same fake
# is found after the script calls eval "$(brew shellenv)".
# Exit codes default to 0.
make_fake_brew() {
    local prefix="$1"
    local update_exit="${2:-0}"
    local bundle_install_exit="${3:-0}"
    local bundle_cleanup_exit="${4:-0}"
    mkdir -p "$prefix/bin"
    {
        printf '#!/bin/sh\n'
        printf 'echo "brew $*" >> "$HOME/.fake-calls"\n'
        printf 'echo "HOMEBREW_NO_ASK=${HOMEBREW_NO_ASK:-unset} brew $*" >> "$HOME/.fake-env"\n'
        printf 'echo "HOMEBREW_BUNDLE_CLEANUP_NO_VSCODE=${HOMEBREW_BUNDLE_CLEANUP_NO_VSCODE:-unset} brew $*" >> "$HOME/.fake-env"\n'
        printf 'if [ "$1" = "shellenv" ]; then\n'
        printf '    printf '"'"'export PATH="%s/bin:$PATH"\n'"'"' "%s"\n' "$prefix" "$prefix"
        printf 'elif [ "$1" = "update" ]; then\n'
        printf '    exit %d\n' "$update_exit"
        printf 'elif [ "$1" = "bundle" ] && [ "$2" = "install" ]; then\n'
        printf '    exit %d\n' "$bundle_install_exit"
        printf 'elif [ "$1" = "bundle" ] && [ "$2" = "cleanup" ]; then\n'
        # Read only from a pipe or file, never from a terminal, so a
        # regression fails the stdin test instead of hanging a manual run.
        printf '    if [ ! -t 0 ] && read -r answer; then echo "cleanup read stdin: $answer" >> "$HOME/.fake-calls"; fi\n'
        printf '    exit %d\n' "$bundle_cleanup_exit"
        printf 'fi\n'
    } > "$prefix/bin/brew"
    chmod +x "$prefix/bin/brew"
}

# run_brew [extra KEY=VALUE env pairs]
# Sources the script in live mode in a zsh subshell.
run_brew() {
    env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" "$@" zsh -c '
        export HOME BREWFILE HOMEBREW_PREFIX
        source "$1"
    ' _ "$SCRIPT"
}

# run_brew_dry [extra KEY=VALUE env pairs]
# Sources the script in dry-run mode (DRY_RUN_CMD=echo).
run_brew_dry() {
    env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" DRY_RUN_CMD=echo "$@" zsh -c '
        export HOME BREWFILE DRY_RUN_CMD HOMEBREW_PREFIX
        source "$1"
    ' _ "$SCRIPT"
}

# ---------------------------------------------------------------------------
# a. No brew at either well-known path
# ---------------------------------------------------------------------------

@test "exits 0 when Homebrew is not found (non-fatal)" {
    run env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" \
        HOMEBREW_PREFIX="$tmpdir/no-brew" \
        zsh -c '
            export HOME BREWFILE HOMEBREW_PREFIX
            source "$1"
        ' _ "$SCRIPT"
    [[ $status -eq 0 ]]
}

@test "prints 'Homebrew is not found' to stderr when no brew is available" {
    run env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" \
        HOMEBREW_PREFIX="$tmpdir/no-brew" \
        zsh -c '
            export HOME BREWFILE HOMEBREW_PREFIX
            source "$1" 2>&1
        ' _ "$SCRIPT"
    [[ $output == *"Homebrew is not found"* ]]
}

# ---------------------------------------------------------------------------
# b. brew found at /opt/homebrew
# ---------------------------------------------------------------------------

@test "exits 0 when brew is found at the Homebrew prefix" {
    make_fake_brew "$tmpdir/brew"
    run run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $status -eq 0 ]]
}

# ---------------------------------------------------------------------------
# c. Live mode: brew update is called
# ---------------------------------------------------------------------------

@test "live mode: brew update is called" {
    make_fake_brew "$tmpdir/brew"
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $(fake_calls) == *"brew update"* ]]
}

# ---------------------------------------------------------------------------
# d. Live mode: brew bundle install is called with the correct --file
# ---------------------------------------------------------------------------

@test "live mode: brew bundle install is called with --upgrade (no --greedy: unsupported here)" {
    make_fake_brew "$tmpdir/brew"
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $(fake_calls) == *"brew bundle install --file $tmpdir/Brewfile --upgrade"* ]]
    # `brew bundle install` does not accept --greedy; ensure we did not regress.
    [[ $(fake_calls) != *"brew bundle install --file $tmpdir/Brewfile --upgrade --greedy"* ]]
}

@test "live mode: brew upgrade --greedy is called separately for auto-updating casks" {
    make_fake_brew "$tmpdir/brew"
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $(fake_calls) == *"brew upgrade --greedy"* ]]
}

# ---------------------------------------------------------------------------
# e. Live mode: drift detection runs brew bundle cleanup in read-only mode
# ---------------------------------------------------------------------------

@test "live mode: drift detection runs brew bundle cleanup (read-only, no --force)" {
    make_fake_brew "$tmpdir/brew"
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $(fake_calls) == *"brew bundle cleanup --file $tmpdir/Brewfile"* ]]
    # No --force unless the user accepts uninstall via the TTY prompt.
    [[ $(fake_calls) != *"--force"* ]]
}

@test "live mode: drift listing gets no stdin, so Homebrew cannot prompt to uninstall" {
    # Since Homebrew 6, `brew bundle cleanup` without --force offers to
    # remove the extras when it can read an answer. The listing must stay
    # read-only; the script's own menu decides.
    make_fake_brew "$tmpdir/brew"
    printf 'y\n' | run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $(fake_calls) == *"brew bundle cleanup --file $tmpdir/Brewfile"* ]]
    [[ $(fake_calls) != *"cleanup read stdin"* ]]
}

@test "live mode: Homebrew ask mode is disabled for bundle and upgrade" {
    make_fake_brew "$tmpdir/brew"
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    local env_log; env_log=$(cat "$tmpdir/.fake-env")
    [[ $env_log == *"HOMEBREW_NO_ASK=1 brew bundle install"* ]]
    [[ $env_log == *"HOMEBREW_NO_ASK=1 brew upgrade --greedy"* ]]
    [[ $env_log == *"HOMEBREW_NO_ASK=1 brew bundle cleanup"* ]]
}

@test "live mode: the drift listing leaves VS Code extensions alone" {
    # Another tool installs VS Code extensions that the Brewfile does not
    # declare. Homebrew must not list them as drift.
    make_fake_brew "$tmpdir/brew"
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    local env_log; env_log=$(cat "$tmpdir/.fake-env")
    [[ $env_log == *"HOMEBREW_BUNDLE_CLEANUP_NO_VSCODE=1 brew bundle cleanup --file $tmpdir/Brewfile"* ]]
}

@test "live mode: answering u to the drift menu leaves VS Code extensions alone" {
    # The fake brew reports drift (cleanup exits 1), so the menu opens. It
    # reads its answer from /dev/tty: Python's pty module gives the script
    # a controlling terminal and types the answer. The alarm ends the test
    # if the script ever waits for a second answer.
    make_fake_brew "$tmpdir/brew" 0 0 1
    printf 'u\n' | python3 -c 'import pty, signal, sys; signal.alarm(30); pty.spawn(sys.argv[1:])' \
        env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" HOMEBREW_PREFIX="$tmpdir/brew" zsh -c '
        export HOME BREWFILE HOMEBREW_PREFIX
        source "$1"
    ' _ "$SCRIPT"
    local env_log; env_log=$(cat "$tmpdir/.fake-env")
    [[ $env_log == *"HOMEBREW_BUNDLE_CLEANUP_NO_VSCODE=1 brew bundle cleanup --file $tmpdir/Brewfile --force"* ]]
}

@test "live mode: brew cleanup --prune=all -v is called to tidy cache" {
    make_fake_brew "$tmpdir/brew"
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $(fake_calls) == *"brew cleanup --prune=all -v"* ]]
}

# ---------------------------------------------------------------------------
# f. Live mode: call order is correct
# ---------------------------------------------------------------------------

@test "live mode: brew update appears before brew bundle install in the call log" {
    make_fake_brew "$tmpdir/brew"
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    local calls; calls=$(fake_calls)
    local update_line install_line
    update_line=$(echo "$calls"  | grep -n "brew update"          | head -1 | cut -d: -f1)
    install_line=$(echo "$calls" | grep -n "brew bundle install"  | head -1 | cut -d: -f1)
    [[ -n $update_line && -n $install_line ]]
    [[ $update_line -lt $install_line ]]
}

# ---------------------------------------------------------------------------
# g. Dry-run mode: brew update/bundle not invoked, commands printed to stdout
# ---------------------------------------------------------------------------

@test "dry-run mode: exits 0" {
    make_fake_brew "$tmpdir/brew"
    run env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" DRY_RUN_CMD=echo \
        HOMEBREW_PREFIX="$tmpdir/brew" \
        zsh -c '
            export HOME BREWFILE DRY_RUN_CMD HOMEBREW_PREFIX
            source "$1"
        ' _ "$SCRIPT"
    [[ $status -eq 0 ]]
}

@test "dry-run mode: brew update and bundle commands are printed to stdout" {
    make_fake_brew "$tmpdir/brew"
    run env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" DRY_RUN_CMD=echo \
        HOMEBREW_PREFIX="$tmpdir/brew" \
        zsh -c '
            export HOME BREWFILE DRY_RUN_CMD HOMEBREW_PREFIX
            source "$1"
        ' _ "$SCRIPT"
    [[ $output == *"brew update"* ]]
    [[ $output == *"brew bundle install"* ]]
}

@test "dry-run mode: brew update and bundle are NOT recorded in fake_calls" {
    make_fake_brew "$tmpdir/brew"
    run_brew_dry HOMEBREW_PREFIX="$tmpdir/brew"
    # shellenv IS called (discovery step), but update/bundle are only echoed.
    [[ $(fake_calls) != *"brew update"* ]]
    [[ $(fake_calls) != *"brew bundle install"* ]]
    [[ $(fake_calls) != *"brew bundle cleanup"* ]]
}

# ---------------------------------------------------------------------------
# h. brew update failure: script continues (non-fatal to allow partial
#    operation when the network is unavailable)
# ---------------------------------------------------------------------------

@test "brew update failure: script continues and exits 0" {
    # The script has no set -e; a failed brew update does not abort execution.
    make_fake_brew "$tmpdir/brew" 1
    run run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $status -eq 0 ]]
}

@test "brew update failure: brew bundle install is still called" {
    make_fake_brew "$tmpdir/brew" 1
    run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $(fake_calls) == *"brew bundle install"* ]]
}

# ---------------------------------------------------------------------------
# i. brew bundle install failure: script exits non-zero (do not silently
#    succeed when Brewfile entries fail to install)
# ---------------------------------------------------------------------------

@test "brew bundle install failure: exits 0 (non-fatal)" {
    make_fake_brew "$tmpdir/brew" 0 1
    run run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $status -eq 0 ]]
}

@test "brew bundle install failure: cleanup is not called" {
    make_fake_brew "$tmpdir/brew" 0 1
    run run_brew HOMEBREW_PREFIX="$tmpdir/brew"
    [[ $(fake_calls) != *"brew bundle cleanup"* ]]
}
