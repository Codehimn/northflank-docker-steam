#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"

LOG_DIR=/data/logs

log(){ printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }

find_steam(){
  if [[ -s /data/steam-exe-path.txt ]]; then
    local p
    p="$(cat /data/steam-exe-path.txt)"
    [[ -f "$p" ]] && { printf '%s\n' "$p"; return; }
  fi
  find "$WINEPREFIX/drive_c" -type f -iname 'steam.exe' -print -quit 2>/dev/null
}

steam_running(){
  pgrep -fi 'steam\.exe|steamwebhelper\.exe' >/dev/null 2>&1
}

launch_steam(){
  local exe
  exe="$(find_steam)"
  [[ -n "$exe" ]] || { log "Steam.exe not found."; return 1; }
  printf '%s\n' "$exe" >/data/steam-exe-path.txt

  local -a flags=()
  if [[ "${LOW_MEMORY:-1}" == "1" ]]; then
    flags+=("-no-cef-sandbox" "-cef-disable-gpu" "-cef-disable-gpu-compositing")
  fi
  [[ "${STEAM_START_SILENT:-0}" == "1" ]] && flags+=("-silent")

  log "Launching Steam: $exe ${flags[*]}"
  WINEDEBUG=-all wine "$exe" "${flags[@]}" >>"$LOG_DIR/steam.log" 2>&1 &
}

launch_steam
sleep 75

while true; do
  if ! steam_running; then
    log "Steam not running; retrying in 20 seconds..."
    sleep 20
    steam_running || launch_steam || true
    sleep 75
  fi
  sleep 30
done
