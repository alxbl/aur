#!/usr/bin/env bash
# Updater for istioctl-bin. Usage: istioctl-bin.sh [-n]
source "$(dirname "$0")/lib.sh"

latest_version() {
  github_latest_tag istio/istio
}

checksums() {
  local ver=$1 base=https://github.com/istio/istio/releases/download/$1
  local license amd64 arm64
  # Upstream publishes no checksum for LICENSE, so it is hashed as fetched.
  license=$(sha256_of "https://raw.githubusercontent.com/istio/istio/$ver/LICENSE") || return 1
  amd64=$(upstream_sha256 "$base/istioctl-$ver-linux-amd64.tar.gz.sha256") || return 1
  arm64=$(upstream_sha256 "$base/istioctl-$ver-linux-arm64.tar.gz.sha256") || return 1
  printf '%s %s\n' \
    sha256sums "$license" \
    sha256sums_x86_64 "$amd64" \
    sha256sums_aarch64 "$arm64"
}

run_update "$@"
