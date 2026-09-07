#!/usr/bin/env bash
# shellcheck disable=SC2154
# Variable avatar_src is set by the Nix wrapper.

mkdir -p /var/lib/AccountsService/icons
cp "$avatar_src" /var/lib/AccountsService/icons/example
chmod 0644 /var/lib/AccountsService/icons/example
