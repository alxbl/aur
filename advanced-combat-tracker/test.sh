#!/usr/bin/env bash
# Offline tests for the advanced-combat-tracker launcher. Usage: test.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
launcher=$here/advanced-combat-tracker
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
check() { # DESCRIPTION EXIT-STATUS
  if (($2 == 0)); then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failures=$((failures + 1))
  fi
}
ok() { "$@" >/dev/null 2>&1; echo $?; }
out_has() { grep -qF -- "$1" "$tmp/out"; }

home=$tmp/home
prefix=$home/.xlcore/wineprefix
proc=$tmp/proc
share=$tmp/share

fake_wine() { # DIR: creates DIR/bin/{wine,wineserver}
  mkdir -p "$1/bin"
  printf '#!/bin/sh\necho "prefix=$WINEPREFIX fsync=${WINEFSYNC:-} esync=${WINEESYNC:-} server=$WINESERVER cwd=$PWD args=$*" >"$RECORD"\n' >"$1/bin/wine"
  printf '#!/bin/sh\n' >"$1/bin/wineserver"
  chmod +x "$1/bin/wine" "$1/bin/wineserver"
}

dotnet_reg() { # RELEASE-HEX
  printf 'WINE REGISTRY Version 2\n\n[Software\\\\Microsoft\\\\NET Framework Setup\\\\NDP\\\\v4\\\\Full] 1700000000\n"Install"=dword:00000001\n"Release"=dword:%s\n' "$1" >"$prefix/system.reg"
}

fake_server() { # PID EXE-DIR ENV... : a running wineserver
  local pid=$1 dir=$2
  shift 2
  mkdir -p "$proc/$pid"
  echo wineserver >"$proc/$pid/comm"
  printf '%s\0' "$@" >"$proc/$pid/environ"
  ln -sfn "$dir/bin/wineserver" "$proc/$pid/exe"
}

reset() { # SYNC-TYPE
  rm -rf "$home" "$proc" "$share"
  mkdir -p "$prefix/drive_c" "$proc" "$share/app" "$share/plugins/FFXIV_ACT_Plugin"
  fake_wine "$home/.xlcore/compatibilitytool/wine/wine-a"
  printf 'WineStartupType=Managed\nWineSyncType=%s\nWineBinaryPath=/usr/bin\n' "${1:-FSync}" >"$home/.xlcore/launcher.ini"
  dotnet_reg 00082348
  echo act >"$share/app/Advanced Combat Tracker.exe"
  echo plugin >"$share/plugins/FFXIV_ACT_Plugin/FFXIV_ACT_Plugin.dll"
  export RECORD=$tmp/record
  rm -f "$RECORD"
}

# in_launcher COMMAND...: runs a launcher function in a subshell, output in $tmp/out.
in_launcher() {
  (
    export HOME=$home PROC=$proc ACT_SHARE=$share
    unset ACT_PREFIX ACT_WINE
    source "$launcher"
    "$@"
  ) >"$tmp/out" 2>&1
}
detect() { detect_prefix && detect_wine && echo "WINE=$WINE SERVER=$WINESERVER SYNC=$SYNC"; }
wine_a=$home/.xlcore/compatibilitytool/wine/wine-a

# Prefix detection
reset; (
  export HOME=$home PROC=$proc; source "$launcher"; detect_prefix; echo "$PREFIX"
) >"$tmp/out" 2>&1
check "detects ~/.xlcore/wineprefix" "$(out_has "$prefix"; echo $?)"

reset; mkdir -p "$tmp/other"
(
  export HOME=$home PROC=$proc ACT_PREFIX=$tmp/other; source "$launcher"; detect_prefix; echo "$PREFIX"
) >"$tmp/out" 2>&1
check "ACT_PREFIX overrides detection" "$(out_has "$tmp/other"; echo $?)"

reset; rm -rf "$home/.xlcore"; mkdir -p "$home/.var/app/dev.goats.xivlauncher"
in_launcher detect_prefix; rc=$?
check "Flatpak XIVLauncher is rejected" "$((rc == 1 && $(out_has Flatpak; echo $?) == 0 ? 0 : 1))"

reset; rm -rf "$home/.xlcore"
in_launcher detect_prefix; rc=$?
check "no prefix is an error" "$((rc == 1 ? 0 : 1))"

# Wine detection
reset FSync
in_launcher detect
check "managed build and FSync from launcher.ini" "$(out_has "WINE=$wine_a/bin/wine SERVER=$wine_a/bin/wineserver SYNC=WINEFSYNC"; echo $?)"

reset ESync
in_launcher detect
check "ESync from launcher.ini" "$(out_has "SYNC=WINEESYNC"; echo $?)"

reset None
in_launcher detect
check "no sync variable when sync is off" "$(out_has "SYNC=
"; echo $?)"

reset
fake_wine "$home/.xlcore/compatibilitytool/wine/wine-b"
in_launcher detect; rc=$?
check "several managed builds is an error" "$((rc == 1 && $(out_has 'several managed'; echo $?) == 0 ? 0 : 1))"

reset
fake_wine "$tmp/custom"
printf 'WineStartupType=Custom\nWineSyncType=ESync\nWineBinaryPath=%s/bin\n' "$tmp/custom" >"$home/.xlcore/launcher.ini"
in_launcher detect
check "custom wine from WineBinaryPath" "$(out_has "WINE=$tmp/custom/bin/wine"; echo $?)"

reset
fake_wine "$tmp/running"
fake_server 4242 "$tmp/running" "WINEPREFIX=$prefix" WINEESYNC=1
in_launcher detect
check "follows the running wineserver's wine" "$(out_has "WINE=$tmp/running/bin/wine SERVER=$tmp/running/bin/wineserver"; echo $?)"
check "follows the running wineserver's sync" "$(out_has "SYNC=WINEESYNC"; echo $?)"

reset
fake_wine "$tmp/running"
fake_server 4242 "$tmp/running" "WINEPREFIX=$tmp/elsewhere" WINEESYNC=1
in_launcher detect
check "ignores a wineserver of another prefix" "$(out_has "WINE=$wine_a/bin/wine"; echo $?)"

reset
fake_wine "$tmp/override"
(
  export HOME=$home PROC=$proc ACT_WINE=$tmp/override/bin/wine; source "$launcher"; detect_prefix; detect_wine; echo "WINE=$WINE"
) >"$tmp/out" 2>&1
check "ACT_WINE overrides detection" "$(out_has "WINE=$tmp/override/bin/wine"; echo $?)"

# .NET check
reset; dotnet_reg 00082348
check ".NET 4.8 is accepted" "$(ok in_launcher bash -c "source '$launcher'; PREFIX='$prefix'; check_dotnet")"
reset; dotnet_reg 00070bf0
check ".NET 4.7.2 is rejected" "$((  $(ok in_launcher bash -c "source '$launcher'; PREFIX='$prefix'; check_dotnet") != 0 ? 0 : 1 ))"
reset; rm "$prefix/system.reg"
check "missing registry is rejected" "$((  $(ok in_launcher bash -c "source '$launcher'; PREFIX='$prefix'; check_dotnet") != 0 ? 0 : 1 ))"

# Linking
app=$prefix/drive_c/advanced-combat-tracker
plugin=$app/Plugins/FFXIV_ACT_Plugin
link() { in_launcher bash -c "source '$launcher'; PREFIX='$prefix'; link_files"; }
points_to() { [[ -L $1 && $(readlink "$1") == "$2" ]]; }
reset
link
check "ACT is linked to the package" "$(points_to "$app/Advanced Combat Tracker.exe" "$share/app/Advanced Combat Tracker.exe"; echo $?)"
check "plugins are linked to the package" "$(points_to "$plugin/FFXIV_ACT_Plugin.dll" "$share/plugins/FFXIV_ACT_Plugin/FFXIV_ACT_Plugin.dll"; echo $?)"
check "directories stay real" "$([[ -d $plugin && ! -L $plugin && ! -L $app ]]; echo $?)"
check "first link tells how to add the plugin" "$(out_has 'New plugin FFXIV_ACT_Plugin'; echo $?)"
link
check "second link stays quiet" "$([[ ! -s $tmp/out ]]; echo $?)"

echo changed >"$share/app/Advanced Combat Tracker.exe"
check "package changes show through the link" "$(grep -q changed "$app/Advanced Combat Tracker.exe"; echo $?)"

echo user >"$app/user.cfg"
echo new >"$share/plugins/FFXIV_ACT_Plugin/new.dll"
link
check "new package files are linked" "$(points_to "$plugin/new.dll" "$share/plugins/FFXIV_ACT_Plugin/new.dll"; echo $?)"
check "user files are kept" "$([[ -f $app/user.cfg && ! -L $app/user.cfg ]]; echo $?)"

echo written >"$plugin/written-by-plugin.dat"
rm "$share/plugins/FFXIV_ACT_Plugin/new.dll"
link
check "links to removed package files are pruned" "$([[ ! -e $plugin/new.dll && ! -L $plugin/new.dll ]]; echo $?)"
check "files written next to links are kept" "$([[ -f $plugin/written-by-plugin.dat ]]; echo $?)"

mkdir -p "$app/Plugins/UserPlugin"
echo mine >"$app/Plugins/UserPlugin/p.dll"
ln -s /elsewhere "$app/Plugins/UserPlugin/foreign-link"
rm "$plugin/written-by-plugin.dat"
rm -r "$share/plugins/FFXIV_ACT_Plugin"
link
check "plugins that are no longer packaged are removed" "$([[ ! -e $plugin && ! -L $plugin/FFXIV_ACT_Plugin.dll ]]; echo $?)"
check "plugins the package does not own are kept" "$([[ -f $app/Plugins/UserPlugin/p.dll ]]; echo $?)"
check "foreign links are kept" "$([[ -L $app/Plugins/UserPlugin/foreign-link ]]; echo $?)"

reset
mkdir -p "$app"
echo mine >"$app/Advanced Combat Tracker.exe"
link
check "a real file at a link path is kept" "$(grep -q mine "$app/Advanced Combat Tracker.exe" && [[ ! -L "$app/Advanced Combat Tracker.exe" ]]; echo $?)"
check "a real file at a link path is reported" "$(out_has 'not a package link'; echo $?)"

reset
mkdir -p "$app"
ln -s /elsewhere "$app/Advanced Combat Tracker.exe"
link
check "a foreign link at a link path is kept" "$([[ $(readlink "$app/Advanced Combat Tracker.exe") == /elsewhere ]]; echo $?)"

reset
mkdir -p "$app"
ln -s "$share/app/gone.exe" "$app/Advanced Combat Tracker.exe"
link
check "a stale link into the package is replaced" "$(points_to "$app/Advanced Combat Tracker.exe" "$share/app/Advanced Combat Tracker.exe"; echo $?)"

# Whole launcher
run_main() {
  (
    export HOME=$home PROC=$proc ACT_SHARE=$share
    unset ACT_PREFIX ACT_WINE
    "$launcher" "$@"
  ) >"$tmp/out" 2>&1
}
reset
run_main; rc=$?
check "launcher runs ACT through wine" "$((rc == 0 ? 0 : 1))"
check "launcher uses the detected prefix and sync" "$(grep -q "prefix=$prefix fsync=1 esync=" "$RECORD"; echo $?)"
check "launcher joins the detected wineserver" "$(grep -q "server=$wine_a/bin/wineserver" "$RECORD"; echo $?)"
check "launcher starts the installed executable" "$(grep -qF 'args=C:\advanced-combat-tracker\Advanced Combat Tracker.exe' "$RECORD"; echo $?)"
check "launcher runs from the ACT directory" "$(grep -q "cwd=$app " "$RECORD"; echo $?)"

reset; dotnet_reg 00070bf0
run_main; rc=$?
check "launcher without .NET points to --setup" "$((rc == 1 && $(out_has -- '--setup'; echo $?) == 0 ? 0 : 1))"
check "launcher without .NET does not run wine" "$([[ ! -e $RECORD ]]; echo $?)"

reset
run_main --bogus; rc=$?
check "unknown argument is an error" "$((rc == 1 ? 0 : 1))"

reset
fake_wine "$tmp/running"
fake_server 4242 "$tmp/running" "WINEPREFIX=$prefix"
run_main --setup; rc=$?
check "--setup refuses while the game's wineserver runs" "$((rc == 1 && $(out_has 'wineserver is running'; echo $?) == 0 ? 0 : 1))"

# PKGBUILD pins for the local source files
for file in advanced-combat-tracker advanced-combat-tracker.desktop; do
  sum=$(sha256sum "$here/$file" | cut -d' ' -f1)
  check "PKGBUILD pins the current $file" "$(grep -q "'$sum'" "$here/PKGBUILD"; echo $?)"
done

((failures == 0)) && echo "all tests passed" || echo "$failures test(s) failed"
exit $((failures > 0))
