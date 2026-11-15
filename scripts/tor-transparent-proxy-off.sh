#!/usr/bin/env bash
# nft comes from PATH.

# Remove the tor-transparent-proxy nftables table (both ip and ip6
# families), restoring normal routing.

nft delete table ip tor-transparent-proxy 2>/dev/null || true
nft delete table ip6 tor-transparent-proxy 2>/dev/null || true

echo "Tor transparent proxy disabled"
