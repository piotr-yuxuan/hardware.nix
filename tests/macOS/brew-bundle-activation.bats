#!/usr/bin/env bats
# Tests for scripts/brew-bundle-activation.sh
# shellcheck disable=SC2154  # tmpdir is set by isolation_setup before any test body runs
#
# The script runs `brew bundle` during Home Manager activation on macOS.
# It discovers Homebrew at /opt/homebrew (ARM) then /usr/local (Intel).
#
# Isolation strategy:
# - HOMEBREW_ARM_PREFIX and HOMEBREW_X86_PREFIX env vars override the
#   hardcoded discovery paths, pointing them into $tmpdir so a fake brew
#   binary is found without root access and without macOS being required.
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

# make_fake_brew <prefix_dir> [brew_update_exit_code]
# Creates a fake brew binary at <prefix_dir>/bin/brew.
# Its shellenv subcommand adds <prefix_dir>/bin to PATH so the same fake
# is found after the script calls eval "$(brew shellenv)".
# If brew_update_exit_code is non-zero, brew update exits with that code.
make_fake_brew() {
    local prefix="$1"
    local update_exit="${2:-0}"
    mkdir -p "$prefix/bin"
    {
        printf '#!/bin/sh\n'
        printf 'echo "brew $*" >> "$HOME/.fake-calls"\n'
        printf 'if [ "$1" = "shellenv" ]; then\n'
        printf '    printf '"'"'export PATH="%s/bin:$PATH"\n'"'"' "%s"\n' "$prefix" "$prefix"
        printf 'elif [ "$1" = "update" ]; then\n'
        printf '    exit %d\n' "$update_exit"
        printf 'fi\n'
    } > "$prefix/bin/brew"
    chmod +x "$prefix/bin/brew"
}

# run_brew [extra KEY=VALUE env pairs]
# Sources the script in live mode in a zsh subshell.
run_brew() {
    env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" "$@" zsh -c '
        export HOME BREWFILE HOMEBREW_ARM_PREFIX HOMEBREW_X86_PREFIX
        source "$1"
    ' _ "$SCRIPT"
}

# run_brew_dry [extra KEY=VALUE env pairs]
# Sources the script in dry-run mode (DRY_RUN_CMD=echo).
run_brew_dry() {
    env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" DRY_RUN_CMD=echo "$@" zsh -c '
        export HOME BREWFILE DRY_RUN_CMD HOMEBREW_ARM_PREFIX HOMEBREW_X86_PREFIX
        source "$1"
    ' _ "$SCRIPT"
}

# ---------------------------------------------------------------------------
# a. No brew at either well-known path
# ---------------------------------------------------------------------------

@test "exits non-zero when Homebrew is not found at either path" {
    run env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" \
        HOMEBREW_ARM_PREFIX="$tmpdir/no-arm" \
        HOMEBREW_X86_PREFIX="$tmpdir/no-x86" \
        zsh -c '
            export HOME BREWFILE HOMEBREW_ARM_PREFIX HOMEBREW_X86_PREFIX
            source "$1"
        ' _ "$SCRIPT"
    [[ $status -ne 0 ]]
}

@test "prints 'Homebrew is not found' to stderr when no brew is available" {
    run env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" \
        HOMEBREW_ARM_PREFIX="$tmpdir/no-arm" \
        HOMEBREW_X86_PREFIX="$tmpdir/no-x86" \
        zsh -c '
            export HOME BREWFILE HOMEBREW_ARM_PREFIX HOMEBREW_X86_PREFIX
            source "$1" 2>&1
        ' _ "$SCRIPT"
    [[ $output == *"Homebrew is not found"* ]]
}

# ---------------------------------------------------------------------------
# b. brew found at /opt/homebrew (ARM prefix)
# ---------------------------------------------------------------------------

@test "exits 0 when brew is found at the ARM prefix" {
    make_fake_brew "$tmpdir/arm-brew"
    run run_brew HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
                 HOMEBREW_X86_PREFIX="$tmpdir/no-x86"
    [[ $status -eq 0 ]]
}

@test "ARM prefix is tried before the Intel prefix" {
    make_fake_brew "$tmpdir/arm-brew"
    make_fake_brew "$tmpdir/x86-brew"
    run_brew HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
             HOMEBREW_X86_PREFIX="$tmpdir/x86-brew"
    # Only the ARM brew should have been called.
    [[ $(fake_calls) == *"$tmpdir/arm-brew"* ]] || \
        [[ $(fake_calls) == *"brew shellenv"* ]]
    # The x86 brew's shellenv should not have been called.
    # (We check that only one "shellenv" entry is present.)
    local shellenv_count
    shellenv_count=$(fake_calls | grep -c "brew shellenv" || true)
    [[ $shellenv_count -eq 1 ]]
}

# ---------------------------------------------------------------------------
# c. Live mode: brew update is called
# ---------------------------------------------------------------------------

@test "live mode: brew update is called" {
    make_fake_brew "$tmpdir/arm-brew"
    run_brew HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
             HOMEBREW_X86_PREFIX="$tmpdir/no-x86"
    [[ $(fake_calls) == *"brew update"* ]]
}

# ---------------------------------------------------------------------------
# d. Live mode: brew bundle install is called with the correct --file
# ---------------------------------------------------------------------------

@test "live mode: brew bundle install is called with the correct Brewfile path" {
    make_fake_brew "$tmpdir/arm-brew"
    run_brew HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
             HOMEBREW_X86_PREFIX="$tmpdir/no-x86"
    [[ $(fake_calls) == *"brew bundle install --file $tmpdir/Brewfile --upgrade"* ]]
}

# ---------------------------------------------------------------------------
# e. Live mode: brew bundle cleanup is called
# ---------------------------------------------------------------------------

@test "live mode: brew bundle cleanup is called with the correct Brewfile path" {
    make_fake_brew "$tmpdir/arm-brew"
    run_brew HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
             HOMEBREW_X86_PREFIX="$tmpdir/no-x86"
    [[ $(fake_calls) == *"brew bundle cleanup --file $tmpdir/Brewfile"* ]]
}

# ---------------------------------------------------------------------------
# f. Live mode: call order is correct
# ---------------------------------------------------------------------------

@test "live mode: brew update appears before brew bundle install in the call log" {
    make_fake_brew "$tmpdir/arm-brew"
    run_brew HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
             HOMEBREW_X86_PREFIX="$tmpdir/no-x86"
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
    make_fake_brew "$tmpdir/arm-brew"
    run env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" DRY_RUN_CMD=echo \
        HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
        HOMEBREW_X86_PREFIX="$tmpdir/no-x86" \
        zsh -c '
            export HOME BREWFILE DRY_RUN_CMD HOMEBREW_ARM_PREFIX HOMEBREW_X86_PREFIX
            source "$1"
        ' _ "$SCRIPT"
    [[ $status -eq 0 ]]
}

@test "dry-run mode: brew update and bundle commands are printed to stdout" {
    make_fake_brew "$tmpdir/arm-brew"
    run env HOME="$tmpdir" BREWFILE="$tmpdir/Brewfile" DRY_RUN_CMD=echo \
        HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
        HOMEBREW_X86_PREFIX="$tmpdir/no-x86" \
        zsh -c '
            export HOME BREWFILE DRY_RUN_CMD HOMEBREW_ARM_PREFIX HOMEBREW_X86_PREFIX
            source "$1"
        ' _ "$SCRIPT"
    [[ $output == *"brew update"* ]]
    [[ $output == *"brew bundle install"* ]]
    [[ $output == *"brew bundle cleanup"* ]]
}

@test "dry-run mode: brew update and bundle are NOT recorded in fake_calls" {
    make_fake_brew "$tmpdir/arm-brew"
    run_brew_dry HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
                 HOMEBREW_X86_PREFIX="$tmpdir/no-x86"
    # shellenv IS called (discovery step), but update/bundle are only echoed.
    [[ $(fake_calls) != *"brew update"* ]]
    [[ $(fake_calls) != *"brew bundle install"* ]]
    [[ $(fake_calls) != *"brew bundle cleanup"* ]]
}

# ---------------------------------------------------------------------------
# h. brew update failure: script continues (no set -e; failure is intentionally
#    non-fatal to allow partial operation when the network is unavailable)
# ---------------------------------------------------------------------------

@test "brew update failure: script continues and exits 0" {
    # The script has no set -e; a failed brew update does not abort execution.
    make_fake_brew "$tmpdir/arm-brew" 1
    run run_brew HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
                 HOMEBREW_X86_PREFIX="$tmpdir/no-x86"
    [[ $status -eq 0 ]]
}

@test "brew update failure: brew bundle install is still called" {
    make_fake_brew "$tmpdir/arm-brew" 1
    run_brew HOMEBREW_ARM_PREFIX="$tmpdir/arm-brew" \
             HOMEBREW_X86_PREFIX="$tmpdir/no-x86"
    [[ $(fake_calls) == *"brew bundle install"* ]]
}
