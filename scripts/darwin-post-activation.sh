#!/bin/sh
# Post-activation hooks for macOS machines.
# Called by nix-darwin's system.activationScripts.postActivation.
# Runs as root during darwin-rebuild switch.
#
# Keep this file minimal: prefer declarative nix-darwin/Home Manager options.

# Login screen: show the keyboard input menu so the layout tracks the last
# logged-in user rather than the system default.
/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow ShowInputMenu -bool true
