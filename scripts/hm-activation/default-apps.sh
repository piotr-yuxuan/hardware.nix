#!/usr/bin/env bash
set -uo pipefail

: "${DRY_RUN_CMD:=}"

export DUTI_BIN="@DUTI_BIN@"

if ! bash "@DEFAULT_APPS_SCRIPT@"; then
	echo "defaultApps: warning: failed to set macOS defaults; continuing." >&2
fi
