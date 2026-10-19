#!/usr/bin/env bash
# Re-enable every package listed in a debloat file, restore the stock launcher as home and reset
# animation scales. Pass the same list you used with tools/disable.sh.
#
# Usage: TV_HOST=192.168.1.50 tools/restore.sh examples/xiaomi-mi-tv-4a/debloat.txt [stock.launcher.package]
# Without the second argument it looks for a known stock launcher that is currently disabled.
set -euo pipefail
LIST="${1:?usage: restore.sh <debloat list> [stock launcher package]}"
# Make a relative path absolute before changing directory, so it means what it did where the user typed it.
[ -f "$LIST" ] || { echo "ERROR: cannot read $LIST" >&2; exit 1; }
LIST="$(cd "$(dirname "$LIST")" && pwd)/$(basename "$LIST")"
cd "$(dirname "$0")/.."
PY=tools/venv/bin/python
[ -x "$PY" ] || PY=tools/venv/Scripts/python.exe
[ -x "$PY" ] || { echo "run: python3 -m venv tools/venv && tools/venv/bin/pip install -r tools/requirements.txt" >&2; exit 1; }
export MSYS_NO_PATHCONV=1
. tools/pkglist.sh
PKGS=$(pkg_list "$LIST")   # exits here, before touching the TV, if the list is not clean
STOCK="${2:-}"
if [ -z "$STOCK" ]; then
  # Google TV's stock launcher is not the Android TV one; guessing wrong leaves it disabled.
  DISABLED=$("$PY" -I tools/tv.py 'pm list packages -d' | tr -d '\r')
  STOCK=com.google.android.tvlauncher
  for c in com.google.android.apps.tv.launcherx com.google.android.tvlauncher com.google.android.leanbacklauncher; do
    # Whole-line match: "package:...leanbacklauncher" is also the start of "...leanbacklauncher.recommendations",
    # which every Android TV list disables, so a substring test would pick a launcher that is still enabled.
    if grep -qxF "package:$c" <<<"$DISABLED"; then STOCK=$c; break; fi
  done
  echo "Stock launcher: $STOCK (pass it as the second argument to choose another)"
fi
printf '%s\n' "$STOCK" | grep -qxE '[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+' || { echo "ERROR: '$STOCK' is not a package name" >&2; exit 1; }
{
  # The stock launcher goes first: enabling the setup wizard (often in the list) while no stock launcher
  # is enabled lets the wizard take over Home. It is set as Home again at the end, because Android drops
  # the Home preference whenever the set of Home apps changes.
  echo "pm enable --user 0 $STOCK"
  printf '%s\n' "$PKGS" | awk '{print "pm enable --user 0 " $1}'
  echo "pm enable --user 0 $STOCK"
  # resolve the stock HOME component on the TV (Android 9 needs pkg/activity, not just pkg)
  echo "c=\$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME $STOCK | tail -n 1); case \"\$c\" in */*) cmd package set-home-activity --user 0 \"\$c\" ;; *) echo \"could not resolve a Home activity for $STOCK\" ;; esac"
  echo "settings put global window_animation_scale 1.0"
  echo "settings put global transition_animation_scale 1.0"
  echo "settings put global animator_duration_scale 1.0"
  echo "pm list packages -d"
} | "$PY" -I tools/tv.py --batch
