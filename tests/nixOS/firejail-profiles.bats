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

# Firejail applies an ignore only to the commands it reads afterwards,
# so it has to come before the shipped profile.
@test "VLC opens files from any folder of home and from /tmp" {
	local ignore_line include_line
	assert_directive vlc.profile 'whitelist ${HOME}'
	assert_directive vlc.profile 'ignore private-tmp'

	ignore_line=$(grep -nFx 'ignore private-tmp' "$FIREJAIL_DIR/vlc.profile" | cut -d: -f1)
	include_line=$(grep -nFx 'include vlc.profile' "$FIREJAIL_DIR/vlc.profile" | cut -d: -f1)
	((ignore_line < include_line))
}

# Firejail cannot relax dbus-user none to a filter once it has read it,
# so the ignore has to come before the shipped profile.
@test "mpv may own only its MPRIS names on a filtered session bus" {
	local ignore_line include_line
	assert_directive mpv.profile 'ignore private-bin'
	assert_directive mpv.profile 'ignore dbus-user none'
	assert_directive mpv.profile 'dbus-user filter'
	assert_directive mpv.profile 'dbus-user.own org.mpris.MediaPlayer2.mpv'
	assert_directive mpv.profile 'dbus-user.own org.mpris.MediaPlayer2.mpv.*'
	assert_directive mpv.profile 'include mpv.profile'

	run grep -c '^dbus-user\.' "$FIREJAIL_DIR/mpv.profile"
	[[ $status -eq 0 ]]
	[[ $output -eq 2 ]]

	ignore_line=$(grep -nFx 'ignore dbus-user none' "$FIREJAIL_DIR/mpv.profile" | cut -d: -f1)
	include_line=$(grep -nFx 'include mpv.profile' "$FIREJAIL_DIR/mpv.profile" | cut -d: -f1)
	((ignore_line < include_line))
}

# The system path links each desktop file to the package that provides
# it; the icon package links on to the unwrapped application, so only the
# first link tells where the file comes from.
@test "no GUI launcher of a sandboxed app runs it outside its firejail wrapper" {
	local system_path desktop provider offenders=()
	command -v nix >/dev/null || skip "nix unavailable"
	nix store info >/dev/null 2>&1 || skip "nix store unreachable"
	cd "$REPO_ROOT" || return 1
	# A failed build is what this test guards against (a desktop file
	# whose substitution no longer applies), so it fails rather than
	# skips.
	if ! system_path=$(nix build --no-link --print-out-paths \
		'.#nixosConfigurations.nixOS.config.system.path' 2>"$BATS_TEST_TMPDIR/build.err"); then
		cat "$BATS_TEST_TMPDIR/build.err"
		return 1
	fi

	for desktop in "$system_path"/share/applications/*.desktop; do
		provider=$(readlink "$desktop") || continue
		[[ $provider == /nix/store/*-firejail-wrapped-binaries/* ||
			$provider == /nix/store/*-sandboxed-app-icons/* ]] || continue
		if grep -E '^(Try)?Exec=' "$desktop" |
			grep -oE '/nix/store/[^[:space:]"]+' |
			grep -qvE '^/nix/store/[0-9a-z]{32}-firejail-wrapped-binaries/bin/'; then
			offenders+=("${desktop##*/}")
		fi
	done

	if ((${#offenders[@]} > 0)); then
		printf 'runs a store path outside firejail: %s\n' "${offenders[@]}"
		return 1
	fi
}
