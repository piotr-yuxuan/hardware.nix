#!/usr/bin/env bats
# Tests for scripts/tor-transparent-proxy-on.sh and
# scripts/tor-transparent-proxy-off.sh
#
# Both scripts call nft and id from PATH. Tests run them with a PATH
# that holds only fake binaries, which record invocations, and check the
# generated rulesets.

SCRIPT_ON="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/tor-transparent-proxy-on.sh"
SCRIPT_OFF="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/tor-transparent-proxy-off.sh"

load '../helpers/isolation'

setup() {
	isolation_setup

	# Fake id: print a numeric UID when called with -u tor
	make_fake_bin id 'if [ "$1" = "-u" ] && [ "$2" = "tor" ]; then echo 998; else echo 1000; fi'

	# Fake nft: record stdin when called with -f -, using builtins only
	make_fake_bin nft '
		if [ "$1" = "-f" ] && [ "$2" = "-" ]; then
			while IFS= read -r line; do printf "%s\n" "$line"; done >> "$HOME/.nft-stdin"
		fi
	'

	export HOME="$tmpdir"
}

teardown() {
	isolation_teardown
}

# ---------------------------------------------------------------------------
# tor-transparent-proxy-on.sh
# ---------------------------------------------------------------------------

@test "on: script exits 0" {
	run_script "$SCRIPT_ON" PATH="$tmpdir/bin"
}

@test "on: nft -f - is called (stdin ruleset)" {
	run_script "$SCRIPT_ON" PATH="$tmpdir/bin"
	calls=$(fake_calls)
	[[ $calls == *"nft -f -"* ]]
}

@test "on: IPv4 ruleset references TransPort 9040 and DNSPort 5353" {
	run_script "$SCRIPT_ON" PATH="$tmpdir/bin"
	stdin_content=$(cat "$tmpdir/.nft-stdin")
	[[ $stdin_content == *"9040"* ]]
	[[ $stdin_content == *"5353"* ]]
}

@test "on: IPv6 ruleset is a separate call that drops non-loopback traffic" {
	run_script "$SCRIPT_ON" PATH="$tmpdir/bin"
	stdin_content=$(cat "$tmpdir/.nft-stdin")
	[[ $stdin_content == *"ip6 tor-transparent-proxy"* ]]
	[[ $stdin_content == *"drop"* ]]
}

@test "on: id -u tor is called to resolve the Tor UID" {
	run_script "$SCRIPT_ON" PATH="$tmpdir/bin"
	calls=$(fake_calls)
	[[ $calls == *"id -u tor"* ]]
}

# ---------------------------------------------------------------------------
# tor-transparent-proxy-off.sh
# ---------------------------------------------------------------------------

@test "off: script exits 0" {
	run_script "$SCRIPT_OFF" PATH="$tmpdir/bin"
}

@test "off: nft delete table ip tor-transparent-proxy is called" {
	run_script "$SCRIPT_OFF" PATH="$tmpdir/bin"
	calls=$(fake_calls)
	[[ $calls == *"nft delete table ip tor-transparent-proxy"* ]]
}

@test "off: nft delete table ip6 tor-transparent-proxy is called" {
	run_script "$SCRIPT_OFF" PATH="$tmpdir/bin"
	calls=$(fake_calls)
	[[ $calls == *"nft delete table ip6 tor-transparent-proxy"* ]]
}
