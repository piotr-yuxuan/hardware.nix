#!/usr/bin/env bats
# shellcheck disable=SC2154  # tmpdir is set by isolation_setup before any test body runs
# Verify configuration generated for the macOS host that no evaluation
# check covers: the work and personal Git identities, the delta pager,
# the activation snippets, the staleness agent environment, the
# garbage-collection daemon and the trusted Nix users.
#
# The values come from one `nix eval` of darwinConfigurations.macOS, which
# is the Mac template (templates/macOS) evaluated against this checkout,
# placeholders included. It works on Linux too. Git only runs against temporary repositories with
# the generated configuration as its isolated global configuration.

load '../helpers/isolation'

PERSONAL_DIR_CONDITION='gitdir:~/src/github.com/piotr-yuxuan/'
PERSONAL_EMAIL='piotr-yuxuan@users.noreply.github.com'

setup_file() {
	cd "$BATS_TEST_DIRNAME/../.." || return 1
	export REPO_ROOT="$PWD"
	export EVAL_JSON="$BATS_FILE_TMPDIR/darwin.json"
	# The single-quoted text is a Nix expression; ${...} is Nix syntax.
	# shellcheck disable=SC2016
	if ! nix eval --no-write-lock-file --json '.#darwinConfigurations.macOS' --apply '
		c: let
		  hm = c.config.home-manager.users.${c.config.system.primaryUser};
		  personal = builtins.filter
		    (i: i.condition == "'"$PERSONAL_DIR_CONDITION"'")
		    hm.programs.git.includes;
		in {
		  gitconfig = hm.xdg.configFile."git/config".text;
		  personal = if personal == [] then ""
		    else c.pkgs.lib.generators.toGitINI (builtins.head personal).contents;
		  sshConfig = hm.home.file.".ssh/config".text;
		  home = hm.home.homeDirectory;
		  nhFlake = hm.launchd.agents.nix-staleness-check.config.EnvironmentVariables.NH_FLAKE or "";
		  brewBundle = hm.home.activation.brewBundle.data;
		  defaultApps = hm.home.activation.defaultApps.data;
		  userAgents = builtins.concatStringsSep " " (builtins.attrNames c.config.launchd.user.agents);
		  nhDaemonPath = c.config.launchd.daemons.nh-clean.serviceConfig.EnvironmentVariables.PATH or "";
		  nhDaemonLog = c.config.launchd.daemons.nh-clean.serviceConfig.StandardOutPath or "";
		  nhDaemonErrLog = c.config.launchd.daemons.nh-clean.serviceConfig.StandardErrorPath or "";
		  trustedUsers = builtins.concatStringsSep " " c.config.nix.settings.trusted-users;
		}' >"$EVAL_JSON" 2>/dev/null </dev/null; then
		export EVAL_DISABLED=1
	fi
}

require_eval() {
	if [[ ${EVAL_DISABLED:-0} == 1 ]]; then
		skip "nix eval of darwinConfigurations.macOS unavailable"
	fi
}

field() { jq -r --arg k "$1" '.[$k]' "$EVAL_JSON"; }

# git_in DIR ARGS...: run git in DIR with the generated configuration,
# the personal include file substituted for its unbuilt store path.
# It reads GIT_HOME, not tmpdir: bats' own `run` shadows a variable
# named tmpdir.
git_in() {
	local dir="$1"
	shift
	env HOME="$GIT_HOME" GIT_CONFIG_GLOBAL="$GIT_HOME/gitconfig" GIT_CONFIG_NOSYSTEM=1 \
		git -C "$dir" "$@" </dev/null
}

setup() {
	isolation_setup
	export GIT_HOME="$tmpdir"
	if [[ ${EVAL_DISABLED:-0} != 1 ]]; then
		field personal >"$tmpdir/personal.inc"
		field gitconfig |
			sed "s|\"/nix/store/[^\"]*-hm_gitconfig\"|\"$tmpdir/personal.inc\"|" \
				>"$tmpdir/gitconfig"
		mkdir -p "$tmpdir/src/github.com/piotr-yuxuan/p" "$tmpdir/src/github.com/corp/w"
		git_in "$tmpdir/src/github.com/piotr-yuxuan/p" init -q
		git_in "$tmpdir/src/github.com/corp/w" init -q
	fi
}
teardown() { isolation_teardown; }

@test "personal repositories get the personal identity, signing and SSH key" {
	require_eval
	local p="$tmpdir/src/github.com/piotr-yuxuan/p"
	[[ $(git_in "$p" config user.email) == "$PERSONAL_EMAIL" ]]
	[[ $(git_in "$p" config commit.gpgSign) == true ]]
	[[ $(git_in "$p" config tag.gpgSign) == true ]]
	[[ -n $(git_in "$p" config user.signingKey) ]]
	[[ $(git_in "$p" config core.sshCommand) == *"-i ~/.ssh/${PERSONAL_EMAIL}_ed25519"* ]]
	[[ $(git_in "$p" config core.sshCommand) == *"IdentitiesOnly=yes"* ]]
}

@test "a symlink into the personal directory also gets the personal identity" {
	require_eval
	ln -s "$tmpdir/src/github.com/piotr-yuxuan/p" "$tmpdir/.emacs.d"
	[[ $(git_in "$tmpdir/.emacs.d" config user.email) == "$PERSONAL_EMAIL" ]]
}

@test "work repositories refuse to commit until the work identity is set" {
	require_eval
	local w="$tmpdir/src/github.com/corp/w"
	run git_in "$w" config user.name
	[[ $status -ne 0 ]]
	run git_in "$w" config user.email
	[[ $status -ne 0 ]]
	run git_in "$w" commit -q --allow-empty -m test
	[[ $status -ne 0 ]]
	[[ $output == *"was given and auto-detection is disabled"* ]]
}

@test "work repositories are not signed with the personal key" {
	require_eval
	local w="$tmpdir/src/github.com/corp/w"
	run git_in "$w" config user.signingKey
	[[ $status -ne 0 ]]
	run git_in "$w" config core.sshCommand
	[[ $status -ne 0 ]]
}

@test "ssh offers no host-specific key for github.com" {
	require_eval
	[[ $(field sshConfig) != *"Host github.com"* ]]
}

@test "the Brewfile activation installs this repository's Brewfile" {
	require_eval
	local brewfile
	brewfile=$(field brewBundle | sed -n 's/^BREWFILE=\([^ ]*\) bash .*/\1/p')
	[[ -n $brewfile ]]
	cmp "$brewfile" "$REPO_ROOT/config/Brewfile"
}

@test "the default-apps activation gives its script duti" {
	require_eval
	[[ $(field defaultApps) =~ ^DUTI_BIN=/nix/store/[a-z0-9]{32}-duti-[^/]*/bin/duti\ bash\ /nix/store/[a-z0-9]{32}-set-macos-defaults\.sh$ ]]
}

@test "git pages and filters interactive staging through delta" {
	require_eval
	run git config --file "$GIT_HOME/gitconfig" --get pager.diff
	[[ $output == /nix/store/*-delta-*/bin/delta ]]
	run git config --file "$GIT_HOME/gitconfig" --get interactive.diffFilter
	[[ $output == /nix/store/*-delta-*/bin/delta\ --color-only ]]
}

@test "nh clean is a root daemon with nix on its PATH, logging outside /tmp" {
	require_eval
	[[ -z $(field userAgents) ]]
	[[ :$(field nhDaemonPath): == *:/run/current-system/sw/bin:* ]]
	[[ $(field nhDaemonLog) == /var/log/* ]]
	[[ $(field nhDaemonErrLog) == /var/log/* ]]
}

@test "only root is a trusted Nix user" {
	require_eval
	[[ $(field trustedUsers) == root ]]
}

@test "the staleness agent points at the documented directory of the Mac's flake" {
	require_eval
	[[ $(field nhFlake) == "$(field home)/src/local/macOS" ]]
}
