# Helpers shared by the per-package updaters in this directory.
#
# An updater sources this file, defines two functions, and calls run_update:
#
#   latest_version      prints the newest upstream version in pkgver form
#   checksums VERSION   prints "<checksum-array> <sha256>" for every array to
#                       rewrite; returns non-zero if any hash is unavailable
#
# Exit status of run_update:
#   0   up to date
#   10  PKGBUILD and .SRCINFO bumped
#   11  out of date but not bumped (check-only mode, or checksums unavailable)
#   *   error
#
# Only the first element of a checksum array is rewritten, which must start on
# the assignment line, e.g. sha256sums=('...' or sha256sums_x86_64=('...').

set -euo pipefail

UPDATE_ROOT=${UPDATE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}

fail() {
  echo "${PKG:-update}: $*" >&2
  exit 1
}

# Prints the tag of the newest non-prerelease GitHub release of OWNER/REPO.
github_latest_tag() {
  local url
  url=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest") || return 1
  [[ $url == */releases/tag/* ]] || return 1
  echo "${url##*/releases/tag/}"
}

# Prints the sha256 of the content at URL.
sha256_of() {
  local sum
  sum=$(curl -fsSL "$1" | sha256sum) || return 1
  echo "${sum%% *}"
}

# Prints the sha256 published at URL in sha256sum format.
upstream_sha256() {
  local sum
  sum=$(curl -fsSL "$1") || return 1
  sum=${sum%%[[:space:]]*}
  [[ $sum =~ ^[0-9a-f]{64}$ ]] || return 1
  echo "$sum"
}

# pkgbuild_var FILE NAME: prints the value of a simple NAME=value assignment.
pkgbuild_var() {
  sed -n "s/^$2=['\"]\{0,1\}\([^'\"]*\).*/\1/p" "$1" | head -1
}

# set_pkgbuild_var FILE NAME VALUE
set_pkgbuild_var() {
  sed -i "s|^$2=.*|$2=$3|" "$1"
}

# set_checksum FILE ARRAY SHA256: sets the first element of ARRAY; fails if
# ARRAY does not start with a quoted hex checksum on its assignment line.
set_checksum() {
  grep -q "^$2=('[0-9a-f]*'" "$1" || return 1
  sed -i "s/^$2=('[0-9a-f]*'/$2=('$3'/" "$1"
}

run_update() {
  local check_only=0
  [[ ${1:-} == -n ]] && check_only=1

  PKG=${PKG:-$(basename "${BASH_SOURCE[1]}" .sh)}
  local dir=$UPDATE_ROOT/$PKG
  [[ -f $dir/PKGBUILD ]] || fail "no PKGBUILD in $dir"

  local current latest sums
  current=$(pkgbuild_var "$dir/PKGBUILD" pkgver)
  latest=$(latest_version) || fail "cannot determine latest upstream version"
  [[ $latest =~ ^[0-9][0-9A-Za-z._+]*$ ]] || fail "unusable upstream version '$latest'"

  if (($(vercmp "$latest" "$current") <= 0)); then
    echo "$PKG: up to date ($current)"
    return 0
  fi
  if ((check_only)); then
    echo "$PKG: out of date ($current -> $latest)"
    return 11
  fi
  if ! sums=$(checksums "$latest"); then
    echo "$PKG: out of date ($current -> $latest); checksums unavailable, not bumped"
    return 11
  fi

  local work array sum
  work=$(mktemp -d)
  trap 'rm -rf "$work"' RETURN
  cp -a "$dir/." "$work/"
  set_pkgbuild_var "$work/PKGBUILD" pkgver "$latest"
  set_pkgbuild_var "$work/PKGBUILD" pkgrel 1
  while read -r array sum; do
    set_checksum "$work/PKGBUILD" "$array" "$sum" || fail "cannot rewrite $array"
  done <<<"$sums"
  (cd "$work" && makepkg --printsrcinfo >.SRCINFO) || fail "makepkg --printsrcinfo failed"

  cp "$work/PKGBUILD" "$work/.SRCINFO" "$dir/"
  echo "$PKG: bumped $current -> $latest"
  return 10
}
