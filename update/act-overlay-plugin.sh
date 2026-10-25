#!/usr/bin/env bash
# Updater for act-overlay-plugin.
# Usage: act-overlay-plugin.sh [-n]
source "$(dirname "$0")/lib.sh"

latest_version() {
  local tag
  tag=$(github_latest_tag OverlayPlugin/OverlayPlugin) || return 1
  echo "${tag#v}"
}

# Upstream publishes no checksum file, so the release zip is hashed as fetched.
checksums() {
  local zip
  zip=$(sha256_of "https://github.com/OverlayPlugin/OverlayPlugin/releases/download/v$1/OverlayPlugin-$1.zip") || return 1
  echo "sha256sums $zip"
}

run_update "$@"
