#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:--all}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"

LOG_DIR=/data/logs
STEAM_EXE="$WINEPREFIX/drive_c/Program Files (x86)/Steam/Steam.exe"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

steam_running() {
  pgrep -f '[Ss]team\.exe' >/dev/null 2>&1 || \
  pgrep -f '[Ss]teamwebhelper\.exe' >/dev/null 2>&1
}

launch_steam() {
  local -a flags=()

  if [[ "${LOW_MEMORY:-1}" == "1" ]]; then
    flags+=("-no-cef-sandbox" "-cef-disable-gpu" "-cef-disable-gpu-compositing")
  fi

  if [[ "${STEAM_START_SILENT:-0}" == "1" ]]; then
    flags+=("-silent")
  fi

  log "Launching Steam Windows: ${flags[*]:-no extra flags}"
  wine "$STEAM_EXE" "${flags[@]}" >>"$LOG_DIR/steam.log" 2>&1 &
}

launch_steam
sleep 60

while true; do
  if ! steam_running; then
    log "Steam process missing; waiting 15 seconds before restart..."
    sleep 15
    if ! steam_running; then
      launch_steam
      sleep 60
    fi
  fi
  sleep 30
done
