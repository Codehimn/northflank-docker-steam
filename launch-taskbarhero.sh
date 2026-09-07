#!/usr/bin/env bash
set -Eeuo pipefail
export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
APPID="${TASKBARHERO_APPID:-3678970}"

if [[ -s /data/steam-exe-path.txt ]]; then
  STEAM_EXE="$(cat /data/steam-exe-path.txt)"
else
  STEAM_EXE="$(find "$WINEPREFIX/drive_c" -type f -iname 'steam.exe' -print -quit 2>/dev/null)"
fi

[[ -n "${STEAM_EXE:-}" && -f "$STEAM_EXE" ]] || {
  echo "Steam.exe not found." >&2
  exit 1
}
wine "$STEAM_EXE" -applaunch "$APPID"
