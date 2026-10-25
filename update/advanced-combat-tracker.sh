#!/usr/bin/env bash
# Updater for advanced-combat-tracker.
# Usage: advanced-combat-tracker.sh [-n]
source "$(dirname "$0")/lib.sh"

latest_version() {
  github_latest_tag EQAditu/AdvancedCombatTracker
}

# Upstream publishes no checksum, so the release zip is hashed as fetched.
# Only the zip's checksum, the first element, is rewritten.
checksums() {
  local zip
  zip=$(sha256_of "https://github.com/EQAditu/AdvancedCombatTracker/releases/download/$1/ACTv3.zip") || return 1
  echo "sha256sums $zip"
}

run_update "$@"
