#!/usr/bin/env bash
# Offline tests for the act-overlay-plugin config template. Usage: test.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
cfg=$here/RainbowMage.OverlayPlugin.config.json

failures=0
check() { # DESCRIPTION EXIT-STATUS
  if (($2 == 0)); then
    echo "ok   $1"
  else
    echo "FAIL $1"
    failures=$((failures + 1))
  fi
}
json() { python3 -I -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); $1" "$cfg"; }

sum=$(sha256sum "$cfg" | cut -d' ' -f1)
check "PKGBUILD pins the current config template" "$(grep -q "'$sum'" "$here/PKGBUILD"; echo $?)"
check "the template is valid JSON" "$(json 'pass' 2>/dev/null; echo $?)"
check "the template turns the plugin's update check off" "$(json 'assert d["UpdateCheck"] is False' 2>/dev/null; echo $?)"
check "the template has one overlay at a neutral geometry" "$(json 'o=d["Overlays"]; assert len(o)==1 and o[0]["Position"]=="20, 20" and o[0]["Size"]=="1200, 300"' 2>/dev/null; echo $?)"
check "the template carries no per-user timestamp" "$(json 'assert "LastUpdateCheck" not in d' 2>/dev/null; echo $?)"

((failures == 0)) && echo "all tests passed" || echo "$failures test(s) failed"
exit $((failures > 0))
