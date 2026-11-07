#!/usr/bin/env bash
# Updater for fgj-bin.
# Usage: fgj-bin.sh [-n]
source "$(dirname "$0")/lib.sh"

base=https://code.segfault.me/alxbl/fgj

latest_version() {
  local release tag
  release=$(curl -fsS "https://code.segfault.me/api/v1/repos/alxbl/fgj/releases/latest") || return 1
  tag=$(grep -o '"tag_name":"v[0-9][^"]*"' <<<"$release" | head -1) || return 1
  tag=${tag#\"tag_name\":\"v}
  echo "${tag%\"}"
}

# The release publishes the checksum of the archive next to it.
checksums() {
  local sum
  sum=$(upstream_sha256 "$base/releases/download/v$1/fgj-$1-x86_64-linux.tar.gz.sha256") || return 1
  echo "sha256sums_x86_64 $sum"
}

run_update "$@"
