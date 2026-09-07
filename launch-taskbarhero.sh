#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export WINEDEBUG="${WINEDEBUG:--all}"

APPID="${TASKBARHERO_APPID:-3678970}"

find_steam() {
  if [[ -s /data/steam-exe-path.txt ]]; then
    local saved
    saved="$(cat /data/steam-exe-path.txt)"
    [[ -f "$saved" ]] && { printf '%s\n' "$saved"; return 0; }
  fi
  find "$WINEPREFIX/drive_c" -type f -iname 'steam.exe' -print -quit 2>/dev/null
}

STEAM_EXE="$(find_steam)"
[[ -n "$STEAM_EXE" ]] || {
  echo "Steam.exe not found." >&2
  exit 1
}

echo "Launching Taskbar Hero through Steam (AppID $APPID)..."
wine "$STEAM_EXE" -applaunch "$APPID"
