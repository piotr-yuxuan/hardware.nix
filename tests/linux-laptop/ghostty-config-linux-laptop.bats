#!/usr/bin/env bats
# Tests for the Ghostty configuration assembled by home/linux-laptop.nix.
#
# home/linux-laptop.nix writes the Ghostty config via xdg.configFile."ghostty/config",
# which resolves to $XDG_CONFIG_HOME/ghostty/config (~/.config/ghostty/config).
# On linux-laptop, Ghostty is installed as a Nix package (pkgs.ghostty is not broken
# on Linux) via programs.ghostty.enable = true with no package = null override.
# The Home Manager module wires up bash and zsh shell integration and writes the
# config via xdg.configFile.
#
# The platform-specific suffix appended on linux-laptop is:
#   \nfont-size = 11\n
# where 11 comes from the monoFontSize let-binding in home/linux-laptop.nix.
#
# These tests verify the content contract of the assembled config: the shared
# base is included verbatim, the linux-laptop font-size suffix is appended, and the
# file format is valid Ghostty key = value syntax.
#
# No Home Manager activation is run; we test the text directly.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
BASE_CONFIG="$REPO_ROOT/config/ghostty/config"
MONO_FONT_SIZE=11

# Assemble the same string that home/linux-laptop.nix produces.
# home/linux-laptop.nix: (lib.fileContents ../config/ghostty/config)
#                  + "\nfont-size = ${toString monoFontSize}\n"
assembled_config() {
    printf '%s\nfont-size = %s\n' "$(cat "$BASE_CONFIG")" "$MONO_FONT_SIZE"
}

# ---------------------------------------------------------------------------
# Base config is included
# ---------------------------------------------------------------------------

@test "linux-laptop assembled config contains font-family from base" {
    [[ $(assembled_config) == *"font-family = IosevkaTerm Nerd Font Mono"* ]]
}

@test "linux-laptop assembled config contains ANSI palette from base" {
    [[ $(assembled_config) == *"palette = 0=#252525"* ]]
}

@test "linux-laptop assembled config contains all 16 palette entries" {
    local count
    count=$(assembled_config | grep -c "^palette = ")
    [[ $count -eq 16 ]]
}

@test "linux-laptop assembled config contains cursor settings from base" {
    [[ $(assembled_config) == *"cursor-color = #00BACD"* ]]
    [[ $(assembled_config) == *"cursor-style-blink = false"* ]]
}

# ---------------------------------------------------------------------------
# Platform suffix is appended
# ---------------------------------------------------------------------------

@test "linux-laptop assembled config contains font-size = 11" {
    [[ $(assembled_config) == *"font-size = 11"* ]]
}

@test "linux-laptop font-size suffix appears after base config" {
    local full suffix_line_no base_line_no
    full=$(assembled_config)
    base_line_no=$(echo "$full" | grep -n "palette = 15=" | cut -d: -f1)
    suffix_line_no=$(echo "$full" | grep -n "^font-size = 11$" | cut -d: -f1)
    [[ -n $base_line_no && -n $suffix_line_no ]]
    [[ $suffix_line_no -gt $base_line_no ]]
}

@test "linux-laptop config does not contain macOS font-size = 22" {
    # Ensure the macOS suffix was not accidentally included.
    ! assembled_config | grep -q "^font-size = 22$"
}

# ---------------------------------------------------------------------------
# File format is valid Ghostty key = value syntax
# ---------------------------------------------------------------------------

@test "linux-laptop no line in assembled config contains Nix-style interpolation" {
    ! assembled_config | grep -q '\${'
}

@test "linux-laptop no line contains backslash-n escape sequences" {
    ! assembled_config | grep -qF '\n'
}

@test "linux-laptop every non-blank non-comment line contains an equals sign" {
    assembled_config | grep -v '^#' | grep -v '^[[:space:]]*$' | while IFS= read -r line; do
        [[ $line == *"="* ]] || { echo "Line without '=': $line" >&2; return 1; }
    done
}

# ---------------------------------------------------------------------------
# Config file path: XDG is canonical on Linux
# ---------------------------------------------------------------------------

@test "linux-laptop xdg configFile path resolves to ~/.config/ghostty/config" {
    # On Linux, XDG_CONFIG_HOME defaults to ~/.config.
    # xdg.configFile."ghostty/config" therefore writes to
    # ~/.config/ghostty/config -- the same as home.file.".config/ghostty/config".
    local xdg_path home_file_path
    xdg_path="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
    home_file_path="$HOME/.config/ghostty/config"
    [[ $xdg_path == "$home_file_path" ]]
}

@test "linux-laptop base config file exists in the repository" {
    [[ -f $BASE_CONFIG ]]
}

@test "linux-laptop base config does not contain font-size (injected per platform)" {
    ! grep -q "^font-size" "$BASE_CONFIG"
}
