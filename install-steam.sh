#!/usr/bin/env bash
set -u

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=}"

LOG_DIR=/data/logs
INSTALLER=/opt/installers/SteamSetup.exe
mkdir -p "$LOG_DIR"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

find_steam() {
  find "$WINEPREFIX/drive_c" \
    -type f \
    -iname 'steam.exe' \
    -print \
    -quit 2>/dev/null
}

STEAM_EXE="$(find_steam)"
if [[ -n "$STEAM_EXE" ]]; then
  log "Steam already installed: $STEAM_EXE"
  printf '%s\n' "$STEAM_EXE" > /data/steam-exe-path.txt
  exit 0
fi

if [[ ! -s "$INSTALLER" ]]; then
  log "ERROR: SteamSetup.exe is missing."
  exit 1
fi

log "Running SteamSetup.exe silently (attempt 1)..."
rm -f "$LOG_DIR/steam-installer.log"

# Do not trust installer exit code alone. Some Windows installers spawn another
# process and return early/non-zero. The authoritative check is whether Steam.exe appears.
timeout 120s wine "$INSTALLER" /S >>"$LOG_DIR/steam-installer.log" 2>&1
RC=$?
log "Silent installer exit code: $RC"

for i in $(seq 1 30); do
  STEAM_EXE="$(find_steam)"
  if [[ -n "$STEAM_EXE" ]]; then
    log "Steam installed: $STEAM_EXE"
    printf '%s\n' "$STEAM_EXE" > /data/steam-exe-path.txt
    exit 0
  fi
  sleep 1
done

log "Steam.exe not found after first silent attempt."
log "Trying silent installer once more..."
timeout 120s wine "$INSTALLER" /S >>"$LOG_DIR/steam-installer.log" 2>&1
RC=$?
log "Second silent installer exit code: $RC"

for i in $(seq 1 30); do
  STEAM_EXE="$(find_steam)"
  if [[ -n "$STEAM_EXE" ]]; then
    log "Steam installed: $STEAM_EXE"
    printf '%s\n' "$STEAM_EXE" > /data/steam-exe-path.txt
    exit 0
  fi
  sleep 1
done

log "Automatic silent install failed. Last installer log lines:"
tail -n 100 "$LOG_DIR/steam-installer.log" || true

# Last-resort fail-safe: open the normal graphical installer in the already
# working noVNC desktop. Never kill the service because of installer behavior.
log "Launching visible Steam installer as fallback..."
wine "$INSTALLER" >>"$LOG_DIR/steam-installer-visible.log" 2>&1 &

exit 1
