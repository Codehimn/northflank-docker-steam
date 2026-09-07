#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export WINEARCH=wow64
export WINEDEBUG="${WINEDEBUG:--all}"

APPID="${TASKBARHERO_APPID:-3678970}"
STEAM_EXE="$WINEPREFIX/drive_c/Program Files (x86)/Steam/Steam.exe"

[[ -f "$STEAM_EXE" ]] || {
  echo "Steam.exe not found at: $STEAM_EXE" >&2
  exit 1
}

echo "Launching Taskbar Hero through Steam (AppID $APPID)..."
wine "$STEAM_EXE" -applaunch "$APPID"
