#!/bin/sh
# Nix flake staleness check for macOS machines.
# Called weekly by launchd agent com.user.nix-staleness-check.
# Warns via macOS notification if any flake input is older than 14 days.
#
# NIX_BIN, JQ_BIN, and OSASCRIPT_BIN may be overridden for testing;
# they default to the standard paths found via PATH / absolute path.

export PATH="/run/current-system/sw/bin:$PATH"

_nix="${NIX_BIN:-nix}"
_jq="${JQ_BIN:-jq}"

flake_dir="${NH_FLAKE:-}"
if [ ! -d "$flake_dir" ]; then exit 0; fi

# STALENESS_CUTOFF_SECONDS may be injected by tests to fix the cutoff to a
# known epoch value, bypassing the platform-specific date invocation.
cutoff="${STALENESS_CUTOFF_SECONDS:-$(date -v-14d +%s 2>/dev/null || date -d '14 days ago' +%s)}"
stale=""

while IFS='=' read -r name date_str; do
	[ -z "$date_str" ] && continue
	# TS_FROM_ISO_DATE may be injected by tests to replace the platform-specific
	# BSD/GNU date invocation used to parse ISO 8601 strings into epoch seconds.
	if [ -n "${TS_FROM_ISO_DATE:-}" ]; then
		ts=$("$TS_FROM_ISO_DATE" "$date_str")
	else
		ts=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$date_str" +%s 2>/dev/null || echo 0)
	fi
	if [ "$ts" -lt "$cutoff" ] 2>/dev/null; then
		stale="$stale $name"
	fi
done <<EOF
$("$_nix" flake metadata --json "$flake_dir" 2>/dev/null | "$_jq" -r '.locks.nodes | to_entries[] | select(.value.locked.lastModified) | "\(.key)=\(.value.locked.lastModified | todate | split("T") | .[0] + "T" + (.[1] | split("+") | .[0]))"')
EOF

if [ -n "$stale" ]; then
	"${OSASCRIPT_BIN:-/usr/bin/osascript}" -e "display notification \"Stale inputs:$stale\" with title \"Nix flake inputs are outdated\" subtitle \"Run: nix flake update\""
fi
