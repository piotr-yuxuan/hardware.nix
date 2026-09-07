#!/usr/bin/env bats
# Tests for scripts/tor-transparent-proxy-on.sh and
# scripts/tor-transparent-proxy-off.sh
#
# Both scripts call nft and id via variables set by the Nix wrapper.
# Tests provide fake binaries that record invocations and check the
# generated rulesets.

SCRIPT_ON="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/tor-transparent-proxy-on.sh"
SCRIPT_OFF="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/tor-transparent-proxy-off.sh"

load '../helpers/isolation'

setup() {
	isolation_setup

	# Fake id: print a numeric UID when called with -u tor
	make_fake_bin id 'if [ "$1" = "-u" ] && [ "$2" = "tor" ]; then echo 998; else echo 1000; fi'

	# Fake nft: record stdin when called with -f -
	make_fake_bin nft '
		if [ "$1" = "-f" ] && [ "$2" = "-" ]; then
			cat >> "$HOME/.nft-stdin"
		fi
	'

	export id_cmd="$tmpdir/bin/id"
	export nft_cmd="$tmpdir/bin/nft"
	export HOME="$tmpdir"
}

teardown() {
	isolation_teardown
}

# ---------------------------------------------------------------------------
# tor-transparent-proxy-on.sh
# ---------------------------------------------------------------------------

@test "on: script exits 0" {
	run bash -c "
		export id_cmd=\"$id_cmd\" nft_cmd=\"$nft_cmd\" HOME=\"$tmpdir\"
		source \"$SCRIPT_ON\"
	"
	[[ $status -eq 0 ]]
}

@test "on: nft -f - is called (stdin ruleset)" {
	run bash -c "
		export id_cmd=\"$id_cmd\" nft_cmd=\"$nft_cmd\" HOME=\"$tmpdir\"
		source \"$SCRIPT_ON\"
	"
	calls=$(fake_calls)
	[[ $calls == *"nft -f -"* ]]
}

@test "on: IPv4 ruleset references TransPort 9040 and DNSPort 5353" {
	bash -c "
		export id_cmd=\"$id_cmd\" nft_cmd=\"$nft_cmd\" HOME=\"$tmpdir\"
		source \"$SCRIPT_ON\"
	"
	stdin_content=$(cat "$tmpdir/.nft-stdin")
	[[ $stdin_content == *"9040"* ]]
	[[ $stdin_content == *"5353"* ]]
}

@test "on: IPv6 ruleset is a separate call that drops non-loopback traffic" {
	bash -c "
		export id_cmd=\"$id_cmd\" nft_cmd=\"$nft_cmd\" HOME=\"$tmpdir\"
		source \"$SCRIPT_ON\"
	"
	stdin_content=$(cat "$tmpdir/.nft-stdin")
	[[ $stdin_content == *"ip6 tor-transparent-proxy"* ]]
	[[ $stdin_content == *"drop"* ]]
}

@test "on: id -u tor is called to resolve the Tor UID" {
	bash -c "
		export id_cmd=\"$id_cmd\" nft_cmd=\"$nft_cmd\" HOME=\"$tmpdir\"
		source \"$SCRIPT_ON\"
	"
	calls=$(fake_calls)
	[[ $calls == *"id -u tor"* ]]
}

# ---------------------------------------------------------------------------
# tor-transparent-proxy-off.sh
# ---------------------------------------------------------------------------

@test "off: script exits 0" {
	run bash -c "
		export nft_cmd=\"$nft_cmd\" HOME=\"$tmpdir\"
		source \"$SCRIPT_OFF\"
	"
	[[ $status -eq 0 ]]
}

@test "off: nft delete table ip tor-transparent-proxy is called" {
	bash -c "
		export nft_cmd=\"$nft_cmd\" HOME=\"$tmpdir\"
		source \"$SCRIPT_OFF\"
	"
	calls=$(fake_calls)
	[[ $calls == *"nft delete table ip tor-transparent-proxy"* ]]
}

@test "off: nft delete table ip6 tor-transparent-proxy is called" {
	bash -c "
		export nft_cmd=\"$nft_cmd\" HOME=\"$tmpdir\"
		source \"$SCRIPT_OFF\"
	"
	calls=$(fake_calls)
	[[ $calls == *"nft delete table ip6 tor-transparent-proxy"* ]]
}
