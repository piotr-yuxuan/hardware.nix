#!/usr/bin/env bash

# This file supports both sourcing and direct execution.  ShellCheck analyzes
# it as direct execution only and therefore mistakes the fallback exit branches
# after return for unreachable code.
# shellcheck disable=SC2317
# Home Manager activation sources this file from bash/zsh.
# Keep behaviour resilient: activation must not abort the full switch.
set -uo pipefail

: "${DRY_RUN_CMD:=}"

# Sourced as a home-manager activation script. Runs on every
# `home-manager switch` on macOS. BREWFILE is set by Nix interpolation
# in macOS.nix before this script runs.
#
# Logging policy: every brew action below is preceded by a banner and
# the command is echoed before it runs, so that the output of
# `sudo darwin-rebuild switch --flake '.#macOS'` makes it obvious what
# Homebrew did during activation. `run` is the single helper used to
# print and execute (or merely print, in DRY_RUN mode).

_banner() { printf '\n==> brewBundle: %s\n' "$*"; }
run() {
	printf '    $ %s\n' "$*"
	if [[ -n $DRY_RUN_CMD ]]; then
		return 0
	fi
	"$@"
}

# Locate Homebrew at the well-known prefix. During activation the PATH
# is minimal, so we cannot rely on `command -v brew`.
# HOMEBREW_PREFIX is overridable for tests. It defaults to the real path.
_brew="${HOMEBREW_PREFIX:-/opt/homebrew}/bin/brew"
if [[ -x "$_brew" ]]; then
	_banner "Homebrew detected at $_brew"
	eval "$("$_brew" shellenv)"
else
	echo "brewBundle: skipping Brewfile activation because Homebrew is not found." >&2
	return 0 2>/dev/null || exit 0
fi

# Homebrew 6 made ask mode the default: install and upgrade may stop to
# confirm. Activation must not wait for an answer.
export HOMEBREW_NO_ASK=1

# Another tool installs the VS Code extensions, from its own manifest;
# the Brewfile declares one of them. Without this variable,
# `brew bundle cleanup` counts every other extension as drift, and the
# answer u of the menu below uninstalls them.
export HOMEBREW_BUNDLE_CLEANUP_NO_VSCODE=1

# Refresh the Homebrew formula/cask index before installing.
# Equivalent to `apt update`; keeps formula metadata and available versions current.
# Non-fatal: activation should still attempt bundle install when offline.
_banner "refreshing formula and cask index (brew update)"
if ! run brew update; then
	echo "brewBundle: brew update failed; continuing." >&2
fi

# If Docker.app was installed manually, adopt it so `brew bundle` won't fail.
# This lets you switch to declarative management without manual cleanup.
# The token matches the Brewfile's docker-desktop cask.
if [[ -d /Applications/Docker.app ]] && ! brew list --cask docker-desktop >/dev/null 2>&1; then
	_banner "adopting pre-existing /Applications/Docker.app"
	run brew install --cask --adopt docker-desktop ||
		echo "brewBundle: warning: failed to adopt existing Docker.app" >&2
fi

# Install or upgrade all Brewfile entries.
# --upgrade: bring already-installed packages up to the latest formula version.
# Note: `brew bundle install` does not accept --greedy; greedy cask
# upgrades are handled by the dedicated `brew upgrade --greedy` step
# below.
_banner "installing and upgrading Brewfile entries (--upgrade)"
if ! run brew bundle install --file "$BREWFILE" --upgrade; then
	echo "brewBundle: brew bundle install failed; continuing." >&2
	return 0 2>/dev/null || exit 0
fi

# Greedy upgrade: also pull forward casks marked auto_updates or
# version :latest, which `brew bundle install --upgrade` skips.
# Non-fatal: a single failing cask must not abort the whole switch.
_banner "upgrading auto-updating casks (brew upgrade --greedy)"
run brew upgrade --greedy ||
	echo "brewBundle: brew upgrade --greedy failed; continuing." >&2

# Detect drift: items installed locally but not declared in the Brewfile.
# `brew bundle cleanup` without --force prints what would be removed and
# exits non-zero when drift exists. Since Homebrew 6 it also offers to
# remove them when it can read an answer, so give it no stdin: the menu
# below makes that choice.
_banner "checking for drift between installed packages and $BREWFILE"
if [[ -z $DRY_RUN_CMD ]] && ! run brew bundle cleanup --file "$BREWFILE" </dev/null; then
	if [[ -r /dev/tty ]]; then
		printf 'brewBundle: drift detected between installed packages and %s.\n' "$BREWFILE" >/dev/tty
		printf '  [u] uninstall the extras listed above\n' >/dev/tty
		printf '  [e] abort so you can edit %s and rerun the switch\n' "$BREWFILE" >/dev/tty
		printf '  [s] skip and leave the drift in place\n' >/dev/tty
		printf 'Choice [u/e/s]: ' >/dev/tty
		read -r _drift_choice </dev/tty || _drift_choice=s
		case "$_drift_choice" in
		u | U)
			_banner "user chose: uninstall extras (brew bundle cleanup --force)"
			run brew bundle cleanup --file "$BREWFILE" --force ||
				echo "brewBundle: brew bundle cleanup --force failed; continuing." >&2
			;;
		e | E)
			echo "brewBundle: aborting; edit $BREWFILE and rerun home-manager switch." >&2
			return 1 2>/dev/null || exit 1
			;;
		*) echo "brewBundle: drift left in place." >&2 ;;
		esac
	else
		echo "brewBundle: drift detected but no TTY available; leaving as-is." >&2
	fi
fi

# Tidy Homebrew state: remove stale downloads and prune the entire cache.
# Verbose so the activation log records exactly what was reclaimed.
_banner "tidying Homebrew cache (brew cleanup --prune=all -v)"
run brew cleanup --prune=all -v ||
	echo "brewBundle: brew cleanup failed; continuing." >&2
