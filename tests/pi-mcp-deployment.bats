#!/usr/bin/env bats
# Verify the Pi MCP adapter and server configuration in the realised
# nixOS Home Manager generation.

load 'helpers/isolation'

setup_file() {
	cd "$BATS_TEST_DIRNAME/.." || return 1
	if ! out=$(nix build --no-link --print-out-paths \
		'.#nixosConfigurations.nixOS.config.home-manager.users.example.home.activationPackage' \
		2>/dev/null); then
		export MCP_BUILD_DISABLED=1
		return 0
	fi

	export OUT="$out"
	export MCP_CONFIG="$OUT/home-files/.config/mcp/mcp.json"
	export MCP_ADAPTER="$OUT/home-files/.pi/agent/extensions/pi-mcp-adapter"
}

require_build() {
	if [[ ${MCP_BUILD_DISABLED:-0} == 1 ]]; then
		skip "nix build unavailable or not writable in this environment"
	fi
}

setup() { isolation_setup; }
teardown() { isolation_teardown; }

@test "Pi MCP adapter deploys with its runtime dependencies" {
	require_build
	[[ -f $MCP_ADAPTER/index.ts ]]
	[[ -d $MCP_ADAPTER/node_modules/@modelcontextprotocol/client ]]
	[[ -x $OUT/home-path/bin/python3 ]]
	[[ -x $OUT/home-path/bin/socat ]]
}

@test "MCP configuration declares only the selected servers" {
	require_build
	run jq -r '.mcpServers | keys | sort | join(",")' "$MCP_CONFIG"
	[[ $status -eq 0 ]]
	[[ $output == "aws-knowledge,clojure-mcp,emacs-tools" ]]
}

@test "AWS Knowledge is direct while other MCP servers use the proxy" {
	require_build
	run jq -e '
		.settings.directTools == false and
		.mcpServers["aws-knowledge"].directTools == true and
		(.mcpServers["clojure-mcp"] | has("directTools") | not) and
		(.mcpServers["emacs-tools"] | has("directTools") | not)
	' "$MCP_CONFIG"
	[[ $status -eq 0 ]]
}

@test "all MCP servers use lazy lifecycle" {
	require_build
	run jq -e '[.mcpServers[].lifecycle] | all(. == "lazy")' "$MCP_CONFIG"
	[[ $status -eq 0 ]]
}

@test "Emacs MCP uses socat to bridge the configured Unix socket" {
	require_build
	run jq -e '
		.mcpServers["emacs-tools"].command == "sh" and
		.mcpServers["emacs-tools"].args == [
			"-c",
			"exec socat - \"UNIX-CONNECT:$HOME/.emacs.d/var/mcp-server/emacs-mcp-server.sock\""
		] and
		(.mcpServers["emacs-tools"] | has("url") | not)
	' "$MCP_CONFIG"
	[[ $status -eq 0 ]]
}
