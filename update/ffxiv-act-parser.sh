#!/usr/bin/env bash
# Updater for ffxiv-act-parser.
# Usage: ffxiv-act-parser.sh [-n]
source "$(dirname "$0")/lib.sh"

latest_version() {
  github_latest_tag ravahn/FFXIV_ACT_Plugin
}

# Upstream publishes no checksum, so the release zip is hashed as fetched.
checksums() {
  local zip
  zip=$(sha256_of "https://github.com/ravahn/FFXIV_ACT_Plugin/releases/download/$1/FFXIV_ACT_Plugin_$1.zip") || return 1
  echo "sha256sums $zip"
}

run_update "$@"
