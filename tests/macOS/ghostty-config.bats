#!/usr/bin/env bats
# Tests for the Ghostty configuration assembled by home/macOS.nix.
#
# home/macOS.nix writes the Ghostty config via xdg.configFile."ghostty/config",
# which resolves to $XDG_CONFIG_HOME/ghostty/config (~/.config/ghostty/config).
# On macOS, Ghostty is installed via the Homebrew cask (config/Brewfile) rather
# than as a Nix package; pkgs.ghostty is marked broken on Darwin.  The Home
# Manager module is therefore invoked with package = null so that it wires up
# shell integration without adding the broken derivation to home.packages.
#
# These tests verify the content contract of the assembled config: that the
# shared base (config/ghostty/config) is included verbatim, that the
# platform-specific suffix is appended, and that the resulting text is suitable
# for Ghostty to read (key = value format, no Nix-specific syntax escaping).
#
# No Home Manager activation is run; we test the text directly to keep the
# suite fast and platform-agnostic.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
BASE_CONFIG="$REPO_ROOT/config/ghostty/config"

# Assemble the same string that home/macOS.nix produces.
assembled_config() {
    printf '%s\n# Platform\nfont-size = 22\nshell-integration = detect\n' \
        "$(cat "$BASE_CONFIG")"
}

# ---------------------------------------------------------------------------
# Base config is included
# ---------------------------------------------------------------------------

@test "assembled config contains font-family from base" {
    [[ $(assembled_config) == *"font-family = IosevkaTerm Nerd Font Mono"* ]]
}

@test "assembled config contains ANSI palette from base" {
    [[ $(assembled_config) == *"palette = 0=#252525"* ]]
}

@test "assembled config contains all 16 palette entries" {
    local count
    count=$(assembled_config | grep -c "^palette = ")
    [[ $count -eq 16 ]]
}

@test "assembled config contains cursor settings from base" {
    [[ $(assembled_config) == *"cursor-color = #00BACD"* ]]
    [[ $(assembled_config) == *"cursor-style-blink = false"* ]]
}

# ---------------------------------------------------------------------------
# Platform suffix is appended
# ---------------------------------------------------------------------------

@test "assembled config contains macOS font-size = 22" {
    [[ $(assembled_config) == *"font-size = 22"* ]]
}

@test "assembled config contains shell-integration = detect" {
    [[ $(assembled_config) == *"shell-integration = detect"* ]]
}

@test "platform suffix appears after base config" {
    local full suffix_line_no base_line_no
    full=$(assembled_config)
    # font-size line must come after the last palette entry
    base_line_no=$(echo "$full" | grep -n "palette = 15=" | cut -d: -f1)
    suffix_line_no=$(echo "$full" | grep -n "^font-size = 22$" | cut -d: -f1)
    [[ -n $base_line_no && -n $suffix_line_no ]]
    [[ $suffix_line_no -gt $base_line_no ]]
}

# ---------------------------------------------------------------------------
# File format is valid Ghostty key = value syntax
# ---------------------------------------------------------------------------

@test "no line in assembled config contains Nix-style interpolation" {
    # Nix interpolation ${ ... } must not appear in the rendered output
    ! assembled_config | grep -q '\${'
}

@test "no line contains backslash-n escape sequences" {
    # The config must have real newlines, not literal \n
    ! assembled_config | grep -qF '\n'
}

@test "every non-blank non-comment line contains an equals sign" {
    assembled_config | grep -v '^#' | grep -v '^[[:space:]]*$' | while IFS= read -r line; do
        [[ $line == *"="* ]] || { echo "Line without '=': $line" >&2; return 1; }
    done
}

# ---------------------------------------------------------------------------
# Config file path: XDG vs home.file equivalence
# ---------------------------------------------------------------------------

@test "xdg configFile path and home.file path resolve to the same location" {
    # Both xdg.configFile.\"ghostty/config\" and
    # home.file.\".config/ghostty/config\" write to ~/.config/ghostty/config.
    # This test documents the equivalence by asserting the path components.
    local xdg_path home_file_path
    xdg_path="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
    home_file_path="$HOME/.config/ghostty/config"
    [[ $xdg_path == "$home_file_path" ]]
}

@test "base config file exists in the repository" {
    [[ -f $BASE_CONFIG ]]
}

@test "base config does not contain font-size (moved to platform suffix)" {
    # font-size was removed from the shared base in commit 1b68833 and is now
    # injected per platform; the shared base must not contain it.
    ! grep -q "^font-size" "$BASE_CONFIG"
}
