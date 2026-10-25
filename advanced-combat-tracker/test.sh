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

# File sync
app=$prefix/drive_c/advanced-combat-tracker
sync() { in_launcher bash -c "source '$launcher'; PREFIX='$prefix'; sync_files"; }
reset
sync
check "sync installs ACT" "$([[ -f $app/Advanced\ Combat\ Tracker.exe ]]; echo $?)"
check "sync installs plugins" "$([[ -f $app/Plugins/FFXIV_ACT_Plugin/FFXIV_ACT_Plugin.dll ]]; echo $?)"
check "first sync reports the enabled plugin" "$(out_has 'Enabled plugin FFXIV_ACT_Plugin'; echo $?)"
sync
check "second sync stays quiet" "$([[ ! -s $tmp/out ]]; echo $?)"

echo user >"$app/user.cfg"
echo changed >"$share/app/Advanced Combat Tracker.exe"
echo stale >"$app/Plugins/FFXIV_ACT_Plugin/old-deucalion.dll"
sync
check "sync updates changed files" "$(grep -q changed "$app/Advanced Combat Tracker.exe"; echo $?)"
check "sync keeps user files in the app directory" "$([[ -f $app/user.cfg ]]; echo $?)"
check "sync removes stale files from plugin directories" "$([[ ! -e $app/Plugins/FFXIV_ACT_Plugin/old-deucalion.dll ]]; echo $?)"

mkdir -p "$app/Plugins/UserPlugin"
echo mine >"$app/Plugins/UserPlugin/p.dll"
rm -r "$share/plugins/FFXIV_ACT_Plugin"
sync
check "sync removes plugins that are no longer packaged" "$([[ ! -e $app/Plugins/FFXIV_ACT_Plugin ]]; echo $?)"
check "sync keeps plugins it does not own" "$([[ -f $app/Plugins/UserPlugin/p.dll ]]; echo $?)"

# Plugin registration in ACT's config
cfgdir=$prefix/drive_c/users/$(id -un)/AppData/Roaming/Advanced\ Combat\ Tracker/Config
cfg=$prefix/drive_c/users/$(id -un)/AppData/Roaming/Advanced\ Combat\ Tracker/Config/Advanced\ Combat\ Tracker.config.xml
entry='Path="C:\advanced-combat-tracker\Plugins\FFXIV_ACT_Plugin\FFXIV_ACT_Plugin.dll"'
reset; sync
check "a missing ACT config is created with the plugin enabled" "$(grep -qF "<Plugin Enabled=\"True\" $entry />" "$cfg"; echo $?)"
check "the created config is UTF-8 with a BOM and CRLF" "$([[ $(head -c 3 "$cfg" | xxd -p) == efbbbf ]] && grep -q $'\r' "$cfg"; echo $?)"

reset; mkdir -p "$cfgdir"
printf '\xef\xbb\xbf<?xml version="1.0"?>\r\n<Config>\r\n    <SettingsSerializer>\r\n        <CheckBox Name="a" Value="True" />\r\n    </SettingsSerializer>\r\n    <ActPlugins>\r\n        <Plugin Enabled="True" Path="C:\\other.dll" />\r\n    </ActPlugins>\r\n</Config>\r\n' >"$cfg"
sync
check "an existing config gains the plugin" "$(grep -qF "$entry" "$cfg"; echo $?)"
check "an existing config keeps its other plugins" "$(grep -qF 'Path="C:\other.dll"' "$cfg"; echo $?)"
check "an existing config keeps its settings" "$(grep -qF '<CheckBox Name="a" Value="True" />' "$cfg"; echo $?)"
check "an existing config stays well-formed" "$(python3 -I -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$cfg" 2>/dev/null; echo $?)"

reset; mkdir -p "$cfgdir"
printf '<Config>\r\n    <ActPlugins />\r\n</Config>\r\n' >"$cfg"
sync
check "an empty plugin section gains the plugin" "$(grep -qF "$entry" "$cfg" && python3 -I -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$cfg"; echo $?)"

reset; mkdir -p "$cfgdir"
printf '<Config>\r\n</Config>\r\n' >"$cfg"
sync
check "a config without a plugin section gains one" "$(grep -qF "$entry" "$cfg" && python3 -I -c "import sys,xml.dom.minidom as m; m.parse(sys.argv[1])" "$cfg"; echo $?)"

reset; sync
sed -i '/FFXIV_ACT_Plugin.dll/d' "$cfg"
sync
check "a plugin the user removed is not re-enabled" "$(grep -qF FFXIV_ACT_Plugin "$cfg"; [[ $? -ne 0 ]]; echo $?)"

reset; sync; before=$(sha256sum "$cfg")
rm "$app/Plugins/FFXIV_ACT_Plugin/.managed-by-pacman"; sync
check "a registered plugin is not added twice" "$([[ $(grep -cF FFXIV_ACT_Plugin.dll "$cfg") == 1 ]]; echo $?)"

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
