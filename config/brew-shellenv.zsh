# Initialise Homebrew into the shell environment.
# nix-darwin's set-environment overwrites PATH before macOS path_helper runs, so
# /opt/homebrew/bin is not on PATH at profile time. Reference the binary by its
# absolute path instead of relying on command -v.
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
