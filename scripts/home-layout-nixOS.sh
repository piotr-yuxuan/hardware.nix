#!/usr/bin/env bash
# Linux-specific (nixOS) HOME directory layout additions.
#
# Sourced as a Home Manager activation snippet on every switch.
# Must run after the cross-platform home-layout.sh (ensured by entryAfter
# ["homeLayout"] in home/nixOS.nix).
# $DRY_RUN_CMD is provided by Home Manager.

DROPBOX="$HOME/Dropbox (Maestral)/example"

# mov -> Videos (XDG standard video directory; macOS uses Movies).
[[ -e $HOME/mov || -L $HOME/mov ]] || $DRY_RUN_CMD ln -s "$HOME/Videos" "$HOME/mov"

# redirect_to_dropbox TARGET LINK [AUTO_SUBDIR...]
#
# Replace LINK (a plain directory) with a symlink to the Dropbox-backed
# TARGET.  Before attempting the replacement, any listed AUTO_SUBDIR names
# are removed if they are empty directories created by the cross-platform
# layout script.  The function is a no-op when:
#   - LINK is already a symlink,
#   - TARGET does not exist yet (Maestral not yet synced).
# It warns and skips when LINK is non-empty after the cleanup step.
redirect_to_dropbox() {
	local target=$1
	local link=$2
	shift 2
	local subs=("$@")

	[[ -L $link ]] && return 0   # already redirected
	[[ -d $target ]] || return 0 # Dropbox not yet synced

	if [[ -d $link ]]; then
		# Remove known empty auto-seeded subdirectories.
		for sub in "${subs[@]}"; do
			if [[ -d $link/$sub && -z $(ls -A "$link/$sub" 2>/dev/null) ]]; then
				$DRY_RUN_CMD rmdir "$link/$sub"
			fi
		done
		if [[ -z $(ls -A "$link" 2>/dev/null) ]]; then
			$DRY_RUN_CMD rmdir "$link"
			$DRY_RUN_CMD ln -s "$target" "$link"
		else
			echo "home-layout: $link is non-empty; skipping Dropbox redirect" >&2
		fi
	elif [[ ! -e $link ]]; then
		$DRY_RUN_CMD ln -s "$target" "$link"
	fi
}

# Standard XDG user directories -> Dropbox counterparts.
# Documents/Pictures/etc. on macOS live in Dropbox under the same names;
# Videos maps to Movies (macOS Dropbox convention).
redirect_to_dropbox "$DROPBOX/Documents" "$HOME/Documents"
redirect_to_dropbox "$DROPBOX/Downloads" "$HOME/Downloads"
redirect_to_dropbox "$DROPBOX/Music" "$HOME/Music"
redirect_to_dropbox "$DROPBOX/Pictures" "$HOME/Pictures" screenshots
redirect_to_dropbox "$DROPBOX/Movies" "$HOME/Videos"

# ~/src -> Dropbox-backed source tree.
# The cross-platform script may have seeded an empty github.com/ placeholder;
# redirect_to_dropbox removes it automatically before replacing ~/src.
redirect_to_dropbox "$DROPBOX/src" "$HOME/src" github.com

# Pictures/Screenshots -> screenshots
#
# GNOME Screenshot writes to ~/Pictures/Screenshots (capital S); the
# cross-platform layout script seeds ~/Pictures/screenshots (lowercase).
# A case-insensitive symlink bridges the two on the case-sensitive Linux FS.
if [[ -d $HOME/Pictures/screenshots && ! -e $HOME/Pictures/Screenshots ]]; then
	$DRY_RUN_CMD ln -s screenshots "$HOME/Pictures/Screenshots"
fi

# Transmission download directory.
# Firejail whitelists only this directory so torrents cannot scatter
# files across ~.  The path resolves through ~/net -> ~/Downloads
# (possibly Dropbox-backed).
[[ -d $HOME/net/transmission ]] || $DRY_RUN_CMD mkdir -p "$HOME/net/transmission"
