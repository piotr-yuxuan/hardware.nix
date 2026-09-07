#!/usr/bin/env bash
set -uo pipefail

: "${DRY_RUN_CMD:=}"

export BREWFILE="@BREWFILE@"

if ! bash "@BREW_BUNDLE_SCRIPT@"; then
	echo "brewBundle: warning: Brewfile activation failed; continuing." >&2
fi
