#!/usr/bin/env bash
set -Eeuo pipefail

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export WINEDEBUG="${WINEDEBUG:--all}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
export MESA_LOADER_DRIVER_OVERRIDE="${MESA_LOADER_DRIVER_OVERRIDE:-llvmpipe}"
export MALLOC_ARENA_MAX="${MALLOC_ARENA_MAX:-2}"

LOG_DIR=/data/logs
mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

find_steam() {
  if [[ -s /data/steam-exe-path.txt ]]; then
    local saved
    saved="$(cat /data/steam-exe-path.txt)"
    [[ -f "$saved" ]] && { printf '%s\n' "$saved"; return 0; }
  fi

  find "$WINEPREFIX/drive_c" -type f -iname 'steam.exe' -print -quit 2>/dev/null
}

steam_running() {
  pgrep -fi 'steam\.exe' >/dev/null 2>&1 || \
  pgrep -fi 'steamwebhelper\.exe' >/dev/null 2>&1
}

launch_steam() {
  local steam_exe
  steam_exe="$(find_steam)"
  if [[ -z "$steam_exe" ]]; then
    log "Steam.exe not found; watchdog cannot launch Steam."
    return 1
  fi

  printf '%s\n' "$steam_exe" > /data/steam-exe-path.txt

  local -a flags=()
  if [[ "${LOW_MEMORY:-1}" == "1" ]]; then
    flags+=("-no-cef-sandbox" "-cef-disable-gpu" "-cef-disable-gpu-compositing")
  fi
  if [[ "${STEAM_START_SILENT:-0}" == "1" ]]; then
    flags+=("-silent")
  fi

  log "Launching Steam: $steam_exe ${flags[*]}"
  wine "$steam_exe" "${flags[@]}" >>"$LOG_DIR/steam.log" 2>&1 &
}

launch_steam || exit 0

# Steam can replace/restart itself during first update.
sleep 75

while true; do
  if ! steam_running; then
    log "Steam process not found; waiting 20s before recovery launch..."
    sleep 20
    if ! steam_running; then
      launch_steam || true
      sleep 75
    fi
  fi
  sleep 30
done
