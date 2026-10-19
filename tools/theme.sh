#!/usr/bin/env bash
# Push a theme (a folder with config.json and optionally wallpaper.jpg) to the launcher on the TV and
# restart Home so it picks it up. The launcher reads the files from its external files directory and
# overlays config.json on its built-in config.xml; see themes/README.md for the keys.
#
# Usage: TV_HOST=192.168.1.50 tools/theme.sh themes/aurora
#        TV_HOST=192.168.1.50 tools/theme.sh --reset        # remove the overlay, back to config.xml
set -euo pipefail
# Make a relative theme folder absolute before changing directory, so "themes/aurora" means the folder next to
# where the user ran this. pwd -W gives the C:/ form Windows Python needs under Git Bash; plain bash has no -W.
if [ -n "${1:-}" ] && [ "$1" != --reset ]; then
  [ -d "$1" ] || { echo "no such theme folder: $1" >&2; exit 1; }
  THEME_ARG=$(cd "$1" && { pwd -W 2>/dev/null || pwd; })
else
  THEME_ARG=${1:-}
fi
cd "$(dirname "$0")"
: "${TV_HOST:?set TV_HOST to the TV IP address, e.g. TV_HOST=192.168.1.50 $0 themes/aurora}"
PY=venv/bin/python
[ -x "$PY" ] || PY=venv/Scripts/python.exe
[ -x "$PY" ] || { echo "run: python3 -m venv tools/venv && tools/venv/bin/pip install -r tools/requirements.txt" >&2; exit 1; }
export MSYS_NO_PATHCONV=1
PKG=com.gathin.tvhome
DIR=/sdcard/Android/data/$PKG/files
tv() { "$PY" -I tv.py "$@"; }

if [ "${1:-}" = --reset ]; then
  tv "rm -f $DIR/config.json $DIR/wallpaper.jpg; am force-stop $PKG; am start -n $PKG/.MainActivity >/dev/null; echo reset" | tail -n 1
  exit 0
fi
THEME="${THEME_ARG:?usage: theme.sh <theme folder> | --reset}"
[ -f "$THEME/config.json" ] || { echo "no config.json in $THEME" >&2; exit 1; }
# The venv's Python, not whatever python3 is on the PATH (Git Bash on Windows often has none). utf-8-sig, because
# the launcher accepts a BOM at the top of config.json and a check that refused it would turn good themes away.
if ! JSON_ERR=$("$PY" -I -c 'import json,sys; json.load(open(sys.argv[1], encoding="utf-8-sig"))' "$THEME/config.json" 2>&1); then
  echo "$THEME/config.json is not valid JSON: $(printf '%s' "$JSON_ERR" | tail -n 1)" >&2
  exit 1
fi

tv "mkdir -p $DIR" >/dev/null
tv --push "$THEME/config.json" "$DIR/config.json"
if [ -f "$THEME/wallpaper.jpg" ]; then
  "$PY" -I b64push.py "$THEME/wallpaper.jpg" "$DIR/wallpaper.jpg"
else
  tv "rm -f $DIR/wallpaper.jpg" >/dev/null
fi
tv "am force-stop $PKG; am start -n $PKG/.MainActivity >/dev/null; echo applied" | tail -n 1
echo "Theme $(basename "$THEME") is on the TV. Undo with: tools/theme.sh --reset"
