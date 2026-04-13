# shellcheck shell=bash
# shellcheck disable=SC2154  # tmpdir is set by isolation.bash (sourced first)
# tests/helpers/nix_mocks.bash
#
# Pre-built fake implementations of Nix-adjacent tools used by
# activation scripts (nix, jq, date, osascript).
# Load with:  load '../helpers/nix_mocks'
# Requires isolation.bash to be loaded first (needs $tmpdir and make_fake_bin).

# make_fake_nix BEHAVIOUR
#
# Creates a fake nix binary in $tmpdir/bin/ that behaves according to
# BEHAVIOUR:
#   ok        - exits 0, prints minimal valid JSON (empty locks object).
#   stale     - exits 0, prints JSON with one input lastModified=1 (epoch).
#   fresh     - exits 0, prints JSON with lastModified set to current time.
#   fail      - exits 1 with an error message on stderr.
make_fake_nix() {
	local behaviour="${1:-ok}"
	mkdir -p "$tmpdir/bin"
	case "$behaviour" in
	ok)
		printf '#!/bin/sh\necho '"'"'{"locks":{"nodes":{}}}'"'"'\n' \
			>"$tmpdir/bin/nix"
		;;
	stale)
		printf '#!/bin/sh\necho '"'"'{"locks":{"nodes":{"nixpkgs":{"locked":{"lastModified":1}}}}}'"'"'\n' \
			>"$tmpdir/bin/nix"
		;;
	fresh)
		printf '#!/bin/sh\nnow=$(date +%%s)\necho "{\"locks\":{\"nodes\":{\"nixpkgs\":{\"locked\":{\"lastModified\":$now}}}}}"\n' \
			>"$tmpdir/bin/nix"
		;;
	fail)
		printf '#!/bin/sh\necho "error: nix failed" >&2\nexit 1\n' \
			>"$tmpdir/bin/nix"
		;;
	*)
		echo "make_fake_nix: unknown behaviour: $behaviour" >&2
		return 1
		;;
	esac
	chmod +x "$tmpdir/bin/nix"
}

# make_fake_jq BEHAVIOUR
#
# Creates a fake jq binary.  BEHAVIOUR:
#   stale       - returns a stale name=timestamp pair.
#   fresh       - returns a fresh name=timestamp pair (current time).
#   passthrough - runs the real jq found outside $tmpdir/bin.
make_fake_jq() {
	local behaviour="${1:-passthrough}"
	mkdir -p "$tmpdir/bin"
	case "$behaviour" in
	stale)
		printf '#!/bin/sh\necho "nixpkgs=1970-01-01T00:00:01"\n' \
			>"$tmpdir/bin/jq"
		;;
	fresh)
		printf '#!/bin/sh\nnow=$(date -u +%%Y-%%m-%%dT%%H:%%M:%%S)\necho "nixpkgs=${now}"\n' \
			>"$tmpdir/bin/jq"
		;;
	passthrough)
		local real_jq
		real_jq=$(PATH=$(echo "$PATH" | tr ':' '\n' | grep -v "^$tmpdir" | tr '\n' ':') command -v jq 2>/dev/null || true)
		if [ -z "$real_jq" ]; then
			echo "make_fake_jq passthrough: real jq not found on PATH" >&2
			return 1
		fi
		printf '#!/bin/sh\nexec %s "$@"\n' "$real_jq" >"$tmpdir/bin/jq"
		;;
	*)
		echo "make_fake_jq: unknown behaviour: $behaviour" >&2
		return 1
		;;
	esac
	chmod +x "$tmpdir/bin/jq"
}

# make_fake_osascript
#
# Creates a fake osascript that records invocations to the call log.
# The full argument list is recorded so tests can assert notification messages.
make_fake_osascript() {
	mkdir -p "$tmpdir/bin"
	printf '#!/bin/sh\necho "osascript $*" >> "$HOME/.fake-calls"\n' \
		>"$tmpdir/bin/osascript"
	chmod +x "$tmpdir/bin/osascript"
}

# make_fake_date BEHAVIOUR
#
# Creates a fake date binary.  BEHAVIOUR:
#   recent  - prints a timestamp 1 day ago.
#   old     - prints a timestamp 30 days ago.
# Tries BSD -v syntax first, falls back to GNU -d.
make_fake_date() {
	local behaviour="${1:-recent}"
	mkdir -p "$tmpdir/bin"
	case "$behaviour" in
	recent)
		printf '#!/bin/sh\ndate -v-1d +%%s 2>/dev/null || date -d "1 day ago" +%%s\n' \
			>"$tmpdir/bin/date"
		;;
	old)
		printf '#!/bin/sh\ndate -v-30d +%%s 2>/dev/null || date -d "30 days ago" +%%s\n' \
			>"$tmpdir/bin/date"
		;;
	*)
		echo "make_fake_date: unknown behaviour: $behaviour" >&2
		return 1
		;;
	esac
	chmod +x "$tmpdir/bin/date"
}
