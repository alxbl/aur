#!/usr/bin/env bash
# Updater for fgj.
# Usage: fgj.sh [-n]
source "$(dirname "$0")/lib.sh"

latest_version() {
  local tags
  tags=$(curl -fsS 'https://code.segfault.me/api/v1/repos/alxbl/fgj/tags') || return 1
  grep -o '"name":"v[0-9][^"]*"' <<<"$tags" | sed 's/^"name":"v//; s/"$//' | sort -V | tail -1
}

# Upstream publishes no checksum file, so the tag archive is hashed as fetched.
checksums() {
  local tarball
  tarball=$(sha256_of "https://code.segfault.me/alxbl/fgj/archive/v$1.tar.gz") || return 1
  echo "sha256sums $tarball"
}

run_update "$@"
