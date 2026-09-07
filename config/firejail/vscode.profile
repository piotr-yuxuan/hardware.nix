# VSCode: built-in Electron profile with project directory whitelist.
#
# The shipped code.profile already ignores devel/exec/interpreter
# restrictions (needed by an IDE) and uses electron-common.profile
# for proper Electron sandboxing.
#
# private-bin (from electron-common.profile) is incompatible with
# NixOS (Nix store paths are not in the locations firejail searches).
ignore private-bin

# Project directories visible inside the sandbox.
# The shipped profile noblacklists ~/.config/Code and ~/.vscode but
# does not whitelist them (it is designed without whitelist mode).
# Because we activate whitelist mode below, we must explicitly
# whitelist everything VS Code needs.
whitelist ${HOME}/.config/Code
whitelist ${HOME}/.vscode

noblacklist ${HOME}/OSX-KVM
whitelist ${HOME}/OSX-KVM

noblacklist ${HOME}/src
whitelist ${HOME}/src

# ~/src points here on linux-laptop.  Keep the canonical path available when a
# project is opened without going through the symlink.
noblacklist ${HOME}/Dropbox (Maestral)/Example/src
whitelist ${HOME}/Dropbox (Maestral)/Example/src

# linux-laptop permits unprivileged user namespaces, so use Firejail's supported
# Electron hardening: drop all capabilities, enable nonewprivs and seccomp,
# and restrict the protocol families available to VS Code.
include electron-common-hardened.inc.profile

include code.profile
