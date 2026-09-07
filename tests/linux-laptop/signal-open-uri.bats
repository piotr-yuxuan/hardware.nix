#!/usr/bin/env bats

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)/scripts/signal-open-uri.sh"

load '../helpers/isolation'

setup() {
	isolation_setup
	export HOME="$tmpdir"
	make_fake_bin gdbus ''
	export GDBUS_BIN="$tmpdir/bin/gdbus"
}

teardown() {
	isolation_teardown
}

@test "HTTP URLs are sent through the desktop OpenURI portal" {
	run bash "$SCRIPT" 'http://example.test/path?one=two'
	[[ $status -eq 0 ]]
	[[ $(fake_calls) == 'gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.OpenURI.OpenURI  http://example.test/path?one=two {}' ]]
}

@test "HTTPS URLs are sent through the desktop OpenURI portal" {
	run bash "$SCRIPT" 'https://example.test/a#fragment'
	[[ $status -eq 0 ]]
	[[ $(fake_calls) == 'gdbus call --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop --method org.freedesktop.portal.OpenURI.OpenURI  https://example.test/a#fragment {}' ]]
}

@test "non-HTTP URIs cannot use the host link bridge" {
	run bash "$SCRIPT" 'file:///home/example/.ssh/config'
	[[ $status -eq 3 ]]
	[[ $output == *'refusing non-HTTP URI'* ]]
	[[ -z $(fake_calls) ]]
}

@test "the helper requires exactly one URL" {
	run bash "$SCRIPT"
	[[ $status -eq 2 ]]
	[[ $output == 'usage: xdg-open URL' ]]
	[[ -z $(fake_calls) ]]

	run bash "$SCRIPT" 'https://one.test' 'https://two.test'
	[[ $status -eq 2 ]]
	[[ -z $(fake_calls) ]]
}
