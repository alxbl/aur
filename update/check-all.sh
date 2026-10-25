#!/usr/bin/env bash
# Runs the updater of every package, bumping those that can be bumped.
# Usage: check-all.sh [-n] [PACKAGE...]
#   -n  only report out-of-date packages; change nothing
#
# Exit status: 1 if an updater is missing or failed, else 2 if a package is
# out of date and was not bumped, else 0.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")

flags=()
if [[ ${1:-} == -n ]]; then
  flags=(-n)
  shift
fi

packages=("$@")
if ((${#packages[@]} == 0)); then
  for pkgbuild in "$root"/*/PKGBUILD; do
    [[ -e $pkgbuild ]] && packages+=("$(basename "$(dirname "$pkgbuild")")")
  done
fi

errors=0 outdated=0 bumped=0
for pkg in "${packages[@]}"; do
  updater=$here/$pkg.sh
  if [[ ! -x $updater ]]; then
    echo "$pkg: missing updater update/$pkg.sh" >&2
    errors=$((errors + 1))
    continue
  fi
  "$updater" "${flags[@]}"
  case $? in
    0) ;;
    10) bumped=$((bumped + 1)) ;;
    11) outdated=$((outdated + 1)) ;;
    *)
      echo "$pkg: updater failed" >&2
      errors=$((errors + 1))
      ;;
  esac
done

echo "bumped: $bumped, out of date: $outdated, errors: $errors"
((errors)) && exit 1
((outdated)) && exit 2
exit 0
