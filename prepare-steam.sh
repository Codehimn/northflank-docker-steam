#!/usr/bin/env bash
set -u

export DISPLAY="${DISPLAY:-:99}"
export HOME="${HOME:-/home/steamuser}"
export WINEPREFIX="${WINEPREFIX:-/data/wineprefix}"

LOG_DIR=/data/logs
mkdir -p "$LOG_DIR"

log(){ printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }

run_test(){
  local exe="$1" expected="$2" logfile="$3"
  rm -f "$logfile"
  WINEDEBUG=+seh,+module wine "$exe" >"$logfile" 2>&1
  local rc=$?
  if grep -q "$expected" "$logfile"; then
    return 0
  fi
  log "Test failed: $exe (exit $rc)"
  tail -n 120 "$logfile" || true
  return 1
}

log "=== WINDOWS PE COMPATIBILITY CHECK ==="

if run_test /opt/tests/pe64-test.exe PE64_OK "$LOG_DIR/pe64-test.log"; then
  log "PE64 TEST: OK"
else
  log "PE64 TEST: FAILED"
  return 1 2>/dev/null || exit 1
fi

if run_test /opt/tests/pe32-test.exe PE32_OK "$LOG_DIR/pe32-test.log"; then
  log "PE32 TEST: OK"
else
  log "PE32 TEST: FAILED"
  log "Wine new-WoW64 cannot execute a minimal 32-bit Windows program in this runtime."
  log "SteamSetup.exe and the Windows Steam bootstrapper are therefore not viable here."
  return 1 2>/dev/null || exit 1
fi

find_steam(){
  find "$WINEPREFIX/drive_c" -type f -iname 'steam.exe' -print -quit 2>/dev/null
}

STEAM_EXE="$(find_steam)"
if [[ -n "$STEAM_EXE" ]]; then
  log "Steam already present: $STEAM_EXE"
  printf '%s\n' "$STEAM_EXE" >/data/steam-exe-path.txt
  exit 0
fi

INSTALLER=/opt/installers/SteamSetup.exe
EXTRACT_DIR=/data/steam-bootstrap-extracted

log "Attempting installer-free Steam bootstrap extraction..."
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"

# 7-Zip can often unpack NSIS installers. This bypasses the installer code itself.
if 7zz x -y -o"$EXTRACT_DIR" "$INSTALLER" >"$LOG_DIR/steam-extract.log" 2>&1; then
  EXTRACTED_STEAM="$(find "$EXTRACT_DIR" -type f -iname 'steam.exe' -print -quit 2>/dev/null)"
  if [[ -n "$EXTRACTED_STEAM" ]]; then
    TARGET_DIR="$WINEPREFIX/drive_c/Steam"
    mkdir -p "$TARGET_DIR"
    cp -a "$(dirname "$EXTRACTED_STEAM")/." "$TARGET_DIR/"
    STEAM_EXE="$TARGET_DIR/Steam.exe"
    if [[ -f "$STEAM_EXE" ]]; then
      log "Extracted Steam bootstrapper directly: $STEAM_EXE"
      printf '%s\n' "$STEAM_EXE" >/data/steam-exe-path.txt
      exit 0
    fi
  fi
fi

log "Direct extraction did not produce Steam.exe."
tail -n 80 "$LOG_DIR/steam-extract.log" 2>/dev/null || true

log "Trying SteamSetup.exe directly with diagnostic Wine logging..."
rm -f "$LOG_DIR/steam-installer.log"
timeout 90s env WINEDEBUG=+seh,+module wine "$INSTALLER" /S >"$LOG_DIR/steam-installer.log" 2>&1
RC=$?
log "SteamSetup.exe exit code: $RC"

sleep 5
STEAM_EXE="$(find_steam)"
if [[ -n "$STEAM_EXE" ]]; then
  log "Steam installed: $STEAM_EXE"
  printf '%s\n' "$STEAM_EXE" >/data/steam-exe-path.txt
  exit 0
fi

log "SteamSetup.exe still did not create Steam.exe."
log "Last installer diagnostics:"
tail -n 160 "$LOG_DIR/steam-installer.log" || true
exit 1
