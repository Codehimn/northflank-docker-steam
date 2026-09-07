#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export WINEARCH=wow64
export WINEDEBUG="${WINEDEBUG:--all}"

APPID="${TASKBARHERO_APPID:-3678970}"

echo "Requesting Taskbar Hero install through Steam (AppID $APPID)..."
wine start "steam://install/$APPID"
