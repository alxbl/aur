#!/usr/bin/env bash
# Offline tests for lib.sh and check-all.sh. Usage: update/test.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
lib=$here/lib.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
check() { # DESCRIPTION CONDITION-EXIT-STATUS
  if (($2 == 0)); then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failures=$((failures + 1))
  fi
}
rc_is() { [[ $rc == "$1" ]]; }

old=$(printf 'a%.0s' {1..64})
new=$(printf 'b%.0s' {1..64})

reset_fixture() {
  rm -rf "$tmp/root" && mkdir -p "$tmp/root/demo-bin"
  cat >"$tmp/root/demo-bin/PKGBUILD" <<EOF
pkgname=demo-bin
pkgver=1.0.0
pkgrel=3
pkgdesc='demo'
arch=('x86_64')
url='https://example.com'
license=('MIT')
source_x86_64=("demo-\${pkgver}::https://example.com/demo-\${pkgver}")
sha256sums_x86_64=('$old')
EOF
  cp "$tmp/root/demo-bin/PKGBUILD" "$tmp/original"
}

# run_stub LATEST|FAIL SUMS [run_update args]: runs run_update with stubbed upstream.
run_stub() {
  local stub_latest=$1 stub_sums=$2
  shift 2
  (
    export PKG=demo-bin UPDATE_ROOT=$tmp/root
    source "$lib"
    latest_version() { [[ $stub_latest != FAIL ]] && echo "$stub_latest"; }
    checksums() { [[ -n $stub_sums ]] && printf '%s\n' "$stub_sums"; }
    run_update "$@"
  ) >"$tmp/out" 2>&1
}
unchanged() { cmp -s "$tmp/root/demo-bin/PKGBUILD" "$tmp/original"; }
pkgbuild_has() { grep -q "$1" "$tmp/root/demo-bin/PKGBUILD"; }

reset_fixture
run_stub 1.0.0 ""; rc=$?
check "same version is up to date" "$(rc_is 0; echo $?)"
check "same version leaves PKGBUILD alone" "$(unchanged; echo $?)"

reset_fixture
run_stub 0.9.0 ""; rc=$?
check "older upstream is up to date" "$(rc_is 0; echo $?)"

reset_fixture
run_stub 1.1.0 "sha256sums_x86_64 $new"; rc=$?
check "new version is bumped (exit 10)" "$(rc_is 10; echo $?)"
check "bump sets pkgver" "$(pkgbuild_has '^pkgver=1.1.0$'; echo $?)"
check "bump resets pkgrel" "$(pkgbuild_has '^pkgrel=1$'; echo $?)"
check "bump sets checksum" "$(pkgbuild_has "^sha256sums_x86_64=('$new')\$"; echo $?)"
check "bump regenerates .SRCINFO" "$(grep -q "pkgver = 1.1.0" "$tmp/root/demo-bin/.SRCINFO" && grep -q "$new" "$tmp/root/demo-bin/.SRCINFO"; echo $?)"

reset_fixture
run_stub 1.1.0 ""; rc=$?
check "unavailable checksums flag out of date (exit 11)" "$(rc_is 11; echo $?)"
check "unavailable checksums leave PKGBUILD alone" "$(unchanged; echo $?)"

reset_fixture
run_stub 1.1.0 "sha256sums_x86_64 $new" -n; rc=$?
check "-n flags out of date (exit 11)" "$(rc_is 11; echo $?)"
check "-n leaves PKGBUILD alone" "$(unchanged; echo $?)"

reset_fixture
run_stub v1.2-3 "sha256sums_x86_64 $new"; rc=$?
check "unusable upstream version is an error" "$(rc_is 1; echo $?)"

reset_fixture
run_stub FAIL ""; rc=$?
check "failed version lookup is an error" "$(rc_is 1; echo $?)"

reset_fixture
run_stub 1.1.0 "sha256sums_aarch64 $new"; rc=$?
check "unknown checksum array is an error" "$(rc_is 1; echo $?)"
check "unknown checksum array leaves PKGBUILD alone" "$(unchanged; echo $?)"

# Files next to the PKGBUILD (install scripts) are available to makepkg.
reset_fixture
echo 'post_install() { :; }' >"$tmp/root/demo-bin/demo-bin.install"
echo "install=demo-bin.install" >>"$tmp/root/demo-bin/PKGBUILD"
run_stub 1.1.0 "sha256sums_x86_64 $new"; rc=$?
check "package with an install file is bumped (exit 10)" "$(rc_is 10; echo $?)"
check "install file is left in place" "$([[ -f $tmp/root/demo-bin/demo-bin.install ]]; echo $?)"

# Multi-element checksum arrays: only the first element is rewritten.
reset_fixture
other=$(printf 'c%.0s' {1..64})
sed -i "s|^source_x86_64=.*|source_x86_64=(\"demo-\${pkgver}::https://example.com/demo-\${pkgver}\" 'launcher')|; /^sha256sums_x86_64=/d" "$tmp/root/demo-bin/PKGBUILD"
printf "sha256sums_x86_64=('%s'\n                   '%s')\n" "$old" "$other" >>"$tmp/root/demo-bin/PKGBUILD"
run_stub 1.1.0 "sha256sums_x86_64 $new"; rc=$?
check "multi-element array bump succeeds (exit 10)" "$(rc_is 10; echo $?)"
check "multi-element array: first element rewritten" "$(pkgbuild_has "^sha256sums_x86_64=('$new'\$"; echo $?)"
check "multi-element array: later elements untouched" "$(pkgbuild_has "^ *'$other')\$"; echo $?)"

# check-all.sh
setup_tree() { # RC-OF-DEMO-UPDATER
  rm -rf "$tmp/tree" && mkdir -p "$tmp/tree/update" "$tmp/tree/demo-bin" "$tmp/tree/other-bin"
  cp "$here/check-all.sh" "$tmp/tree/update/"
  touch "$tmp/tree/demo-bin/PKGBUILD" "$tmp/tree/other-bin/PKGBUILD"
  for pkg in demo-bin other-bin; do
    printf '#!/usr/bin/env bash\necho "%s ran"\nexit %s\n' "$pkg" "${1:-0}" >"$tmp/tree/update/$pkg.sh"
    chmod +x "$tmp/tree/update/$pkg.sh"
  done
}
all() { "$tmp/tree/update/check-all.sh" "$@" >"$tmp/out" 2>&1; }

setup_tree 0
all; rc=$?
check "check-all: all up to date exits 0" "$(rc_is 0; echo $?)"
setup_tree 10
all; rc=$?
check "check-all: bumped exits 0" "$(rc_is 0; echo $?)"
setup_tree 11
all; rc=$?
check "check-all: out of date exits 2" "$(rc_is 2; echo $?)"
setup_tree 3
all; rc=$?
check "check-all: updater failure exits 1" "$(rc_is 1; echo $?)"
setup_tree 0
rm "$tmp/tree/update/other-bin.sh"
all; rc=$?
check "check-all: missing updater exits 1" "$(rc_is 1; echo $?)"
check "check-all: missing updater is named" "$(grep -q 'other-bin: missing updater' "$tmp/out"; echo $?)"
all demo-bin; rc=$?
check "check-all: explicit package skips others" "$(rc_is 0; echo $?)"

((failures == 0)) && echo "all tests passed" || echo "$failures test(s) failed"
exit $((failures > 0))
