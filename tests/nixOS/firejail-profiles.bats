#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIREJAIL_DIR="$REPO_ROOT/config/firejail"
HOST_CONFIG="$REPO_ROOT/hosts/nixOS.nix"

load '../helpers/isolation'

setup() {
	isolation_setup
}

teardown() {
	isolation_teardown
}

assert_directive() {
	local profile=$1
	local directive=$2
	grep -Fqx -- "$directive" "$FIREJAIL_DIR/$profile"
}

@test "Firefox exposes home without Firejail URL joining" {
	assert_directive firefox.profile 'whitelist ${HOME}'
	assert_directive firefox.profile 'ignore private-bin'
	assert_directive firefox.profile 'ignore private-etc'
	assert_directive firefox.profile 'include firefox-developer-edition.profile'

	run grep -Fqx -- 'join-or-start firefox-devedition' "$FIREJAIL_DIR/firefox.profile"
	[[ $status -eq 1 ]]
}

@test "Signal exposes home and can call the configured portal service" {
	assert_directive signal.profile 'whitelist ${HOME}'
	assert_directive signal.profile 'dbus-user.talk org.freedesktop.portal.Desktop'
	assert_directive signal.profile 'include signal-desktop.profile'
	grep -Fq 'runtimeInputs = [signalPortalXdgOpen];' "$HOST_CONFIG"
	grep -Fq 'executable = "${signalDesktopWithPortal}/bin/signal-desktop-with-portal";' "$HOST_CONFIG"
}

@test "VS Code exposes both source paths and uses Electron hardening" {
	assert_directive vscode.profile 'whitelist ${HOME}/src'
	assert_directive vscode.profile 'whitelist ${HOME}/Dropbox (Maestral)/example/src'
	assert_directive vscode.profile 'include electron-common-hardened.inc.profile'
	assert_directive vscode.profile 'include code.profile'

	run grep -c '^whitelist ${HOME}/' "$FIREJAIL_DIR/vscode.profile"
	[[ $status -eq 0 ]]
	[[ $output -eq 5 ]]
}

@test "Transmission remains limited to its dedicated download directory" {
	assert_directive transmission-gtk.profile 'ignore whitelist ${DOWNLOADS}'
	assert_directive transmission-gtk.profile 'whitelist ${HOME}/net/transmission'
	assert_directive transmission-gtk.profile 'include transmission-gtk.profile'
}

@test "Discord and VLC continue to inherit their upstream profiles" {
	assert_directive discord.profile 'ignore private-bin'
	assert_directive discord.profile 'include discord.profile'
	assert_directive vlc.profile 'ignore private-bin'
	assert_directive vlc.profile 'include vlc.profile'
}
