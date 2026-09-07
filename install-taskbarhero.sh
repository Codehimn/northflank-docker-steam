#!/usr/bin/env bash
set -Eeuo pipefail
export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
APPID="${TASKBARHERO_APPID:-3678970}"
wine start "steam://install/$APPID"
